#!/bin/bash

# Script de verificación de salud de servicios
# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para imprimir encabezados
print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
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

# Contador de resultados
total_tests=0
passed_tests=0
failed_tests=0

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

# Tests específicos de conectividad
print_header "VERIFICACIÓN DE CONECTIVIDAD - ZOOKEEPER"
total_tests=$((total_tests + 1))
if test_tcp "Zookeeper" "localhost" "2181"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - KAFKA"
total_tests=$((total_tests + 1))
if test_tcp "Kafka" "localhost" "9092"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Probando listar topics de Kafka...${NC}"
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Kafka: Comando de topics ejecutado correctamente"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Kafka: Error al listar topics"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - REDIS"
total_tests=$((total_tests + 1))
if test_tcp "Redis" "localhost" "6379"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Probando PING a Redis...${NC}"
docker exec redis redis-cli -a ${REDIS_PASSWORD:-redispass123} PING 2>/dev/null | grep -q "PONG"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Redis: PING exitoso"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} Redis: PING falló"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - CONSUL"
total_tests=$((total_tests + 1))
if test_http "Consul UI" "http://localhost:8500/ui/" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Consul API" "http://localhost:8500/v1/status/leader" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - POSTGRESQL (N8N)"
total_tests=$((total_tests + 1))
if test_tcp "PostgreSQL N8N" "localhost" "5432"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Probando conexión a PostgreSQL...${NC}"
docker exec postgres-n8n pg_isready -U ${POSTGRES_USER:-n8n} 2>/dev/null | grep -q "accepting connections"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} PostgreSQL N8N: Aceptando conexiones"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} PostgreSQL N8N: No acepta conexiones"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - N8N"
total_tests=$((total_tests + 1))
if test_http "n8n Web UI" "http://localhost:5678/healthz" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - JAEGER"
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

print_header "VERIFICACIÓN DE CONECTIVIDAD - VAULT"
total_tests=$((total_tests + 1))
if test_http "Vault API" "http://localhost:8200/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - PROMETHEUS"
total_tests=$((total_tests + 1))
if test_http "Prometheus" "http://localhost:9090/-/healthy" "200"; then
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

print_header "VERIFICACIÓN DE CONECTIVIDAD - GRAFANA"
total_tests=$((total_tests + 1))
if test_http "Grafana" "http://localhost:3000/api/health" "200"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - MINIO"
total_tests=$((total_tests + 1))
if test_http "MinIO Health" "http://localhost:9000/minio/health/live" "200"; then
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

print_header "VERIFICACIÓN DE CONECTIVIDAD - POSTGRESQL (KONG)"
total_tests=$((total_tests + 1))
if test_tcp "PostgreSQL Kong" "localhost" "5433"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

echo -e "\n${YELLOW}Probando conexión a PostgreSQL Kong...${NC}"
docker exec postgres-kong pg_isready -U ${KONG_PG_USER:-kong} 2>/dev/null | grep -q "accepting connections"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} PostgreSQL Kong: Aceptando conexiones"
    total_tests=$((total_tests + 1))
    passed_tests=$((passed_tests + 1))
else
    echo -e "${RED}✗${NC} PostgreSQL Kong: No acepta conexiones"
    total_tests=$((total_tests + 1))
    failed_tests=$((failed_tests + 1))
fi

print_header "VERIFICACIÓN DE CONECTIVIDAD - KONG"
total_tests=$((total_tests + 1))
if test_http "Kong Proxy" "http://localhost:8000/" "404"; then
    passed_tests=$((passed_tests + 1))
else
    failed_tests=$((failed_tests + 1))
fi

total_tests=$((total_tests + 1))
if test_http "Kong Admin API" "http://localhost:8001/" "200"; then
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

# Resumen final
print_header "RESUMEN DE VERIFICACIÓN"

echo -e "Total de pruebas ejecutadas: ${BLUE}${total_tests}${NC}"
echo -e "Pruebas exitosas: ${GREEN}${passed_tests}${NC}"
echo -e "Pruebas fallidas: ${RED}${failed_tests}${NC}"

success_rate=$((passed_tests * 100 / total_tests))
echo -e "\nTasa de éxito: ${BLUE}${success_rate}%${NC}"

if [ $failed_tests -eq 0 ]; then
    echo -e "\n${GREEN}✓ ¡Todos los servicios están funcionando correctamente!${NC}\n"
    exit 0
else
    echo -e "\n${RED}✗ Algunos servicios tienen problemas. Revisa los logs con:${NC}"
    echo -e "${YELLOW}docker-compose logs [nombre_servicio]${NC}\n"
    exit 1
fi