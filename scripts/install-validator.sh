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

COSMOVISOR_BIN="${COSMOVISOR_BIN:-$HOME/go/bin/cosmovisor}"
DAEMON_NAME="alyxd"

echo "=================================================="
echo "ALYX one-click validator bootstrap"
echo "Chain ID:        $CHAIN_ID"
echo "Moniker:         $MONIKER"
echo "Home:            $ALYX_HOME"
echo "Version:         $ALYX_VERSION"
echo "Binary URL:      $BINARY_URL"
echo "Checksum URL:    $CHECKSUM_URL"
echo "Genesis URL:     $GENESIS_URL"
echo "Addrbook URL:    $ADDRBOOK_URL"
echo "=================================================="

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script supports Linux only."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required."
  exit 1
fi

echo "[1/12] Installing base dependencies..."
sudo apt update
sudo apt install -y curl wget jq git build-essential

if ! command -v go >/dev/null 2>&1; then
  echo
  echo "Go is not installed."
  echo "Install Go 1.24+ first, then re-run this script."
  exit 1
fi

echo "[2/12] Installing Cosmovisor if needed..."
if [[ ! -x "$COSMOVISOR_BIN" ]]; then
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
else
  echo "Cosmovisor already present: $COSMOVISOR_BIN"
fi

export PATH="$HOME/go/bin:$PATH"

echo "[3/12] Preparing directories..."
mkdir -p "$ALYX_HOME/config"
mkdir -p "$ALYX_HOME/data"
mkdir -p "$ALYX_HOME/cosmovisor/genesis/bin"
mkdir -p "$ALYX_HOME/cosmovisor/upgrades"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[4/12] Downloading binary..."
wget -q -O "$TMP_DIR/alyxd" "$BINARY_URL"
chmod +x "$TMP_DIR/alyxd"

echo "[5/12] Downloading checksum..."
if wget -q -O "$TMP_DIR/sha256sum.txt" "$CHECKSUM_URL"; then
  EXPECTED_SHA="$(awk '{print $1}' "$TMP_DIR/sha256sum.txt" | head -n1)"
  ACTUAL_SHA="$(sha256sum "$TMP_DIR/alyxd" | awk '{print $1}')"

  echo "Expected SHA: $EXPECTED_SHA"
  echo "Actual SHA:   $ACTUAL_SHA"

  if [[ -n "$EXPECTED_SHA" && "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
    echo "Checksum mismatch. Aborting."
    exit 1
  fi
else
  echo "Warning: checksum download failed. Continuing without checksum verification."
fi

echo "[6/12] Installing binary into Cosmovisor genesis path..."
install -m 755 "$TMP_DIR/alyxd" "$ALYX_HOME/cosmovisor/genesis/bin/alyxd"
sudo ln -sf "$ALYX_HOME/cosmovisor/genesis/bin/alyxd" /usr/local/bin/alyxd

echo "[7/12] Initializing node home if needed..."
if [[ ! -f "$ALYX_HOME/config/node_key.json" ]]; then
  alyxd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$ALYX_HOME"
else
  echo "Node home already initialized. Skipping init."
fi

echo "[8/12] Downloading network files..."
wget -q -O "$ALYX_HOME/config/genesis.json" "$GENESIS_URL"

if wget -q -O "$ALYX_HOME/config/addrbook.json" "$ADDRBOOK_URL"; then
  echo "Addrbook downloaded."
else
  echo "Addrbook not found. Continuing without addrbook."
fi

echo "[9/12] Writing sane defaults..."
sed -i 's|^indexer *=.*|indexer = "null"|' "$ALYX_HOME/config/config.toml" || true
sed -i 's|^prometheus *=.*|prometheus = true|' "$ALYX_HOME/config/config.toml" || true
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0ualyx"|' "$ALYX_HOME/config/app.toml" || true

echo "[10/12] Writing systemd service..."
sudo tee /etc/systemd/system/alyxd.service >/dev/null <<EOF
[Unit]
Description=ALYX Validator
After=network-online.target
Wants=network-online.target

[Service]
User=$ALYX_USER
Group=$ALYX_USER
ExecStart=$HOME/go/bin/cosmovisor run start --home $ALYX_HOME
Restart=always
RestartSec=5
LimitNOFILE=65535
Environment="DAEMON_NAME=$DAEMON_NAME"
Environment="DAEMON_HOME=$ALYX_HOME"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"

[Install]
WantedBy=multi-user.target
EOF

echo "[11/12] Reloading systemd..."
sudo systemctl daemon-reload
sudo systemctl enable alyxd

echo "[12/12] Starting validator service..."
sudo systemctl restart alyxd

echo
echo "Bootstrap complete."
echo
echo "Useful commands:"
echo "  sudo systemctl status alyxd --no-pager -l"
echo "  journalctl -u alyxd -f"
echo "  curl -s http://127.0.0.1:26657/status | jq"
echo
echo "Next steps:"
echo "  1. Wait for sync"
echo "  2. Create/import wallet"
echo "  3. Fund wallet"
echo "  4. Create validator"
echo
echo "Create wallet:"
echo "  alyxd keys add validator"
echo
echo "Create validator:"
echo "  alyxd tx staking create-validator \\"
echo "    --amount=1000000ualyx \\"
echo "    --from=validator \\"
echo "    --chain-id=$CHAIN_ID \\"
echo "    --commission-rate=0.10 \\"
echo "    --moniker=\"$MONIKER\" \\"
echo "    --gas auto \\"
echo "    --fees 5000ualyx"
