#!/bin/bash
# Helper script to update docker-compose with node IDs from generated node directories

set -e

DIR="$( cd "$( dirname "$0" )" && pwd )"
PROTOCOL_DIR="$( cd "$DIR/.." && pwd )"
COMPOSE_FILE="$PROTOCOL_DIR/docker-compose.localnet.yml"
BINARY="$PROTOCOL_DIR/build/dydxprotocold"

# Try to get node IDs from local node directories first, then from containers
echo "Getting node IDs from generated node directories..."

NODE0_ID=""
NODE1_ID=""
NODE2_ID=""
NODE3_ID=""

# Try from local directories
if [ -d "$PROTOCOL_DIR/node0" ]; then
    NODE0_ID=$($BINARY tendermint show-node-id --home "$PROTOCOL_DIR/node0" 2>/dev/null || echo "")
    NODE1_ID=$($BINARY tendermint show-node-id --home "$PROTOCOL_DIR/node1" 2>/dev/null || echo "")
    NODE2_ID=$($BINARY tendermint show-node-id --home "$PROTOCOL_DIR/node2" 2>/dev/null || echo "")
    NODE3_ID=$($BINARY tendermint show-node-id --home "$PROTOCOL_DIR/node3" 2>/dev/null || echo "")
fi

# Fallback to containers if local directories don't have IDs
if [ -z "$NODE0_ID" ] || [ -z "$NODE1_ID" ] || [ -z "$NODE2_ID" ] || [ -z "$NODE3_ID" ]; then
    echo "Trying to get node IDs from running containers..."
    NODE0_ID=$(docker exec dydxprotocol-node0 dydxprotocold tendermint show-node-id --home /dydxprotocol/chain/.dydxprotocol-node0 2>/dev/null || echo "")
    NODE1_ID=$(docker exec dydxprotocol-node1 dydxprotocold tendermint show-node-id --home /dydxprotocol/chain/.dydxprotocol-node1 2>/dev/null || echo "")
    NODE2_ID=$(docker exec dydxprotocol-node2 dydxprotocold tendermint show-node-id --home /dydxprotocol/chain/.dydxprotocol-node2 2>/dev/null || echo "")
    NODE3_ID=$(docker exec dydxprotocol-node3 dydxprotocold tendermint show-node-id --home /dydxprotocol/chain/.dydxprotocol-node3 2>/dev/null || echo "")
fi

if [ -z "$NODE0_ID" ] || [ -z "$NODE1_ID" ] || [ -z "$NODE2_ID" ] || [ -z "$NODE3_ID" ]; then
    echo "Error: Could not get all node IDs. Make sure nodes are initialized or containers are running."
    exit 1
fi

echo "Node IDs:"
echo "  Node0: $NODE0_ID"
echo "  Node1: $NODE1_ID"
echo "  Node2: $NODE2_ID"
echo "  Node3: $NODE3_ID"

# Update node0 (exclude itself)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|PERSISTENT_PEERS=.*@dydxprotocol-node1:26656.*@dydxprotocol-node2:26656.*@dydxprotocol-node3:26656|PERSISTENT_PEERS=${NODE1_ID}@dydxprotocol-node1:26656,${NODE2_ID}@dydxprotocol-node2:26656,${NODE3_ID}@dydxprotocol-node3:26656|g" "$COMPOSE_FILE"
    # Update node1 (exclude itself)
    sed -i '' "s|PERSISTENT_PEERS=.*@dydxprotocol-node0:26656.*@dydxprotocol-node2:26656.*@dydxprotocol-node3:26656|PERSISTENT_PEERS=${NODE0_ID}@dydxprotocol-node0:26656,${NODE2_ID}@dydxprotocol-node2:26656,${NODE3_ID}@dydxprotocol-node3:26656|g" "$COMPOSE_FILE"
    # Update node2 (exclude itself)
    sed -i '' "s|PERSISTENT_PEERS=.*@dydxprotocol-node0:26656.*@dydxprotocol-node1:26656.*@dydxprotocol-node3:26656|PERSISTENT_PEERS=${NODE0_ID}@dydxprotocol-node0:26656,${NODE1_ID}@dydxprotocol-node1:26656,${NODE3_ID}@dydxprotocol-node3:26656|g" "$COMPOSE_FILE"
    # Update node3 (exclude itself)
    sed -i '' "s|PERSISTENT_PEERS=.*@dydxprotocol-node0:26656.*@dydxprotocol-node1:26656.*@dydxprotocol-node2:26656|PERSISTENT_PEERS=${NODE0_ID}@dydxprotocol-node0:26656,${NODE1_ID}@dydxprotocol-node1:26656,${NODE2_ID}@dydxprotocol-node2:26656|g" "$COMPOSE_FILE"
else
    sed -i "s|PERSISTENT_PEERS=.*@dydxprotocol-node1:26656.*@dydxprotocol-node2:26656.*@dydxprotocol-node3:26656|PERSISTENT_PEERS=${NODE1_ID}@dydxprotocol-node1:26656,${NODE2_ID}@dydxprotocol-node2:26656,${NODE3_ID}@dydxprotocol-node3:26656|g" "$COMPOSE_FILE"
    sed -i "s|PERSISTENT_PEERS=.*@dydxprotocol-node0:26656.*@dydxprotocol-node2:26656.*@dydxprotocol-node3:26656|PERSISTENT_PEERS=${NODE0_ID}@dydxprotocol-node0:26656,${NODE2_ID}@dydxprotocol-node2:26656,${NODE3_ID}@dydxprotocol-node3:26656|g" "$COMPOSE_FILE"
    sed -i "s|PERSISTENT_PEERS=.*@dydxprotocol-node0:26656.*@dydxprotocol-node1:26656.*@dydxprotocol-node3:26656|PERSISTENT_PEERS=${NODE0_ID}@dydxprotocol-node0:26656,${NODE1_ID}@dydxprotocol-node1:26656,${NODE3_ID}@dydxprotocol-node3:26656|g" "$COMPOSE_FILE"
    sed -i "s|PERSISTENT_PEERS=.*@dydxprotocol-node0:26656.*@dydxprotocol-node1:26656.*@dydxprotocol-node2:26656|PERSISTENT_PEERS=${NODE0_ID}@dydxprotocol-node0:26656,${NODE1_ID}@dydxprotocol-node1:26656,${NODE2_ID}@dydxprotocol-node2:26656|g" "$COMPOSE_FILE"
fi

echo ""
echo "Updated $COMPOSE_FILE with actual node IDs"
echo "Restart containers to apply changes: docker-compose -f $COMPOSE_FILE restart"
