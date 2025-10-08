#!/bin/bash

# Script de gestión de Vault
# Proporciona comandos útiles para administrar Vault

set -e

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cargar token root si existe
if [ -f "./data/vault/vault-keys.json" ]; then
    ROOT_TOKEN=$(jq -r '.root_token' ./data/vault/vault-keys.json 2>/dev/null)
fi

show_help() {
    echo -e "${BLUE}===========================================\n"
    echo "  Vault Manager - Herramienta de gestión"
    echo -e "\n===========================================${NC}\n"
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos disponibles:"
    echo ""
    echo "  status        - Ver estado de Vault"
    echo "  unseal        - Desbloquear Vault"
    echo "  seal          - Bloquear Vault"
    echo "  token-info    - Ver información del token actual"
    echo "  list-secrets  - Listar todos los secretos"
    echo "  get <path>    - Obtener un secreto"
    echo "  put <path>    - Crear/actualizar secreto (interactivo)"
    echo "  delete <path> - Eliminar un secreto"
    echo "  backup        - Crear backup de Vault"
    echo "  logs          - Ver logs de Vault"
    echo "  ui            - Abrir UI de Vault en el navegador"
    echo "  help          - Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0 status"
    echo "  $0 get secret/myapp/config"
    echo "  $0 put secret/myapp/database"
    echo "  $0 backup"
    echo ""
}

check_vault_running() {
    if ! docker ps | grep -q vault; then
        echo -e "${RED}✗${NC} Vault no está corriendo"
        echo "Ejecuta: docker-compose up -d vault"
        exit 1
    fi
}

check_token() {
    if [ -z "$ROOT_TOKEN" ]; then
        echo -e "${YELLOW}⚠${NC} No se encontró el token root"
        echo "Por favor, inicializa Vault primero: ./scripts/init_vault.sh"
        exit 1
    fi
}

vault_status() {
    check_vault_running
    echo -e "${BLUE}Estado de Vault:${NC}\n"
    docker exec vault vault status || true
    echo ""
    if docker exec vault vault status 2>&1 | grep -q "Sealed.*false"; then
        echo -e "${GREEN}✓${NC} Vault está desbloqueado y listo para usar"
    elif docker exec vault vault status 2>&1 | grep -q "Sealed.*true"; then
        echo -e "${YELLOW}⚠${NC} Vault está bloqueado. Ejecuta: $0 unseal"
    fi
}

vault_unseal() {
    check_vault_running
    
    if [ ! -f "./data/vault/vault-keys.json" ]; then
        echo -e "${RED}✗${NC} No se encontró vault-keys.json"
        echo "Inicializa Vault primero: ./scripts/init_vault.sh"
        exit 1
    fi
    
    echo -e "${BLUE}Desbloqueando Vault...${NC}\n"
    
    UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' ./data/vault/vault-keys.json)
    UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' ./data/vault/vault-keys.json)
    UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' ./data/vault/vault-keys.json)
    
    docker exec vault vault operator unseal "$UNSEAL_KEY_1" > /dev/null
    echo -e "${GREEN}✓${NC} Clave 1/3 aplicada"
    
    docker exec vault vault operator unseal "$UNSEAL_KEY_2" > /dev/null
    echo -e "${GREEN}✓${NC} Clave 2/3 aplicada"
    
    docker exec vault vault operator unseal "$UNSEAL_KEY_3" > /dev/null
    echo -e "${GREEN}✓${NC} Clave 3/3 aplicada"
    
    echo ""
    echo -e "${GREEN}✓${NC} Vault desbloqueado correctamente"
}

vault_seal() {
    check_vault_running
    check_token
    
    echo -e "${YELLOW}⚠${NC} Esto bloqueará Vault. Necesitarás desbloquearlo nuevamente."
    read -p "¿Continuar? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault vault operator seal
        echo -e "${GREEN}✓${NC} Vault bloqueado"
    else
        echo "Cancelado"
    fi
}

token_info() {
    check_vault_running
    check_token
    
    echo -e "${BLUE}Información del token:${NC}\n"
    docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
        vault token lookup -format=json | jq
}

list_secrets() {
    check_vault_running
    check_token
    
    echo -e "${BLUE}Listando secretos:${NC}\n"
    
    # Listar paths en el engine de secretos
    echo -e "${GREEN}Paths disponibles:${NC}"
    docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
        vault kv list -format=json secret/ 2>/dev/null | jq -r '.[]' || \
        echo "No hay secretos aún"
}

get_secret() {
    check_vault_running
    check_token
    
    if [ -z "$1" ]; then
        echo -e "${RED}✗${NC} Debes especificar el path del secreto"
        echo "Uso: $0 get secret/myapp/config"
        exit 1
    fi
    
    echo -e "${BLUE}Obteniendo secreto: $1${NC}\n"
    docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
        vault kv get -format=json "$1" | jq
}

put_secret() {
    check_vault_running
    check_token
    
    if [ -z "$1" ]; then
        echo -e "${RED}✗${NC} Debes especificar el path del secreto"
        echo "Uso: $0 put secret/myapp/config"
        exit 1
    fi
    
    echo -e "${BLUE}Creando/actualizando secreto: $1${NC}\n"
    echo "Ingresa los pares clave=valor (vacío para terminar):"
    
    PAIRS=""
    while true; do
        read -p "Clave=Valor: " pair
        if [ -z "$pair" ]; then
            break
        fi
        PAIRS="$PAIRS $pair"
    done
    
    if [ -z "$PAIRS" ]; then
        echo "No se ingresaron datos"
        exit 1
    fi
    
    docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
        vault kv put "$1" $PAIRS
    
    echo -e "\n${GREEN}✓${NC} Secreto guardado correctamente"
}

delete_secret() {
    check_vault_running
    check_token
    
    if [ -z "$1" ]; then
        echo -e "${RED}✗${NC} Debes especificar el path del secreto"
        echo "Uso: $0 delete secret/myapp/config"
        exit 1
    fi
    
    echo -e "${YELLOW}⚠${NC} Esto eliminará el secreto: $1"
    read -p "¿Continuar? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
            vault kv delete "$1"
        echo -e "${GREEN}✓${NC} Secreto eliminado"
    else
        echo "Cancelado"
    fi
}

vault_backup() {
    check_vault_running
    check_token
    
    BACKUP_DIR="./backups"
    mkdir -p "$BACKUP_DIR"
    
    BACKUP_FILE="vault-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo -e "${BLUE}Creando backup...${NC}\n"
    
    # Backup del directorio de datos
    tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
        ./data/vault/file \
        ./data/vault/vault-keys.json 2>/dev/null || true
    
    echo -e "${GREEN}✓${NC} Backup creado: $BACKUP_DIR/$BACKUP_FILE"
    echo ""
    echo "El backup incluye:"
    echo "  - Datos de Vault (./data/vault/file)"
    echo "  - Claves de desbloqueo (vault-keys.json)"
    echo ""
    echo -e "${YELLOW}⚠${NC} Guarda este archivo en un lugar seguro"
}

vault_logs() {
    check_vault_running
    
    echo -e "${BLUE}Logs de Vault (Ctrl+C para salir):${NC}\n"
    docker-compose logs -f vault
}

open_ui() {
    check_vault_running
    
    echo -e "${BLUE}Abriendo UI de Vault...${NC}\n"
    echo "URL: http://localhost:8200"
    
    if [ -n "$ROOT_TOKEN" ]; then
        echo "Token: $ROOT_TOKEN"
    fi
    
    # Intentar abrir en el navegador
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:8200" 2>/dev/null
    elif command -v open &> /dev/null; then
        open "http://localhost:8200"
    else
        echo ""
        echo "Por favor, abre http://localhost:8200 en tu navegador"
    fi
}

# Main
case "${1:-help}" in
    status)
        vault_status
        ;;
    unseal)
        vault_unseal
        ;;
    seal)
        vault_seal
        ;;
    token-info)
        token_info
        ;;
    list-secrets)
        list_secrets
        ;;
    get)
        get_secret "$2"
        ;;
    put)
        put_secret "$2"
        ;;
    delete)
        delete_secret "$2"
        ;;
    backup)
        vault_backup
        ;;
    logs)
        vault_logs
        ;;
    ui)
        open_ui
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}✗${NC} Comando desconocido: $1"
        echo ""
        show_help
        exit 1
        ;;
esac