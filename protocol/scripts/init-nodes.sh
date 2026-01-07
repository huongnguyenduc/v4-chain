#!/bin/bash
DIR="$( cd "$( dirname "$0" )" && pwd )"
# Stop on any error
set -e

# Configuration
BINARY=${DIR}/../build/dydxprotocold
CHAIN_ID="dydxprotocol-testnet"
MONIKER_PREFIX="dydxprotocol-node"
CHAIN_DIR="$HOME/.dydxprotocol"
CONFIG_DIR="config"
GENTX_DIR="gentx"

# Clean up old directories
rm -rf node*
# Set base demon
DENOM=adv4tnt
# Create directories for four nodes and collect addresses
declare -a ADDRESSES
for i in {0..3}; do
    NODE_DIR="node$i"
    MONIKER="$MONIKER_PREFIX-$i"
    
    echo "Initializing node $i in $NODE_DIR..."
    
    # Initialize the node
    $BINARY init $MONIKER --chain-id $CHAIN_ID --home $NODE_DIR
    
    # Create a new key for the node
    echo "Creating key for node $i..."
    $BINARY keys add "validator$i" --keyring-backend=test --home $NODE_DIR > "$NODE_DIR/validator_key.txt" 2>&1
    
    # Get the address and mnemonic
    ADDRESS=$($BINARY keys show "validator$i" -a --keyring-backend=test --home $NODE_DIR)
    ADDRESSES[$i]=$ADDRESS
    echo "Node $i address: $ADDRESS"
    
    # Skip mnemonic export (not needed for docker setup, keys are copied directly)
    # The mnemonic export can hang or fail, and we don't need it since we copy keyrings
    # MNEMONIC=$($BINARY keys export "validator$i" --keyring-backend=test --home $NODE_DIR --unarmored-hex --unsafe 2>/dev/null || \
    #            $BINARY keys export "validator$i" --keyring-backend=test --home $NODE_DIR 2>/dev/null | grep -A 1 "mnemonic" | tail -1 || echo "")
    # if [ -n "$MNEMONIC" ]; then
    #     echo "$MNEMONIC" > "$NODE_DIR/validator_mnemonic.txt"
    #     echo "Saved mnemonic for validator$i"
    # fi
    
    # Add genesis account to this node's genesis (needed for gentx creation)
    echo "Adding genesis account for node $i..."
    $BINARY add-genesis-account $ADDRESS 1000000000000000000000$DENOM --keyring-backend=test --home $NODE_DIR
done

# Add all genesis accounts to node0 (where we'll collect gentxs)
echo "Adding all genesis accounts to node0..."
for i in {0..3}; do
    # Check if account already exists in node0 (it will for i=0)
    if [ $i -ne 0 ]; then
        echo "Adding genesis account for node $i to node0..."
        $BINARY add-genesis-account ${ADDRESSES[$i]} 1000000000000000000000$DENOM --keyring-backend=test --home node0
    fi
done

# Update staking bond_denom in node0's genesis before creating gentx
echo "Updating staking bond_denom to $DENOM..."
python3 <<EOF
import json
import sys

genesis_file = "node0/config/genesis.json"
with open(genesis_file, 'r') as f:
    genesis = json.load(f)

# Update bond_denom in staking params
if 'app_state' in genesis and 'staking' in genesis['app_state']:
    if 'params' in genesis['app_state']['staking']:
        genesis['app_state']['staking']['params']['bond_denom'] = '$DENOM'
        print(f"Updated bond_denom to $DENOM")

with open(genesis_file, 'w') as f:
    json.dump(genesis, f, indent=2)
EOF

# Create genesis transactions for each node
for i in {0..3}; do
    NODE_DIR="node$i"
    echo "Creating gentx for node $i..."
    
    # Update bond_denom in this node's genesis before creating gentx
    if [ $i -ne 0 ]; then
        python3 <<PYEOF
import json
genesis_file = "$NODE_DIR/config/genesis.json"
with open(genesis_file, 'r') as f:
    genesis = json.load(f)
if 'app_state' in genesis and 'staking' in genesis['app_state']:
    if 'params' in genesis['app_state']['staking']:
        genesis['app_state']['staking']['params']['bond_denom'] = '$DENOM'
with open(genesis_file, 'w') as f:
    json.dump(genesis, f, indent=2)
PYEOF
    fi
    
    $BINARY gentx "validator$i" 100000000000000000000$DENOM --chain-id $CHAIN_ID --keyring-backend=test --home $NODE_DIR
done

# Collect all gentxs into node0
echo "Collecting gentxs..."
for i in {1..3}; do
    cp "node$i/$CONFIG_DIR/$GENTX_DIR/"*.json "node0/$CONFIG_DIR/$GENTX_DIR/"
done

# Create the final genesis file
echo "Creating final genesis file..."
$BINARY collect-gentxs --home "node0"

# Add market map entries for BTC/USD and ETH/USD to match prices module
echo "Adding market map entries for BTC/USD and ETH/USD..."
python3 <<PYEOF
import json

genesis_file = "node0/config/genesis.json"
with open(genesis_file, 'r') as f:
    genesis = json.load(f)

# Ensure marketmap structure exists
if 'app_state' not in genesis:
    genesis['app_state'] = {}
if 'marketmap' not in genesis['app_state']:
    genesis['app_state']['marketmap'] = {}
if 'market_map' not in genesis['app_state']['marketmap']:
    genesis['app_state']['marketmap']['market_map'] = {}
if 'markets' not in genesis['app_state']['marketmap']['market_map']:
    genesis['app_state']['marketmap']['market_map']['markets'] = {}

markets = genesis['app_state']['marketmap']['market_map']['markets']

# Add BTC/USD with decimals=5 (to match prices exponent=-5)
if 'BTC/USD' not in markets:
    markets['BTC/USD'] = {
        "ticker": {
            "currency_pair": {
                "Base": "BTC",
                "Quote": "USD"
            },
            "decimals": 5,
            "min_provider_count": 1,
            "enabled": True
        },
        "provider_configs": [
            {
                "name": "volatile-exchange-provider",
                "off_chain_ticker": "BTC-USD"
            }
        ]
    }
    print("Added BTC/USD to market map (decimals=5)")

# Add ETH/USD with decimals=6 (to match prices exponent=-6)
if 'ETH/USD' not in markets:
    markets['ETH/USD'] = {
        "ticker": {
            "currency_pair": {
                "Base": "ETH",
                "Quote": "USD"
            },
            "decimals": 6,
            "min_provider_count": 1,
            "enabled": True
        },
        "provider_configs": [
            {
                "name": "volatile-exchange-provider",
                "off_chain_ticker": "ETH-USD"
            }
        ]
    }
    print("Added ETH/USD to market map (decimals=6)")

with open(genesis_file, 'w') as f:
    json.dump(genesis, f, indent=2)
PYEOF

# Distribute the genesis file to all nodes
echo "Distributing genesis file..."
for i in {1..3}; do
    cp "node0/$CONFIG_DIR/genesis.json" "node$i/$CONFIG_DIR/genesis.json"
done

# Get node0's ID
NODE0_ID=$($BINARY tendermint show-node-id --home node0)
echo "Node 0 ID: $NODE0_ID"

# Update persistent_peers for other nodes
echo "Updating persistent peers..."
for i in {1..3}; do
    sed -i.bak "s/persistent_peers = \"\"/persistent_peers = \"$NODE0_ID@dydxprotocol-node0:26656\"/" "node$i/$CONFIG_DIR/config.toml"
done

echo "Local network configuration complete!"

