# dYdX Protocol Localnet Setup

## Quick Start

The setup is **fully automated**. Simply run:

```bash
./scripts/setup-localnet.sh
```

This single command will:
1. Clean any previous setup
2. Initialize 4 nodes with shared genesis
3. Copy all necessary keys and configs
4. Update docker-compose with correct node IDs
5. Build and start all containers
6. Set up the complete 4-node network

## What the Script Does

The `setup-localnet.sh` script automates the entire process:

1. **Cleans previous setup** - Removes containers, volumes, and generated files
2. **Initializes nodes** - Runs `init-nodes.sh` to create 4 nodes with genesis
3. **Copies genesis file** - Copies the final genesis to `docker/genesis/`
4. **Copies keyrings** - Copies validator account keys to `docker/keys/`
5. **Copies node keys** - Copies P2P node keys to `docker/node-keys/` for persistent node IDs
6. **Copies validator keys** - Copies consensus keys to `docker/validator-keys/`
7. **Maps validator keys** - Fixes the mapping to match GenTx order (node3, node1, node2, node0)
8. **Updates docker-compose** - Extracts node IDs and updates persistent_peers
9. **Builds images** - Builds Docker images
10. **Starts network** - Starts all 4 nodes, Prometheus, and Grafana

## Manual Steps (if needed)

If you prefer to run steps manually:

```bash
# 1. Initialize nodes
./scripts/init-nodes.sh

# 2. Copy files
cp node0/config/genesis.json docker/genesis/genesis.json
for i in {0..3}; do
    cp -r "node$i/keyring-test" "docker/keys/node$i-keyring"
    cp "node$i/config/node_key.json" "docker/node-keys/node$i-node_key.json"
    cp "node$i/config/priv_validator_key.json" "docker/validator-keys/node$i-priv_validator_key.json"
done

# 3. Fix validator key mapping (GenTx order: node3, node1, node2, node0)
cp docker/validator-keys/node3-priv_validator_key.json docker/validator-keys/node0-priv_validator_key.json.tmp
cp docker/validator-keys/node0-priv_validator_key.json docker/validator-keys/node3-priv_validator_key.json.tmp
mv docker/validator-keys/node0-priv_validator_key.json.tmp docker/validator-keys/node3-priv_validator_key.json
mv docker/validator-keys/node3-priv_validator_key.json.tmp docker/validator-keys/node0-priv_validator_key.json

# 4. Update docker-compose with node IDs
./scripts/update-docker-node-ids.sh

# 5. Start network
docker-compose -f docker-compose.localnet.yml up -d
```

## Verification

After running the setup script, wait 1-2 minutes for nodes to initialize, then check:

```bash
# Check container status
docker-compose -f docker-compose.localnet.yml ps

# Check block height
curl -s http://localhost:26657/status | python3 -c "import sys, json; print(json.load(sys.stdin)['result']['sync_info']['latest_block_height'])"

# Check peer connections
curl -s http://localhost:26657/net_info | python3 -c "import sys, json; print(len(json.load(sys.stdin)['result']['peers']))"

# View logs
docker-compose -f docker-compose.localnet.yml logs -f
```

## Cleanup

To clean everything and start fresh:

```bash
docker-compose -f docker-compose.localnet.yml down -v
rm -rf node* docker/genesis/genesis.json docker/keys/* docker/node-keys/* docker/validator-keys/*
```

Then run `./scripts/setup-localnet.sh` again.

## Troubleshooting

If nodes don't connect:
- Check that node IDs in docker-compose match the actual node IDs
- Run `./scripts/update-docker-node-ids.sh` to update them
- Restart containers: `docker-compose -f docker-compose.localnet.yml restart`

If validators aren't recognized:
- Verify validator keys are correctly mapped (node0 ↔ node3 swap)
- Check logs: `docker-compose -f docker-compose.localnet.yml logs dydxprotocol-node0 | grep validator`

## Files Structure

```
protocol/
├── scripts/
│   ├── setup-localnet.sh          # Main automated setup script
│   ├── init-nodes.sh               # Initialize 4 nodes
│   └── update-docker-node-ids.sh   # Update node IDs in docker-compose
├── docker/
│   ├── genesis/
│   │   └── genesis.json           # Shared genesis file
│   ├── keys/
│   │   ├── node0-keyring/         # Validator account keys
│   │   ├── node1-keyring/
│   │   ├── node2-keyring/
│   │   └── node3-keyring/
│   ├── node-keys/
│   │   ├── node0-node_key.json    # P2P node keys (for persistent node IDs)
│   │   ├── node1-node_key.json
│   │   ├── node2-node_key.json
│   │   └── node3-node_key.json
│   └── validator-keys/
│       ├── node0-priv_validator_key.json  # Consensus keys (mapped to match GenTx)
│       ├── node1-priv_validator_key.json
│       ├── node2-priv_validator_key.json
│       └── node3-priv_validator_key.json
└── docker-compose.localnet.yml     # Docker Compose configuration
```

## Success Indicators

✅ All 4 containers running and healthy  
✅ Block height > 0  
✅ Each node has 3 peers  
✅ Logs show "This node is a validator"  
✅ No connection errors in logs  

The network is fully operational when all these conditions are met!

