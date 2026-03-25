#!/usr/bin/env bash
set -euo pipefail

CHAIN_ID="${CHAIN_ID:-alyxtest-4}"
MONIKER="${MONIKER:-alyx-validator}"
ALYX_HOME="${ALYX_HOME:-$HOME/.alyx}"
ALYX_USER="${ALYX_USER:-$USER}"
ALYX_VERSION="${ALYX_VERSION:-v0.2.0}"

DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://alyxai.org/downloads}"
NETWORK_BASE="${NETWORK_BASE:-https://alyxai.org/networks}"

BINARY_URL="${BINARY_URL:-$DOWNLOAD_BASE/$CHAIN_ID/$ALYX_VERSION/linux-amd64/alyxd}"
CHECKSUM_URL="${CHECKSUM_URL:-$DOWNLOAD_BASE/$CHAIN_ID/$ALYX_VERSION/linux-amd64/sha256sum.txt}"
GENESIS_URL="${GENESIS_URL:-$NETWORK_BASE/$CHAIN_ID/genesis.json}"
ADDRBOOK_URL="${ADDRBOOK_URL:-$NETWORK_BASE/$CHAIN_ID/addrbook.json}"

SEEDS="150de304a7f498bd10d68f9fe6698a6a7addd48f@46.224.111.93:26656"

COSMOVISOR_BIN="${COSMOVISOR_BIN:-$HOME/go/bin/cosmovisor}"
DAEMON_NAME="alyxd"

echo "============================================"
echo " ALYX VALIDATOR BOOTSTRAP"
echo "============================================"
echo "Chain:     $CHAIN_ID"
echo "Version:   $ALYX_VERSION"
echo "Moniker:   $MONIKER"
echo "============================================"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Linux required"
  exit 1
fi

echo "[1/11] Installing dependencies..."
sudo apt update
sudo apt install -y curl wget jq git build-essential

if ! command -v go >/dev/null 2>&1; then
  echo "Go 1.24+ required"
  exit 1
fi

echo "[2/11] Installing Cosmovisor..."
if [[ ! -x "$COSMOVISOR_BIN" ]]; then
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
fi

export PATH="$HOME/go/bin:$PATH"

echo "[3/11] Creating directories..."
mkdir -p "$ALYX_HOME"/{config,data,cosmovisor/genesis/bin}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[4/11] Downloading binary..."
wget -q -O "$TMP_DIR/alyxd" "$BINARY_URL"
chmod +x "$TMP_DIR/alyxd"

echo "[5/11] Verifying checksum..."
wget -q -O "$TMP_DIR/sha256sum.txt" "$CHECKSUM_URL"

EXPECTED=$(awk '{print $1}' "$TMP_DIR/sha256sum.txt")
ACTUAL=$(sha256sum "$TMP_DIR/alyxd" | awk '{print $1}')

if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo "Checksum mismatch"
  exit 1
fi

echo "Checksum OK"

echo "[6/11] Installing binary..."
install -m 755 "$TMP_DIR/alyxd" "$ALYX_HOME/cosmovisor/genesis/bin/alyxd"
sudo ln -sf "$ALYX_HOME/cosmovisor/genesis/bin/alyxd" /usr/local/bin/alyxd

echo "[7/11] Initializing node..."
if [[ ! -f "$ALYX_HOME/config/node_key.json" ]]; then
  alyxd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$ALYX_HOME"
fi

echo "[8/11] Downloading network files..."
wget -q -O "$ALYX_HOME/config/genesis.json" "$GENESIS_URL"
wget -q -O "$ALYX_HOME/config/addrbook.json" "$ADDRBOOK_URL" || true

echo "[9/11] Applying config optimizations..."

sed -i 's|^seeds *=.*|seeds = "'"$SEEDS"'"|' "$ALYX_HOME/config/config.toml"
sed -i 's|^indexer *=.*|indexer = "null"|' "$ALYX_HOME/config/config.toml"
sed -i 's|^prometheus *=.*|prometheus = true|' "$ALYX_HOME/config/config.toml"

sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0ualyx"|' "$ALYX_HOME/config/app.toml"

# pruning (important)
sed -i 's|^pruning *=.*|pruning = "custom"|' "$ALYX_HOME/config/app.toml"
sed -i 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' "$ALYX_HOME/config/app.toml"
sed -i 's|^pruning-interval *=.*|pruning-interval = "10"|' "$ALYX_HOME/config/app.toml"

echo "[10/11] Creating systemd service..."

sudo tee /etc/systemd/system/alyxd.service >/dev/null <<EOF
[Unit]
Description=ALYX Validator
After=network-online.target

[Service]
User=$ALYX_USER
ExecStart=$HOME/go/bin/cosmovisor run start --home $ALYX_HOME
Restart=always
RestartSec=5
LimitNOFILE=65535

Environment="DAEMON_NAME=alyxd"
Environment="DAEMON_HOME=$ALYX_HOME"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"

[Install]
WantedBy=multi-user.target
EOF

echo "[11/11] Starting node..."

sudo systemctl daemon-reload
sudo systemctl enable alyxd
sudo systemctl restart alyxd

sleep 3

echo "============================================"
echo "Node started"
echo "============================================"

curl -s http://127.0.0.1:26657/status | jq '.result.sync_info'
echo
echo "Next:"
echo "1. Wait for full sync"
echo "2. alyxd keys add validator"
echo "3. Fund wallet"
echo "4. Create validator"
