#!/bin/bash
# Complete setup script for dYdX Protocol 4-node localnet
# This script automates the entire setup process

set -e

DIR="$( cd "$( dirname "$0" )" && pwd )"
PROTOCOL_DIR="$( cd "$DIR/.." && pwd )"

echo "=== dYdX Protocol Localnet Setup ==="
echo ""

# Step 1: Clean previous setup
echo "Step 1: Cleaning previous setup..."
cd "$PROTOCOL_DIR"
docker-compose -f docker-compose.localnet.yml down -v 2>/dev/null || true
rm -rf node* docker/genesis/genesis.json docker/keys/* docker/node-keys/* docker/validator-keys/* 2>/dev/null || true
mkdir -p docker/genesis docker/keys docker/node-keys docker/validator-keys
echo "✓ Cleaned previous setup"
echo ""

# Step 2: Initialize nodes
echo "Step 2: Initializing nodes and creating genesis..."
"$DIR/init-nodes.sh"
echo "✓ Nodes initialized"
echo ""

# Step 3: Copy genesis file
echo "Step 3: Copying genesis file..."
cp node0/config/genesis.json docker/genesis/genesis.json
echo "✓ Genesis file copied"
echo ""

# Step 4: Copy keyrings
echo "Step 4: Copying keyrings..."
for i in {0..3}; do
    cp -r "node$i/keyring-test" "docker/keys/node$i-keyring" 2>/dev/null || true
done
echo "✓ Keyrings copied"
echo ""

# Step 5: Copy node keys
echo "Step 5: Copying node keys..."
for i in {0..3}; do
    cp "node$i/config/node_key.json" "docker/node-keys/node$i-node_key.json" 2>/dev/null || true
done
echo "✓ Node keys copied"
echo ""

# Step 6: Copy validator keys
echo "Step 6: Copying validator keys..."
for i in {0..3}; do
    cp "node$i/config/priv_validator_key.json" "docker/validator-keys/node$i-priv_validator_key.json" 2>/dev/null || true
done
echo "✓ Validator keys copied"
echo ""

# Step 7: Fix validator key mapping (GenTx order: node3, node1, node2, node0)
echo "Step 7: Mapping validator keys to match GenTx order..."
cp docker/validator-keys/node3-priv_validator_key.json docker/validator-keys/node0-priv_validator_key.json.tmp
cp docker/validator-keys/node0-priv_validator_key.json docker/validator-keys/node3-priv_validator_key.json.tmp
mv docker/validator-keys/node0-priv_validator_key.json.tmp docker/validator-keys/node3-priv_validator_key.json
mv docker/validator-keys/node3-priv_validator_key.json.tmp docker/validator-keys/node0-priv_validator_key.json
echo "✓ Validator keys mapped correctly"
echo ""

# Step 8: Update docker-compose with node IDs
echo "Step 8: Updating docker-compose with node IDs..."
cd "$PROTOCOL_DIR"
"$DIR/update-docker-node-ids.sh"
echo "✓ Docker-compose updated"
echo ""

# Step 9: Build Docker images
echo "Step 9: Building Docker images..."
docker-compose -f docker-compose.localnet.yml build > /dev/null 2>&1
echo "✓ Docker images built"
echo ""

# Step 10: Start containers
echo "Step 10: Starting containers..."
docker-compose -f docker-compose.localnet.yml up -d
echo "✓ Containers started"
echo ""

echo "=== Setup Complete! ==="
echo ""
echo "Waiting for nodes to initialize (this may take a minute)..."
sleep 30

echo ""
echo "Network Status:"
echo "  - Containers: $(docker-compose -f docker-compose.localnet.yml ps -q | wc -l | tr -d ' ') running"
echo ""
echo "Monitor progress with:"
echo "  docker-compose -f docker-compose.localnet.yml logs -f"
echo ""
echo "Check block height:"
echo "  curl -s http://localhost:26657/status | python3 -c \"import sys, json; print(json.load(sys.stdin)['result']['sync_info']['latest_block_height'])\""
echo ""
echo "The network should be fully operational within 1-2 minutes!"

