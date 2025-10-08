#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

# Function to print results
print_result() {
    local service=$1
    local status=$2
    local message=$3
    
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $service: $message"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $service: $message"
        ((FAILED++))
    fi
}

echo "=========================================="
echo "  Starting service tests..."
echo "=========================================="
echo ""

# Test ZooKeeper
echo "Testing ZooKeeper..."
# Try first with nc, if not available use curl to admin port
if command -v nc &> /dev/null; then
    if echo stat | nc -w 2 localhost 2181 > /dev/null 2>&1; then
        print_result "ZooKeeper" 0 "Responding correctly on port 2181"
    else
        print_result "ZooKeeper" 1 "Not responding on port 2181"
    fi
else
    # Fallback: verify using docker and admin server
    if docker exec zookeeper bash -c "echo stat | nc localhost 2181" > /dev/null 2>&1; then
        print_result "ZooKeeper" 0 "Responding correctly on port 2181"
    else
        print_result "ZooKeeper" 1 "Not responding on port 2181"
    fi
fi
echo ""

# Test Kafka
echo "Testing Kafka..."
if docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    print_result "Kafka" 0 "Broker responding correctly"
else
    print_result "Kafka" 1 "Broker not responding"
fi

# Test creating a test topic
if docker exec kafka kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists --topic test-topic --partitions 1 --replication-factor 1 > /dev/null 2>&1; then
    print_result "Kafka" 0 "Can create topics"
else
    print_result "Kafka" 1 "Cannot create topics"
fi
echo ""

# Test Redis
echo "Testing Redis..."
REDIS_PASS="${REDIS_PASSWORD:-redispass123}"
if docker exec redis redis-cli -a "$REDIS_PASS" ping 2>/dev/null | grep -q PONG; then
    print_result "Redis" 0 "Responding PONG"
else
    print_result "Redis" 1 "Not responding to PING command"
fi

# Test write/read
if docker exec redis redis-cli -a "$REDIS_PASS" SET test_key "test_value" > /dev/null 2>&1 && \
   docker exec redis redis-cli -a "$REDIS_PASS" GET test_key > /dev/null 2>&1; then
    print_result "Redis" 0 "Can write and read data"
    docker exec redis redis-cli -a "$REDIS_PASS" DEL test_key > /dev/null 2>&1
else
    print_result "Redis" 1 "Cannot write/read data"
fi
echo ""

# Test Consul
echo "Testing Consul..."
if curl -sf http://localhost:8500/v1/status/leader > /dev/null 2>&1; then
    print_result "Consul" 0 "API responding on port 8500"
else
    print_result "Consul" 1 "API not responding"
fi

if docker exec consul consul members > /dev/null 2>&1; then
    print_result "Consul" 0 "Active cluster"
else
    print_result "Consul" 1 "Cluster not responding"
fi
echo ""

# Test PostgreSQL (n8n)
echo "Testing PostgreSQL (n8n)..."
POSTGRES_USER="${POSTGRES_USER:-n8n}"
if docker exec postgres-n8n pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
    print_result "PostgreSQL-n8n" 0 "Database ready"
else
    print_result "PostgreSQL-n8n" 1 "Database not responding"
fi
echo ""

# Test n8n
echo "Testing n8n..."
if curl -sf http://localhost:5678/healthz > /dev/null 2>&1; then
    print_result "n8n" 0 "Health check OK"
else
    print_result "n8n" 1 "Health check failed"
fi

if curl -sf http://localhost:5678 > /dev/null 2>&1; then
    print_result "n8n" 0 "Web interface accessible"
else
    print_result "n8n" 1 "Web interface not accessible"
fi
echo ""

# Test Jaeger
echo "Testing Jaeger..."
if curl -sf http://localhost:14269/ > /dev/null 2>&1; then
    print_result "Jaeger" 0 "Health endpoint responding"
else
    print_result "Jaeger" 1 "Health endpoint not responding"
fi

if curl -sf http://localhost:16686 > /dev/null 2>&1; then
    print_result "Jaeger" 0 "UI accessible on port 16686"
else
    print_result "Jaeger" 1 "UI not accessible"
fi
echo ""

# Test Prometheus
echo "Testing Prometheus..."
if curl -sf http://localhost:9090/-/healthy > /dev/null 2>&1; then
    print_result "Prometheus" 0 "Health check OK"
else
    print_result "Prometheus" 1 "Health check failed"
fi

if curl -sf http://localhost:9090/api/v1/query?query=up > /dev/null 2>&1; then
    print_result "Prometheus" 0 "API responding"
else
    print_result "Prometheus" 1 "API not responding"
fi
echo ""

# Test Grafana
echo "Testing Grafana..."
if curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
    print_result "Grafana" 0 "Health check OK"
else
    print_result "Grafana" 1 "Health check failed"
fi

if curl -sf http://localhost:3000 > /dev/null 2>&1; then
    print_result "Grafana" 0 "UI accessible"
else
    print_result "Grafana" 1 "UI not accessible"
fi
echo ""

# Test MinIO
echo "Testing MinIO..."
if curl -sf http://localhost:9000/minio/health/live > /dev/null 2>&1; then
    print_result "MinIO" 0 "Health check OK"
else
    print_result "MinIO" 1 "Health check failed"
fi

if curl -sf http://localhost:9001 > /dev/null 2>&1; then
    print_result "MinIO" 0 "Console accessible on port 9001"
else
    print_result "MinIO" 1 "Console not accessible"
fi
echo ""

# Test PostgreSQL (Kong)
echo "Testing PostgreSQL (Kong)..."
KONG_PG_USER="${KONG_PG_USER:-kong}"
if docker exec postgres-kong pg_isready -U "$KONG_PG_USER" > /dev/null 2>&1; then
    print_result "PostgreSQL-Kong" 0 "Database ready"
else
    print_result "PostgreSQL-Kong" 1 "Database not responding"
fi
echo ""

# Test Kong
echo "Testing Kong..."
if docker exec kong kong health > /dev/null 2>&1; then
    print_result "Kong" 0 "Health check OK"
else
    print_result "Kong" 1 "Health check failed"
fi

if curl -sf http://localhost:8001/status > /dev/null 2>&1; then
    print_result "Kong" 0 "Admin API accessible"
else
    print_result "Kong" 1 "Admin API not accessible"
fi

# Kong proxy returns "no route" when no services are configured, which is expected
PROXY_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 2>/dev/null)
if [ "$PROXY_RESPONSE" = "404" ]; then
    print_result "Kong" 0 "Proxy accessible (404 with no routes is normal)"
elif [ "$PROXY_RESPONSE" = "200" ] || [ "$PROXY_RESPONSE" = "301" ] || [ "$PROXY_RESPONSE" = "302" ]; then
    print_result "Kong" 0 "Proxy accessible (HTTP code: $PROXY_RESPONSE)"
elif [ -z "$PROXY_RESPONSE" ] || [ "$PROXY_RESPONSE" = "000" ]; then
    print_result "Kong" 1 "Proxy not responding"
else
    print_result "Kong" 0 "Proxy accessible (HTTP code: $PROXY_RESPONSE)"
fi
echo ""

# Final summary
echo "=========================================="
echo "  Test Summary"
echo "=========================================="
echo -e "${GREEN}Tests passed: $PASSED${NC}"
echo -e "${RED}Tests failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All services are working correctly!${NC}"
    exit 0
else
    echo -e "${YELLOW}Some services have issues. Check logs with:${NC}"
    echo "docker-compose logs <service-name>"
    exit 1
fi