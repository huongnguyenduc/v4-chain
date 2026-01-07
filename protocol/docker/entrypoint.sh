#!/bin/bash
set -e

# Default values
CHAIN_ID=${CHAIN_ID:-"dydxprotocol-testnet"}
MONIKER=${MONIKER:-"dydxprotocol-node"}
KEYRING_BACKEND=${KEYRING_BACKEND:-"test"}
LOG_LEVEL=${LOG_LEVEL:-"info"}

# Validator configuration
VALIDATOR_KEY=${VALIDATOR_KEY:-"validator"}
VALIDATOR_MNEMONIC=${VALIDATOR_MNEMONIC:-""}

# Network configuration
SEEDS=${SEEDS:-""}
PERSISTENT_PEERS=${PERSISTENT_PEERS:-""}
EXTERNAL_ADDRESS=${EXTERNAL_ADDRESS:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Set home directory based on moniker
if [ -n "$MONIKER" ]; then
    DYDXPROTOCOL_HOME="/dydxprotocol/chain/.$MONIKER"
else
    DYDXPROTOCOL_HOME="/dydxprotocol/chain/.dydxprotocol"
fi

# Initialize node if not already initialized
init_node() {
    if [ ! -f "$DYDXPROTOCOL_HOME/config/genesis.json" ]; then
        log "Initializing dYdX Protocol node..."
        
        # Check if shared genesis file exists
        if [ -f "/opt/dydxprotocol/genesis/genesis.json" ]; then
            log "Using shared genesis file from /opt/dydxprotocol/genesis/genesis.json"
            # Initialize the node
            dydxprotocold init "$MONIKER" --chain-id "$CHAIN_ID" --home "$DYDXPROTOCOL_HOME"
            # Copy shared genesis file
            cp /opt/dydxprotocol/genesis/genesis.json "$DYDXPROTOCOL_HOME/config/genesis.json"
            log "Copied shared genesis file"
            
            # Copy node key if available (to persist node ID)
            NODE_NUM=$(echo "$MONIKER" | sed 's/.*node\([0-9]\)/\1/')
            if [ -n "$NODE_NUM" ] && [ -f "/opt/dydxprotocol/node-keys/node${NODE_NUM}-node_key.json" ]; then
                log "Copying node key for node $NODE_NUM..."
                cp "/opt/dydxprotocol/node-keys/node${NODE_NUM}-node_key.json" "$DYDXPROTOCOL_HOME/config/node_key.json"
                log "Copied node key (node ID will be persistent)"
            fi
            
            # Copy validator consensus key if available (to match GenTx)
            if [ -n "$NODE_NUM" ] && [ -f "/opt/dydxprotocol/validator-keys/node${NODE_NUM}-priv_validator_key.json" ]; then
                log "Copying validator consensus key for node $NODE_NUM..."
                cp "/opt/dydxprotocol/validator-keys/node${NODE_NUM}-priv_validator_key.json" "$DYDXPROTOCOL_HOME/config/priv_validator_key.json"
                log "Copied validator consensus key (validator will be recognized)"
            fi
            
            # Copy keyring from shared keys if available (for matching validator keys)
            if [ -n "$NODE_NUM" ] && [ -d "/opt/dydxprotocol/keys/node${NODE_NUM}-keyring" ]; then
                log "Copying keyring for node $NODE_NUM..."
                mkdir -p "$DYDXPROTOCOL_HOME/keyring-test"
                cp -r "/opt/dydxprotocol/keys/node${NODE_NUM}-keyring"/* "$DYDXPROTOCOL_HOME/keyring-test/" 2>/dev/null || true
                log "Copied keyring files"
            fi
            
            # Create validator key if it doesn't exist (needed even with shared genesis)
            if ! dydxprotocold keys show "$VALIDATOR_KEY" --keyring-backend "$KEYRING_BACKEND" --home "$DYDXPROTOCOL_HOME" >/dev/null 2>&1; then
                if [ -n "$VALIDATOR_MNEMONIC" ]; then
                    log "Recovering validator key from mnemonic..."
                    echo "$VALIDATOR_MNEMONIC" | dydxprotocold keys add "$VALIDATOR_KEY" --recover --keyring-backend "$KEYRING_BACKEND" --home "$DYDXPROTOCOL_HOME"
                else
                    log "Creating new validator key..."
                    dydxprotocold keys add "$VALIDATOR_KEY" --keyring-backend "$KEYRING_BACKEND" --home "$DYDXPROTOCOL_HOME"
                fi
            fi
        else
            # Initialize the node from scratch
            dydxprotocold init "$MONIKER" --chain-id "$CHAIN_ID" --home "$DYDXPROTOCOL_HOME"
            
            # Create validator key if it doesn't exist
            if ! dydxprotocold keys show "$VALIDATOR_KEY" --keyring-backend "$KEYRING_BACKEND" --home "$DYDXPROTOCOL_HOME" >/dev/null 2>&1; then
                if [ -n "$VALIDATOR_MNEMONIC" ]; then
                    log "Recovering validator key from mnemonic..."
                    echo "$VALIDATOR_MNEMONIC" | dydxprotocold keys add "$VALIDATOR_KEY" --recover --keyring-backend "$KEYRING_BACKEND" --home "$DYDXPROTOCOL_HOME"
                else
                    log "Creating new validator key..."
                    dydxprotocold keys add "$VALIDATOR_KEY" --keyring-backend "$KEYRING_BACKEND" --home "$DYDXPROTOCOL_HOME"
                fi
            fi
            
            # Get validator address
            VALIDATOR_ADDR=$(dydxprotocold keys show "$VALIDATOR_KEY" -a --keyring-backend "$KEYRING_BACKEND" --home "$DYDXPROTOCOL_HOME")
            log "Validator address: $VALIDATOR_ADDR"
            
            # Add genesis account
            dydxprotocold add-genesis-account "$VALIDATOR_ADDR" 1000000000000000000000adv4tnt --home "$DYDXPROTOCOL_HOME"
            
            # Create genesis transaction
            dydxprotocold gentx "$VALIDATOR_KEY" 100000000000000000000adv4tnt --chain-id "$CHAIN_ID" --keyring-backend "$KEYRING_BACKEND" --home "$DYDXPROTOCOL_HOME"
            
            # Collect genesis transactions
            dydxprotocold collect-gentxs --home "$DYDXPROTOCOL_HOME"
        fi
        
        log "Node initialization completed"
    else
        log "Node already initialized"
    fi
}

# Configure node settings
configure_node() {
    log "Configuring node settings..."
    
    # Configure config.toml
    CONFIG_FILE="$DYDXPROTOCOL_HOME/config/config.toml"
    
    # Set moniker
    sed -i "s/moniker = \".*\"/moniker = \"$MONIKER\"/" "$CONFIG_FILE"
    
    # Set log level
    sed -i "s/log_level = \".*\"/log_level = \"$LOG_LEVEL\"/" "$CONFIG_FILE"
    
    # Configure P2P
    if [ -n "$SEEDS" ]; then
        sed -i "s/seeds = \".*\"/seeds = \"$SEEDS\"/" "$CONFIG_FILE"
    fi
    
    if [ -n "$PERSISTENT_PEERS" ]; then
        # Update persistent_peers - handle both empty and non-empty cases
        if grep -q "persistent_peers = \"\"" "$CONFIG_FILE"; then
            sed -i "s|persistent_peers = \"\"|persistent_peers = \"$PERSISTENT_PEERS\"|" "$CONFIG_FILE"
        else
            sed -i "s|persistent_peers = \".*\"|persistent_peers = \"$PERSISTENT_PEERS\"|" "$CONFIG_FILE"
        fi
        log "Set persistent_peers to: $PERSISTENT_PEERS"
    fi
    
    if [ -n "$SEEDS" ]; then
        # Update seeds - handle both empty and non-empty cases
        if grep -q "seeds = \"\"" "$CONFIG_FILE"; then
            sed -i "s|seeds = \"\"|seeds = \"$SEEDS\"|" "$CONFIG_FILE"
        else
            sed -i "s|seeds = \".*\"|seeds = \"$SEEDS\"|" "$CONFIG_FILE"
        fi
        log "Set seeds to: $SEEDS"
    fi
    
    if [ -n "$EXTERNAL_ADDRESS" ]; then
        # Only set external_address if it doesn't contain an IP (to avoid external IP issues)
        if [[ ! "$EXTERNAL_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            sed -i "s/external_address = \".*\"/external_address = \"$EXTERNAL_ADDRESS\"/" "$CONFIG_FILE"
            log "Set external_address to: $EXTERNAL_ADDRESS"
        fi
    fi
    
    # Configure app.toml
    APP_CONFIG_FILE="$DYDXPROTOCOL_HOME/config/app.toml"
    
    # Set minimum gas prices
    sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0.025adv4tnt"/' "$APP_CONFIG_FILE"
    
    # Enable API server
    sed -i '/\[api\]/,/\[/{s/enable = false/enable = true/}' "$APP_CONFIG_FILE"
    sed -i 's/swagger = false/swagger = true/' "$APP_CONFIG_FILE"
    
    # Enable gRPC
    sed -i '/\[grpc\]/,/\[/{s/enable = false/enable = true/}' "$APP_CONFIG_FILE"
    
    log "Node configuration completed"
}

# Validate genesis file
validate_genesis() {
    log "Validating genesis file..."
    if dydxprotocold validate-genesis --home "$DYDXPROTOCOL_HOME"; then
        log "Genesis file is valid"
    else
        error "Genesis file validation failed"
        exit 1
    fi
}

# Start the node
start_node() {
    log "Starting dYdX Protocol node..."
    
    # Export configuration
    export HOME="$DYDXPROTOCOL_HOME"
    
    # Start the node with daemon flags for local development
    exec dydxprotocold start \
        --home "$DYDXPROTOCOL_HOME" \
        --log_level "$LOG_LEVEL" \
        --oracle.enabled=false \
        --price-daemon-enabled=false \
        --bridge-daemon-enabled=false \
        --liquidation-daemon-enabled=false \
        --max-daemon-unhealthy-seconds=4294967295
}

# Main execution
case "$1" in
    "init")
        init_node
        configure_node
        validate_genesis
        ;;
    "start")
        # Initialize if needed
        if [ ! -f "$DYDXPROTOCOL_HOME/config/genesis.json" ]; then
            init_node
            configure_node
        else
            # Re-configure node settings (in case env vars changed)
            configure_node
        fi
        
        # Start the node
        start_node
        ;;
    "validate-genesis")
        validate_genesis
        ;;
    "config")
        configure_node
        ;;
    *)
        # Pass through any other commands to dydxprotocold
        exec dydxprotocold "$@"
        ;;
esac

