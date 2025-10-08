#!/bin/bash

# Vault Management Script
# Provides useful commands for managing Vault

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load root token if exists
if [ -f "./data/vault/vault-keys.json" ]; then
    ROOT_TOKEN=$(jq -r '.root_token' ./data/vault/vault-keys.json 2>/dev/null)
fi

show_help() {
    echo -e "${BLUE}===========================================\n"
    echo "  Vault Manager - Management Tool"
    echo -e "\n===========================================${NC}\n"
    echo "Usage: $0 [command]"
    echo ""
    echo "Available commands:"
    echo ""
    echo "  status        - Check Vault status"
    echo "  unseal        - Unseal Vault"
    echo "  seal          - Seal Vault"
    echo "  token-info    - View current token information"
    echo "  list-secrets  - List all secrets"
    echo "  get <path>    - Get a secret"
    echo "  put <path>    - Create/update secret (interactive)"
    echo "  delete <path> - Delete a secret"
    echo "  backup        - Create Vault backup"
    echo "  logs          - View Vault logs"
    echo "  ui            - Open Vault UI in browser"
    echo "  help          - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 get secret/myapp/config"
    echo "  $0 put secret/myapp/database"
    echo "  $0 backup"
    echo ""
}

check_vault_running() {
    if ! docker ps | grep -q vault; then
        echo -e "${RED}✗${NC} Vault is not running"
        echo "Run: docker-compose up -d vault"
        exit 1
    fi
}

check_token() {
    if [ -z "$ROOT_TOKEN" ]; then
        echo -e "${YELLOW}⚠${NC} Root token not found"
        echo "Please initialize Vault first: ./scripts/init_vault.sh"
        exit 1
    fi
}

vault_status() {
    check_vault_running
    echo -e "${BLUE}Vault Status:${NC}\n"
    docker exec vault vault status || true
    echo ""
    if docker exec vault vault status 2>&1 | grep -q "Sealed.*false"; then
        echo -e "${GREEN}✓${NC} Vault is unsealed and ready to use"
    elif docker exec vault vault status 2>&1 | grep -q "Sealed.*true"; then
        echo -e "${YELLOW}⚠${NC} Vault is sealed. Run: $0 unseal"
    fi
}

vault_unseal() {
    check_vault_running
    
    if [ ! -f "./data/vault/vault-keys.json" ]; then
        echo -e "${RED}✗${NC} vault-keys.json not found"
        echo "Initialize Vault first: ./scripts/init_vault.sh"
        exit 1
    fi
    
    echo -e "${BLUE}Unsealing Vault...${NC}\n"
    
    UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' ./data/vault/vault-keys.json)
    UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' ./data/vault/vault-keys.json)
    UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' ./data/vault/vault-keys.json)
    
    docker exec vault vault operator unseal "$UNSEAL_KEY_1" > /dev/null
    echo -e "${GREEN}✓${NC} Key 1/3 applied"
    
    docker exec vault vault operator unseal "$UNSEAL_KEY_2" > /dev/null
    echo -e "${GREEN}✓${NC} Key 2/3 applied"
    
    docker exec vault vault operator unseal "$UNSEAL_KEY_3" > /dev/null
    echo -e "${GREEN}✓${NC} Key 3/3 applied"
    
    echo ""
    echo -e "${GREEN}✓${NC} Vault unsealed successfully"
}

vault_seal() {
    check_vault_running
    check_token
    
    echo -e "${YELLOW}⚠${NC} This will seal Vault. You will need to unseal it again."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault vault operator seal
        echo -e "${GREEN}✓${NC} Vault sealed"
    else
        echo "Cancelled"
    fi
}

token_info() {
    check_vault_running
    check_token
    
    echo -e "${BLUE}Token Information:${NC}\n"
    docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
        vault token lookup -format=json | jq
}

list_secrets() {
    check_vault_running
    check_token
    
    echo -e "${BLUE}Listing secrets:${NC}\n"
    
    # List paths in secrets engine
    echo -e "${GREEN}Available paths:${NC}"
    docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
        vault kv list -format=json secret/ 2>/dev/null | jq -r '.[]' || \
        echo "No secrets yet"
}

get_secret() {
    check_vault_running
    check_token
    
    if [ -z "$1" ]; then
        echo -e "${RED}✗${NC} You must specify the secret path"
        echo "Usage: $0 get secret/myapp/config"
        exit 1
    fi
    
    echo -e "${BLUE}Getting secret: $1${NC}\n"
    docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
        vault kv get -format=json "$1" | jq
}

put_secret() {
    check_vault_running
    check_token
    
    if [ -z "$1" ]; then
        echo -e "${RED}✗${NC} You must specify the secret path"
        echo "Usage: $0 put secret/myapp/config"
        exit 1
    fi
    
    echo -e "${BLUE}Creating/updating secret: $1${NC}\n"
    echo "Enter key=value pairs (empty to finish):"
    
    PAIRS=""
    while true; do
        read -p "Key=Value: " pair
        if [ -z "$pair" ]; then
            break
        fi
        PAIRS="$PAIRS $pair"
    done
    
    if [ -z "$PAIRS" ]; then
        echo "No data entered"
        exit 1
    fi
    
    docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
        vault kv put "$1" $PAIRS
    
    echo -e "\n${GREEN}✓${NC} Secret saved successfully"
}

delete_secret() {
    check_vault_running
    check_token
    
    if [ -z "$1" ]; then
        echo -e "${RED}✗${NC} You must specify the secret path"
        echo "Usage: $0 delete secret/myapp/config"
        exit 1
    fi
    
    echo -e "${YELLOW}⚠${NC} This will delete the secret: $1"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault \
            vault kv delete "$1"
        echo -e "${GREEN}✓${NC} Secret deleted"
    else
        echo "Cancelled"
    fi
}

vault_backup() {
    check_vault_running
    check_token
    
    BACKUP_DIR="./backups"
    mkdir -p "$BACKUP_DIR"
    
    BACKUP_FILE="vault-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo -e "${BLUE}Creating backup...${NC}\n"
    
    # Backup data directory
    tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
        ./data/vault/file \
        ./data/vault/vault-keys.json 2>/dev/null || true
    
    echo -e "${GREEN}✓${NC} Backup created: $BACKUP_DIR/$BACKUP_FILE"
    echo ""
    echo "Backup includes:"
    echo "  - Vault data (./data/vault/file)"
    echo "  - Unseal keys (vault-keys.json)"
    echo ""
    echo -e "${YELLOW}⚠${NC} Store this file in a secure location"
}

vault_logs() {
    check_vault_running
    
    echo -e "${BLUE}Vault logs (Ctrl+C to exit):${NC}\n"
    docker-compose logs -f vault
}

open_ui() {
    check_vault_running
    
    echo -e "${BLUE}Opening Vault UI...${NC}\n"
    echo "URL: http://localhost:8200"
    
    if [ -n "$ROOT_TOKEN" ]; then
        echo "Token: $ROOT_TOKEN"
    fi
    
    # Try to open in browser
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:8200" 2>/dev/null
    elif command -v open &> /dev/null; then
        open "http://localhost:8200"
    else
        echo ""
        echo "Please open http://localhost:8200 in your browser"
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
        echo -e "${RED}✗${NC} Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac