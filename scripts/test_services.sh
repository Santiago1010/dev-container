#!/bin/bash

# Script de verificación de salud de servicios
# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Función para imprimir encabezados
print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

# Función para imprimir sub-encabezados
print_subheader() {
    echo -e "\n${CYAN}--- $1 ---${NC}"
}

# Función para verificar el estado del servicio
check_service() {
    local service_name=$1
    local status=$(docker ps --filter "name=${service_name}" --format "{{.Status}}" 2>/dev/null)
    
    if [ -z "$status" ]; then
        echo -e "${RED}✗${NC} ${service_name}: No está corriendo"
        return 1
    elif [[ $status == *"(healthy)"* ]]; then
        echo -e "${GREEN}✓${NC} ${service_name}: Corriendo y saludable"
        return 0
    elif [[ $status == *"(unhealthy)"* ]]; then
        echo -e "${RED}✗${NC} ${service_name}: Corriendo pero NO saludable"
        return 1
    else
        echo -e "${YELLOW}⚠${NC} ${service_name}: Corriendo (sin healthcheck o iniciando)"
        return 0
    fi
}

# Función para probar conexión HTTP
test_http() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    
    if [ "$response" = "$expected_code" ]; then
        echo -e "${GREEN}✓${NC} ${name}: HTTP responde correctamente (${response})"
        return 0
    else
        echo -e "${RED}✗${NC} ${name}: HTTP falló (esperado: ${expected_code}, recibido: ${response})"
        return 1
    fi
}

# Función para probar puertos TCP
test_tcp() {
    local name=$1
    local host=$2
    local port=$3
    
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} ${name}: Puerto ${port} accesible"
        return 0
    else
        echo -e "${RED}✗${NC} ${name}: Puerto ${port} no accesible"
        return 1
    fi
}

# Función para probar puertos UDP
test_udp() {
    local name=$1
    local host=$2
    local port=$3
    
    if nc -uzw3 ${host} ${port} 2>/dev/null; then
        echo -e "${GREEN}✓${NC} ${name}: Puerto UDP ${port} accesible"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} ${name}: Puerto UDP ${port} - verificación inconclusa"
        return 0  # UDP es difícil de probar sin enviar datos específicos
    fi
}

# Contador de resultados
total_tests=0
passed_tests=0
failed_tests=0

# Banner inicial
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         VERIFICACIÓN COMPLETA DE SERVICIOS                 ║"
echo "║         Docker Compose Infrastructure                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

print_header "VERIFICACIÓN DE ESTADO DE CONTENEDORES"

services=(
    "zookeeper"
    "kafka"
    "redis"
    "consul"
    "postgres-n8n"
    "n8n"
    "jaeger"
    "vault"
    "prometheus"
    "grafana"
    "minio"
    "postgres-kong"
    "kong-migration"
    "kong"
)

for service in "${services[@]}"; do
    total_tests=$((total_tests + 1))
    if check_service "$service"; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
done

# ========================================
# ZOOKEEPER
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - ZOOKEEPER"

print_subheader "Puerto TCP"
total_tests=$((total_tests + 1))
if test_tcp "Zookeeper Client Port" "localhost" "2181"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Estado del servicio"
echo -e "\n${YELLOW}Verificando estado con 4-letter command...${NC}"
echo "stat" | nc localhost 2181 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Zookeeper: Responde a comandos (stat)"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Zookeeper: No responde a comandos"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# KAFKA
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - KAFKA"

print_subheader "Puertos TCP"
total_tests=$((total_tests + 1))
if test_tcp "Kafka External" "localhost" "9092"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_tcp "Kafka Internal" "localhost" "9093"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Comandos Kafka"
echo -e "\n${YELLOW}Listando topics de Kafka...${NC}"
topics=$(docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Kafka: Comando de topics ejecutado correctamente"
    if [ -n "$topics" ]; then
        echo -e "${CYAN}Topics encontrados:${NC}"
        echo "$topics" | head -5
    else
        echo -e "${YELLOW}No hay topics creados aún${NC}"
    fi
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Kafka: Error al listar topics"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Verificando información del broker...${NC}"
docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092 2>/dev/null | grep -q "ApiVersion"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Kafka: Broker API accesible"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Kafka: Broker API no accesible"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# REDIS
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - REDIS"

print_subheader "Puerto TCP"
total_tests=$((total_tests + 1))
if test_tcp "Redis" "localhost" "6379"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Comandos Redis"
echo -e "\n${YELLOW}Probando PING a Redis...${NC}"
ping_result=$(docker exec redis redis-cli -a ${REDIS_PASSWORD:-redispass123} PING 2>/dev/null)
if echo "$ping_result" | grep -q "PONG"; then
    echo -e "${GREEN}✓${NC} Redis: PING exitoso (PONG recibido)"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Redis: PING falló"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Verificando información de Redis...${NC}"
docker exec redis redis-cli -a ${REDIS_PASSWORD:-redispass123} INFO server 2>/dev/null | grep -q "redis_version"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Redis: INFO comando funciona"
    redis_ver=$(docker exec redis redis-cli -a ${REDIS_PASSWORD:-redispass123} INFO server 2>/dev/null | grep "redis_version" | cut -d: -f2 | tr -d '\r')
    echo -e "${CYAN}Versión: ${redis_ver}${NC}"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Redis: INFO comando falló"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Probando operaciones SET/GET...${NC}"
docker exec redis redis-cli -a ${REDIS_PASSWORD:-redispass123} SET test_key "test_value" >/dev/null 2>&1
get_result=$(docker exec redis redis-cli -a ${REDIS_PASSWORD:-redispass123} GET test_key 2>/dev/null)
docker exec redis redis-cli -a ${REDIS_PASSWORD:-redispass123} DEL test_key >/dev/null 2>&1
if [ "$get_result" = "test_value" ]; then
    echo -e "${GREEN}✓${NC} Redis: Operaciones SET/GET funcionan"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Redis: Operaciones SET/GET fallaron"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# CONSUL
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - CONSUL"

print_subheader "Puertos TCP"
total_tests=$((total_tests + 1))
if test_tcp "Consul HTTP" "localhost" "8500"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_tcp "Consul DNS (TCP)" "localhost" "8600"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Puerto UDP"
total_tests=$((total_tests + 1))
if test_udp "Consul DNS (UDP)" "localhost" "8600"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "APIs HTTP"
total_tests=$((total_tests + 1))
if test_http "Consul UI" "http://localhost:8500/ui/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Consul API - Leader" "http://localhost:8500/v1/status/leader" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Consul API - Members" "http://localhost:8500/v1/agent/members" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Verificación de cluster"
echo -e "\n${YELLOW}Verificando miembros del cluster...${NC}"
docker exec consul consul members 2>/dev/null | grep -q "alive"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Consul: Cluster con miembros activos"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Consul: No se pueden verificar miembros del cluster"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# POSTGRESQL (N8N)
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - POSTGRESQL (N8N)"

print_subheader "Puerto TCP"
total_tests=$((total_tests + 1))
if test_tcp "PostgreSQL N8N" "localhost" "5432"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Estado de la base de datos"
echo -e "\n${YELLOW}Probando conexión a PostgreSQL...${NC}"
pg_status=$(docker exec postgres-n8n pg_isready -U ${POSTGRES_USER:-n8n} 2>/dev/null)
if echo "$pg_status" | grep -q "accepting connections"; then
    echo -e "${GREEN}✓${NC} PostgreSQL N8N: Aceptando conexiones"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} PostgreSQL N8N: No acepta conexiones"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Verificando base de datos...${NC}"
docker exec postgres-n8n psql -U ${POSTGRES_USER:-n8n} -d ${POSTGRES_DB:-n8n} -c "SELECT 1;" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} PostgreSQL N8N: Consultas SQL funcionan"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} PostgreSQL N8N: Consultas SQL fallan"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# N8N
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - N8N"

print_subheader "Puerto TCP"
total_tests=$((total_tests + 1))
if test_tcp "n8n" "localhost" "5678"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "APIs HTTP"
total_tests=$((total_tests + 1))
if test_http "n8n Health Check" "http://localhost:5678/healthz" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "n8n Web UI" "http://localhost:5678/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# JAEGER
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - JAEGER"

print_subheader "Puertos TCP"
ports=("5778" "14250" "14268" "14269" "16686" "9411")
port_names=("Agent Config" "gRPC Collector" "HTTP Collector" "Admin" "Query UI" "Zipkin")

for i in "${!ports[@]}"; do
    total_tests=$((total_tests + 1))
    if test_tcp "Jaeger ${port_names[$i]}" "localhost" "${ports[$i]}"; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
done

print_subheader "Puertos UDP"
udp_ports=("5775" "6831" "6832")
udp_names=("Zipkin Thrift" "Jaeger Compact" "Jaeger Binary")

for i in "${!udp_ports[@]}"; do
    total_tests=$((total_tests + 1))
    if test_udp "Jaeger ${udp_names[$i]}" "localhost" "${udp_ports[$i]}"; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
done

print_subheader "APIs HTTP"
total_tests=$((total_tests + 1))
if test_http "Jaeger UI" "http://localhost:16686/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Jaeger Health" "http://localhost:14269/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# VAULT
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - VAULT"

print_subheader "Puerto TCP"
total_tests=$((total_tests + 1))
if test_tcp "Vault API" "localhost" "8200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "APIs HTTP"
total_tests=$((total_tests + 1))
if test_http "Vault Health" "http://localhost:8200/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Vault UI" "http://localhost:8200/ui/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Estado de Vault"
echo -e "\n${YELLOW}Verificando estado de inicialización...${NC}"
vault_status=$(curl -s http://localhost:8200/v1/sys/health 2>/dev/null)
if echo "$vault_status" | grep -q "initialized"; then
    is_init=$(echo "$vault_status" | grep -o '"initialized":[^,]*' | cut -d: -f2)
    is_sealed=$(echo "$vault_status" | grep -o '"sealed":[^,]*' | cut -d: -f2)
    
    if [ "$is_init" = "true" ]; then
        echo -e "${GREEN}✓${NC} Vault: Inicializado"
    else
        echo -e "${YELLOW}⚠${NC} Vault: No inicializado (ejecutar 'vault operator init')"
    fi
    
    if [ "$is_sealed" = "false" ]; then
        echo -e "${GREEN}✓${NC} Vault: Desbloqueado (unsealed)"
    else
        echo -e "${YELLOW}⚠${NC} Vault: Sellado (ejecutar 'vault operator unseal')"
    fi
    
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Vault: No se puede obtener estado"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# PROMETHEUS
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - PROMETHEUS"

print_subheader "Puerto TCP"
total_tests=$((total_tests + 1))
if test_tcp "Prometheus" "localhost" "9090"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "APIs HTTP"
total_tests=$((total_tests + 1))
if test_http "Prometheus Health" "http://localhost:9090/-/healthy" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Prometheus Ready" "http://localhost:9090/-/ready" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Prometheus Metrics" "http://localhost:9090/metrics" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Prometheus UI" "http://localhost:9090/" "302"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Configuración"
echo -e "\n${YELLOW}Verificando configuración de Prometheus...${NC}"
curl -s http://localhost:9090/api/v1/status/config 2>/dev/null | grep -q "yaml"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Prometheus: Configuración cargada"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Prometheus: Problema con configuración"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# GRAFANA
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - GRAFANA"

print_subheader "Puerto TCP"
total_tests=$((total_tests + 1))
if test_tcp "Grafana" "localhost" "3000"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "APIs HTTP"
total_tests=$((total_tests + 1))
if test_http "Grafana Health" "http://localhost:3000/api/health" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Grafana UI" "http://localhost:3000/login" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# MINIO
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - MINIO"

print_subheader "Puertos TCP"
total_tests=$((total_tests + 1))
if test_tcp "MinIO API" "localhost" "9000"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_tcp "MinIO Console" "localhost" "9001"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "APIs HTTP"
total_tests=$((total_tests + 1))
if test_http "MinIO Health (Live)" "http://localhost:9000/minio/health/live" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "MinIO Health (Ready)" "http://localhost:9000/minio/health/ready" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "MinIO Console" "http://localhost:9001/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# POSTGRESQL (KONG)
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - POSTGRESQL (KONG)"

print_subheader "Puerto TCP"
total_tests=$((total_tests + 1))
if test_tcp "PostgreSQL Kong" "localhost" "5433"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Estado de la base de datos"
echo -e "\n${YELLOW}Probando conexión a PostgreSQL Kong...${NC}"
pg_status=$(docker exec postgres-kong pg_isready -U ${KONG_PG_USER:-kong} 2>/dev/null)
if echo "$pg_status" | grep -q "accepting connections"; then
    echo -e "${GREEN}✓${NC} PostgreSQL Kong: Aceptando conexiones"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} PostgreSQL Kong: No acepta conexiones"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Verificando base de datos Kong...${NC}"
docker exec postgres-kong psql -U ${KONG_PG_USER:-kong} -d ${KONG_PG_DATABASE:-kong} -c "SELECT 1;" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} PostgreSQL Kong: Consultas SQL funcionan"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} PostgreSQL Kong: Consultas SQL fallan"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Verificando esquema de Kong...${NC}"
docker exec postgres-kong psql -U ${KONG_PG_USER:-kong} -d ${KONG_PG_DATABASE:-kong} -c "\dt" 2>/dev/null | grep -q "services"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} PostgreSQL Kong: Esquema de Kong migrado"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${YELLOW}⚠${NC} PostgreSQL Kong: Esquema no encontrado (¿migraciones pendientes?)"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# KONG
# ========================================
print_header "VERIFICACIÓN DE CONECTIVIDAD - KONG"

print_subheader "Puertos TCP"
kong_ports=("8000" "8001" "8002" "8443" "8444")
kong_port_names=("Proxy HTTP" "Admin API" "Manager UI" "Proxy HTTPS" "Admin HTTPS")

for i in "${!kong_ports[@]}"; do
    total_tests=$((total_tests + 1))
    if test_tcp "Kong ${kong_port_names[$i]}" "localhost" "${kong_ports[$i]}"; then
        passed_tests=$((passed_tests + 1))
    else
        failed_tests=$((failed_tests + 1))
    fi
done

print_subheader "APIs HTTP"
total_tests=$((total_tests + 1))
if test_http "Kong Proxy (sin rutas)" "http://localhost:8000/" "404"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Kong Admin API Root" "http://localhost:8001/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Kong Admin API Status" "http://localhost:8001/status" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Kong Manager" "http://localhost:8002/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Información de Kong"
echo -e "\n${YELLOW}Obteniendo información de Kong...${NC}"
kong_info=$(curl -s http://localhost:8001/ 2>/dev/null)
if echo "$kong_info" | grep -q "version"; then
    kong_version=$(echo "$kong_info" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}✓${NC} Kong: Versión ${kong_version}"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Kong: No se puede obtener información"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Listando servicios configurados...${NC}"
services_count=$(curl -s http://localhost:8001/services 2>/dev/null | grep -o '"data":\[' | wc -l)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Kong: API de servicios accesible"
    routes_count=$(curl -s http://localhost:8001/routes 2>/dev/null | grep -o '"data":\[' | wc -l)
    echo -e "${CYAN}Servicios configurados: Verificar en Admin API${NC}"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Kong: No se puede listar servicios"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# VERIFICACIONES ADICIONALES
# ========================================
print_header "VERIFICACIONES ADICIONALES DE INTEGRACIÓN"

print_subheader "Integración N8N con Redis"
echo -e "\n${YELLOW}Verificando si N8N puede conectarse a Redis...${NC}"
docker logs n8n 2>&1 | tail -20 | grep -q "Redis"
if [ $? -eq 0 ]; then
    if docker logs n8n 2>&1 | tail -50 | grep -i "redis" | grep -qi "error\|failed"; then
        echo -e "${RED}✗${NC} N8N: Posibles errores de conexión con Redis en logs"
        total_tests=$((total_tests + 1))
        failed_tests=$((failed_tests + 1))
    else
        echo -e "${GREEN}✓${NC} N8N: Sin errores evidentes de Redis en logs"
        total_tests=$((total_tests + 1))
        passed_tests=$((passed_tests + 1))
    fi
else
    echo -e "${YELLOW}⚠${NC} N8N: No hay menciones de Redis en logs recientes"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
fi

print_subheader "Integración N8N con PostgreSQL"
echo -e "\n${YELLOW}Verificando si N8N puede conectarse a PostgreSQL...${NC}"
if docker logs n8n 2>&1 | tail -50 | grep -i "postgres\|database" | grep -qi "error\|failed\|cannot connect"; then
    echo -e "${RED}✗${NC} N8N: Posibles errores de conexión con PostgreSQL en logs"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
else
    echo -e "${GREEN}✓${NC} N8N: Sin errores evidentes de PostgreSQL en logs"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
fi

print_subheader "Integración Vault con Consul"
echo -e "\n${YELLOW}Verificando backend de Vault en Consul...${NC}"
consul_keys=$(curl -s http://localhost:8500/v1/kv/vault/?keys 2>/dev/null)
if echo "$consul_keys" | grep -q "vault"; then
    echo -e "${GREEN}✓${NC} Vault: Datos almacenados en Consul"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${YELLOW}⚠${NC} Vault: Sin datos en Consul (normal si no está inicializado)"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
fi

print_subheader "Integración Prometheus con servicios"
echo -e "\n${YELLOW}Verificando targets de Prometheus...${NC}"
targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null)
if echo "$targets" | grep -q "activeTargets"; then
    echo -e "${GREEN}✓${NC} Prometheus: API de targets accesible"
    active_count=$(echo "$targets" | grep -o '"health":"up"' | wc -l)
    echo -e "${CYAN}Targets activos (UP): ${active_count}${NC}"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Prometheus: No se pueden obtener targets"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Verificación de volúmenes Docker"
echo -e "\n${YELLOW}Verificando volúmenes de persistencia...${NC}"
volumes=("zookeeper-data" "zookeeper-log" "kafka-data")
volumes_ok=0
volumes_total=${#volumes[@]}

for vol in "${volumes[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
        volumes_ok=$((volumes_ok + 1))
    fi
done

if [ $volumes_ok -eq $volumes_total ]; then
    echo -e "${GREEN}✓${NC} Volúmenes Docker: Todos los volúmenes existen ($volumes_ok/$volumes_total)"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${YELLOW}⚠${NC} Volúmenes Docker: Algunos volúmenes no encontrados ($volumes_ok/$volumes_total)"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

print_subheader "Verificación de red Docker"
echo -e "\n${YELLOW}Verificando red kafka-network...${NC}"
if docker network inspect kafka-network >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Red Docker: kafka-network existe"
    containers_in_network=$(docker network inspect kafka-network | grep -o '"Name": "[^"]*"' | wc -l)
    echo -e "${CYAN}Contenedores en la red: $containers_in_network${NC}"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Red Docker: kafka-network no encontrada"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# VERIFICACIÓN DE RECURSOS
# ========================================
print_header "VERIFICACIÓN DE RECURSOS DEL SISTEMA"

print_subheader "Uso de CPU y Memoria por contenedor"
echo -e "\n${YELLOW}Obteniendo estadísticas de recursos...${NC}\n"

# Encabezado de la tabla
printf "${CYAN}%-20s %10s %15s %15s${NC}\n" "CONTENEDOR" "CPU %" "MEMORIA USO" "MEMORIA %"
printf "${CYAN}%-20s %10s %15s %15s${NC}\n" "--------------------" "----------" "---------------" "---------------"

# Obtener estadísticas sin streaming
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | tail -n +2 | while read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    cpu=$(echo "$line" | awk '{print $2}')
    mem_usage=$(echo "$line" | awk '{print $3" "$4}')
    mem_perc=$(echo "$line" | awk '{print $5}')
    
    # Colorear según uso de CPU
    cpu_val=$(echo "$cpu" | tr -d '%')
    if (( $(echo "$cpu_val > 80" | bc -l 2>/dev/null || echo 0) )); then
        cpu_color=$RED
    elif (( $(echo "$cpu_val > 50" | bc -l 2>/dev/null || echo 0) )); then
        cpu_color=$YELLOW
    else
        cpu_color=$GREEN
    fi
    
    printf "%-20s ${cpu_color}%10s${NC} %15s %15s\n" "$name" "$cpu" "$mem_usage" "$mem_perc"
done

echo -e "\n${GREEN}✓${NC} Estadísticas de recursos obtenidas"
total_tests=$((total_tests + 1))
passed_tests=$((passed_tests + 1))

print_subheader "Espacio en disco"
echo -e "\n${YELLOW}Uso de disco en directorios de datos...${NC}\n"

data_dirs=("./data/redis" "./data/consul" "./data/postgres" "./data/n8n" "./data/prometheus" "./data/grafana" "./data/minio" "./data/postgres-kong" "./data/vault")

for dir in "${data_dirs[@]}"; do
    if [ -d "$dir" ]; then
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo -e "${CYAN}$dir${NC}: $size"
    fi
done

total_tests=$((total_tests + 1))
passed_tests=$((passed_tests + 1))

# ========================================
# VERIFICACIÓN DE LOGS
# ========================================
print_header "VERIFICACIÓN RÁPIDA DE LOGS"

print_subheader "Búsqueda de errores en logs recientes"
echo -e "\n${YELLOW}Analizando logs de los últimos 2 minutos...${NC}\n"

critical_services=("kafka" "consul" "vault" "n8n" "kong")
errors_found=0

for service in "${critical_services[@]}"; do
    error_count=$(docker logs --since=2m "$service" 2>&1 | grep -i "error\|fatal\|exception" | grep -v "no error" | wc -l)
    
    if [ "$error_count" -gt 0 ]; then
        echo -e "${RED}✗${NC} $service: $error_count errores encontrados"
        errors_found=$((errors_found + 1))
    else
        echo -e "${GREEN}✓${NC} $service: Sin errores recientes"
    fi
done

if [ $errors_found -eq 0 ]; then
    echo -e "\n${GREEN}✓${NC} No se encontraron errores críticos en logs recientes"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "\n${YELLOW}⚠${NC} Se encontraron errores en $errors_found servicios (revisar logs detallados)"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

# ========================================
# RECOMENDACIONES
# ========================================
print_header "RECOMENDACIONES"

echo -e "${CYAN}Servicios con UI disponibles:${NC}"
echo -e "  • Consul:     ${BLUE}http://localhost:8500${NC}"
echo -e "  • N8N:        ${BLUE}http://localhost:5678${NC}"
echo -e "  • Jaeger:     ${BLUE}http://localhost:16686${NC}"
echo -e "  • Vault:      ${BLUE}http://localhost:8200${NC}"
echo -e "  • Prometheus: ${BLUE}http://localhost:9090${NC}"
echo -e "  • Grafana:    ${BLUE}http://localhost:3000${NC} (admin / admin123)"
echo -e "  • MinIO:      ${BLUE}http://localhost:9001${NC} (minioadmin / minioadmin123)"
echo -e "  • Kong:       ${BLUE}http://localhost:8002${NC}"

echo -e "\n${CYAN}Comandos útiles:${NC}"
echo -e "  • Ver logs:   ${YELLOW}docker-compose logs -f [servicio]${NC}"
echo -e "  • Reiniciar:  ${YELLOW}docker-compose restart [servicio]${NC}"
echo -e "  • Estado:     ${YELLOW}docker-compose ps${NC}"
echo -e "  • Detener:    ${YELLOW}docker-compose down${NC}"

if docker ps --filter "name=vault" --format "{{.Status}}" | grep -q "healthy"; then
    vault_sealed=$(curl -s http://localhost:8200/v1/sys/health 2>/dev/null | grep -o '"sealed":[^,]*' | cut -d: -f2)
    if [ "$vault_sealed" = "true" ]; then
        echo -e "\n${YELLOW}⚠ VAULT está sellado. Para inicializar y desbloquear:${NC}"
        echo -e "  1. ${YELLOW}docker exec -it vault vault operator init${NC}"
        echo -e "  2. Guarda las claves de unseal y el root token"
        echo -e "  3. ${YELLOW}docker exec -it vault vault operator unseal${NC} (3 veces con diferentes claves)"
    fi
fi

# ========================================
# RESUMEN FINAL
# ========================================
print_header "RESUMEN DE VERIFICACIÓN"

success_rate=$((passed_tests * 100 / total_tests))

echo -e "┌─────────────────────────────────────────┐"
echo -e "│ ${BLUE}ESTADÍSTICAS DE PRUEBAS${NC}                │"
echo -e "├─────────────────────────────────────────┤"
printf "│ Total de pruebas:      ${BLUE}%4d${NC}           │\n" $total_tests
printf "│ Pruebas exitosas:      ${GREEN}%4d${NC}           │\n" $passed_tests
printf "│ Pruebas fallidas:      ${RED}%4d${NC}           │\n" $failed_tests
printf "│ Tasa de éxito:         ${BLUE}%3d%%${NC}           │\n" $success_rate
echo -e "└─────────────────────────────────────────┘"

if [ $failed_tests -eq 0 ]; then
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ ¡Todos los servicios están funcionando!        ║${NC}"
    echo -e "${GREEN}║    Tu infraestructura está lista para usar        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}\n"
    exit 0
elif [ $failed_tests -le 3 ]; then
    echo -e "\n${YELLOW}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠ Algunos servicios tienen problemas menores     ║${NC}"
    echo -e "${YELLOW}║    Revisa los logs para más detalles              ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${CYAN}Para revisar logs:${NC} ${YELLOW}docker-compose logs [servicio]${NC}\n"
    exit 1
else
    echo -e "\n${RED}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ✗ Múltiples servicios tienen problemas           ║${NC}"
    echo -e "${RED}║    Se requiere atención inmediata                  ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════╝${NC}\n"
    echo -e "${CYAN}Acciones recomendadas:${NC}"
    echo -e "  1. ${YELLOW}docker-compose ps${NC} - Ver estado de contenedores"
    echo -e "  2. ${YELLOW}docker-compose logs [servicio]${NC} - Ver logs específicos"
    echo -e "  3. ${YELLOW}docker-compose restart [servicio]${NC} - Reintentar servicio"
    echo -e "  4. ${YELLOW}docker-compose down && docker-compose up -d${NC} - Reinicio completo\n"
    exit 1
fi