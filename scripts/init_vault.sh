#!/bin/bash

# Script para inicializar y configurar Vault
# Este script debe ejecutarse después de levantar los servicios

set -e

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "  Inicializando HashiCorp Vault"
echo "=========================================="
echo ""

# Esperar a que Vault esté disponible
echo "Esperando a que Vault esté disponible..."
for i in {1..30}; do
    if curl -sf http://localhost:8200/v1/sys/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Vault está disponible"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}✗${NC} Timeout esperando a Vault"
        exit 1
    fi
    echo "Intento $i/30..."
    sleep 2
done
echo ""

# Verificar si Vault ya está inicializado
INIT_STATUS=$(docker exec vault vault status -format=json 2>/dev/null | jq -r '.initialized' 2>/dev/null)

if [ "$INIT_STATUS" = "true" ]; then
    echo -e "${YELLOW}⚠${NC} Vault ya está inicializado"
    echo "Si necesitas reinicializarlo, elimina el directorio ./data/vault/file"
    exit 0
fi

# Inicializar Vault
echo "Inicializando Vault con 5 key shares y threshold de 3..."
INIT_OUTPUT=$(docker exec vault vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json)

# Guardar las claves y el token root
echo "$INIT_OUTPUT" > ./data/vault/vault-keys.json
chmod 600 ./data/vault/vault-keys.json

echo -e "${GREEN}✓${NC} Vault inicializado correctamente"
echo ""
echo -e "${YELLOW}IMPORTANTE:${NC} Las claves de desbloqueo y el token root se han guardado en:"
echo "  ./data/vault/vault-keys.json"
echo ""
echo -e "${RED}⚠ ADVERTENCIA:${NC} Guarda este archivo en un lugar seguro y no lo compartas"
echo ""

# Extraer las primeras 3 claves de desbloqueo
UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

# Desbloquear Vault
echo "Desbloqueando Vault (necesita 3 de 5 claves)..."
docker exec vault vault operator unseal "$UNSEAL_KEY_1" > /dev/null
echo -e "${GREEN}✓${NC} Clave 1/3 aplicada"

docker exec vault vault operator unseal "$UNSEAL_KEY_2" > /dev/null
echo -e "${GREEN}✓${NC} Clave 2/3 aplicada"

docker exec vault vault operator unseal "$UNSEAL_KEY_3" > /dev/null
echo -e "${GREEN}✓${NC} Clave 3/3 aplicada"
echo ""
echo -e "${GREEN}✓${NC} Vault desbloqueado correctamente"
echo ""

# Configurar el token root para usar en comandos
export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN="$ROOT_TOKEN"

# Habilitar el motor de secretos KV v2
echo "Habilitando motor de secretos KV versión 2..."
docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
    vault secrets enable -path=secret kv-v2 2>/dev/null || \
    echo -e "${YELLOW}⚠${NC} Motor KV ya está habilitado"

echo -e "${GREEN}✓${NC} Motor de secretos configurado"
echo ""

# Crear una política de ejemplo
echo "Creando política de ejemplo..."
docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault vault policy write app-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/myapp/*" {
  capabilities = ["list", "read", "delete"]
}
EOF

echo -e "${GREEN}✓${NC} Política 'app-policy' creada"
echo ""

# Crear un secreto de ejemplo
echo "Creando secreto de ejemplo..."
docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
    vault kv put secret/myapp/config \
    username=admin \
    password=supersecret \
    api_key=abc123xyz

echo -e "${GREEN}✓${NC} Secreto de ejemplo creado en secret/myapp/config"
echo ""

# Resumen
echo "=========================================="
echo "  Configuración completada"
echo "=========================================="
echo ""
echo "Vault UI: http://localhost:8200"
echo "Root Token: $ROOT_TOKEN"
echo ""
echo -e "${YELLOW}Comandos útiles:${NC}"
echo ""
echo "# Exportar variables de entorno para usar Vault CLI:"
echo "export VAULT_ADDR='http://localhost:8200'"
echo "export VAULT_TOKEN='$ROOT_TOKEN'"
echo ""
echo "# Ver el secreto de ejemplo:"
echo "docker exec -e VAULT_TOKEN='$ROOT_TOKEN' vault vault kv get secret/myapp/config"
echo ""
echo "# Crear un nuevo secreto:"
echo "docker exec -e VAULT_TOKEN='$ROOT_TOKEN' vault vault kv put secret/myapp/database \\"
echo "  host=postgres \\"
echo "  username=dbuser \\"
echo "  password=dbpass"
echo ""
echo -e "${RED}⚠ RECUERDA:${NC} Guarda el archivo vault-keys.json en un lugar seguro"
echo ""