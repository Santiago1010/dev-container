#!/bin/bash

# Script to initialize and configure Vault
# This script should be run after starting the services

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "  Initializing HashiCorp Vault"
echo "=========================================="
echo ""

# Wait for Vault to be available
echo "Waiting for Vault to become available..."
for i in {1..30}; do
    if curl -sf http://localhost:8200/v1/sys/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Vault is available"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}✗${NC} Timeout waiting for Vault"
        exit 1
    fi
    echo "Attempt $i/30..."
    sleep 2
done
echo ""

# Check if Vault is already initialized
INIT_STATUS=$(docker exec vault vault status -format=json 2>/dev/null | jq -r '.initialized' 2>/dev/null)

if [ "$INIT_STATUS" = "true" ]; then
    echo -e "${YELLOW}⚠${NC} Vault is already initialized"
    echo "If you need to reinitialize it, delete the ./data/vault/file directory"
    exit 0
fi

# Initialize Vault
echo "Initializing Vault with 5 key shares and threshold of 3..."
INIT_OUTPUT=$(docker exec vault vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json)

# Save keys and root token
echo "$INIT_OUTPUT" > ./data/vault/vault-keys.json
chmod 600 ./data/vault/vault-keys.json

echo -e "${GREEN}✓${NC} Vault initialized successfully"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} Unseal keys and root token have been saved to:"
echo "  ./data/vault/vault-keys.json"
echo ""
echo -e "${RED}⚠ WARNING:${NC} Store this file in a secure location and do not share it"
echo ""

# Extract first 3 unseal keys
UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

# Unseal Vault
echo "Unsealing Vault (requires 3 out of 5 keys)..."
docker exec vault vault operator unseal "$UNSEAL_KEY_1" > /dev/null
echo -e "${GREEN}✓${NC} Key 1/3 applied"

docker exec vault vault operator unseal "$UNSEAL_KEY_2" > /dev/null
echo -e "${GREEN}✓${NC} Key 2/3 applied"

docker exec vault vault operator unseal "$UNSEAL_KEY_3" > /dev/null
echo -e "${GREEN}✓${NC} Key 3/3 applied"
echo ""
echo -e "${GREEN}✓${NC} Vault unsealed successfully"
echo ""

# Configure root token for command usage
export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN="$ROOT_TOKEN"

# Enable KV v2 secrets engine
echo "Enabling KV version 2 secrets engine..."
docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
    vault secrets enable -path=secret kv-v2 2>/dev/null || \
    echo -e "${YELLOW}⚠${NC} KV engine already enabled"

echo -e "${GREEN}✓${NC} Secrets engine configured"
echo ""

# Create example policy
echo "Creating example policy..."
docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault vault policy write app-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/myapp/*" {
  capabilities = ["list", "read", "delete"]
}
EOF

echo -e "${GREEN}✓${NC} Policy 'app-policy' created"
echo ""

# Create example secret
echo "Creating example secret..."
docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
    vault kv put secret/myapp/config \
    username=admin \
    password=supersecret \
    api_key=abc123xyz

echo -e "${GREEN}✓${NC} Example secret created at secret/myapp/config"
echo ""

# Summary
echo "=========================================="
echo "  Setup completed"
echo "=========================================="
echo ""
echo "Vault UI: http://localhost:8200"
echo "Root Token: $ROOT_TOKEN"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo ""
echo "# Export environment variables to use Vault CLI:"
echo "export VAULT_ADDR='http://localhost:8200'"
echo "export VAULT_TOKEN='$ROOT_TOKEN'"
echo ""
echo "# View example secret:"
echo "docker exec -e VAULT_TOKEN='$ROOT_TOKEN' vault vault kv get secret/myapp/config"
echo ""
echo "# Create a new secret:"
echo "docker exec -e VAULT_TOKEN='$ROOT_TOKEN' vault vault kv put secret/myapp/database \\"
echo "  host=postgres \\"
echo "  username=dbuser \\"
echo "  password=dbpass"
echo ""
echo -e "${RED}⚠ REMEMBER:${NC} Save the vault-keys.json file in a secure location"
echo ""