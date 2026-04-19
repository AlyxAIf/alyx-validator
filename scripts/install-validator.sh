#!/usr/bin/env bash
set -euo pipefail

CHAIN_ID="${CHAIN_ID:-alyxtest-4}"
MONIKER="${MONIKER:-alyx-validator}"
ALYX_HOME="${ALYX_HOME:-$HOME/.alyx}"
ALYX_USER="${ALYX_USER:-$USER}"

RUNTIME_SLOT="${RUNTIME_SLOT:-tokenfactory-v1}"
DOWNLOAD_VERSION="${DOWNLOAD_VERSION:-v0.2.2}"

DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://alyxai.org/downloads}"
NETWORK_BASE="${NETWORK_BASE:-https://alyxai.org/networks}"

BINARY_URL="${BINARY_URL:-$DOWNLOAD_BASE/$CHAIN_ID/$DOWNLOAD_VERSION/linux-amd64/alyxd}"
CHECKSUM_URL="${CHECKSUM_URL:-$DOWNLOAD_BASE/$CHAIN_ID/$DOWNLOAD_VERSION/linux-amd64/sha256sum.txt}"
GENESIS_URL="${GENESIS_URL:-$NETWORK_BASE/$CHAIN_ID/genesis.json}"
ADDRBOOK_URL="${ADDRBOOK_URL:-$NETWORK_BASE/$CHAIN_ID/addrbook.json}"

EXPECTED_SHA256="${EXPECTED_SHA256:-f82f2a91abf88c68ce58ec977feab99f57822a0f9de428e746a944cd4b307735}"

SEEDS='150de304a7f498bd10d68f9fe6698a6a7addd48f@seed.alyxai.org:26656,cf242dd238a236074d8551d2fe04f6e8f409a6a3@seed2.alyxai.org:26656'

COSMOVISOR_BIN="${COSMOVISOR_BIN:-$HOME/go/bin/cosmovisor}"
DAEMON_NAME="alyxd"
SERVICE_NAME="alyxd"

echo "============================================"
echo " ALYX VALIDATOR BOOTSTRAP"
echo "============================================"
echo "Chain ID:        $CHAIN_ID"
echo "Moniker:         $MONIKER"
echo "ALYX Home:       $ALYX_HOME"
echo "Runtime Slot:    $RUNTIME_SLOT"
echo "Download Path:   $DOWNLOAD_VERSION"
echo "Binary URL:      $BINARY_URL"
echo "============================================"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Linux required"
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required"
  exit 1
fi

echo "[1/12] Installing dependencies..."
sudo apt update
sudo apt install -y curl wget jq git build-essential

if ! command -v go >/dev/null 2>&1; then
  echo "Go is required to install Cosmovisor"
  exit 1
fi

echo "[2/12] Installing Cosmovisor..."
if [[ ! -x "$COSMOVISOR_BIN" ]]; then
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
fi
export PATH="$HOME/go/bin:$PATH"

if [[ ! -x "$COSMOVISOR_BIN" ]]; then
  echo "Cosmovisor install failed"
  exit 1
fi

echo "[3/12] Creating directories..."
mkdir -p \
  "$ALYX_HOME/config" \
  "$ALYX_HOME/data" \
  "$ALYX_HOME/cosmovisor/genesis/bin" \
  "$ALYX_HOME/cosmovisor/upgrades/$RUNTIME_SLOT/bin"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[4/12] Downloading binary..."
wget -q -O "$TMP_DIR/alyxd" "$BINARY_URL"
chmod +x "$TMP_DIR/alyxd"

echo "[5/12] Verifying checksum..."
wget -q -O "$TMP_DIR/sha256sum.txt" "$CHECKSUM_URL"

DOWNLOADED_EXPECTED="$(awk '{print $1}' "$TMP_DIR/sha256sum.txt" | head -n1)"
ACTUAL_SHA256="$(sha256sum "$TMP_DIR/alyxd" | awk '{print $1}')"

if [[ -n "$EXPECTED_SHA256" && "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "Checksum mismatch against locked validator runtime checksum"
  echo "Expected: $EXPECTED_SHA256"
  echo "Actual:   $ACTUAL_SHA256"
  exit 1
fi

if [[ -n "$DOWNLOADED_EXPECTED" && "$ACTUAL_SHA256" != "$DOWNLOADED_EXPECTED" ]]; then
  echo "Checksum mismatch against downloaded sha256sum.txt"
  echo "Expected: $DOWNLOADED_EXPECTED"
  echo "Actual:   $ACTUAL_SHA256"
  exit 1
fi

echo "Checksum OK: $ACTUAL_SHA256"

echo "[6/12] Installing binary into active upgrade slot..."
install -m 755 "$TMP_DIR/alyxd" "$ALYX_HOME/cosmovisor/upgrades/$RUNTIME_SLOT/bin/alyxd"
ln -sfn "$ALYX_HOME/cosmovisor/upgrades/$RUNTIME_SLOT" "$ALYX_HOME/cosmovisor/current"
sudo ln -sf "$ALYX_HOME/cosmovisor/current/bin/alyxd" /usr/local/bin/alyxd

echo "[7/12] Initializing node..."
if [[ ! -f "$ALYX_HOME/config/node_key.json" ]]; then
  /usr/local/bin/alyxd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$ALYX_HOME"
fi

echo "[8/12] Downloading network files..."
wget -q -O "$ALYX_HOME/config/genesis.json" "$GENESIS_URL"
wget -q -O "$ALYX_HOME/config/addrbook.json" "$ADDRBOOK_URL" || true

echo "[9/12] Applying config..."
sed -i 's|^seeds *=.*|seeds = "'"$SEEDS"'"|' "$ALYX_HOME/config/config.toml"
sed -i 's|^indexer *=.*|indexer = "null"|' "$ALYX_HOME/config/config.toml"
sed -i 's|^prometheus *=.*|prometheus = true|' "$ALYX_HOME/config/config.toml"
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0ualyx"|' "$ALYX_HOME/config/app.toml"
sed -i 's|^pruning *=.*|pruning = "custom"|' "$ALYX_HOME/config/app.toml"
sed -i 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' "$ALYX_HOME/config/app.toml"
sed -i 's|^pruning-interval *=.*|pruning-interval = "10"|' "$ALYX_HOME/config/app.toml"

echo "[10/12] Creating systemd service..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<EOF
[Unit]
Description=ALYX Node
After=network-online.target
Wants=network-online.target

[Service]
User=${ALYX_USER}
ExecStart=${COSMOVISOR_BIN} run start --home ${ALYX_HOME}
Restart=always
RestartSec=3
LimitNOFILE=65535
Environment="DAEMON_NAME=${DAEMON_NAME}"
Environment="DAEMON_HOME=${ALYX_HOME}"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=true"

[Install]
WantedBy=multi-user.target
EOF

echo "[11/12] Enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}

echo "[12/12] Bootstrap complete."
echo
echo "Next steps:"
echo "  1. Start the node:"
echo "     sudo systemctl start ${SERVICE_NAME}"
echo
echo "  2. Check logs:"
echo "     sudo journalctl -u ${SERVICE_NAME} -f"
echo
echo "  3. Verify runtime slot:"
echo "     readlink -f ${ALYX_HOME}/cosmovisor/current"
echo
echo "  4. Verify checksum:"
echo "     sha256sum ${ALYX_HOME}/cosmovisor/current/bin/alyxd"
echo
echo "Expected runtime:"
echo "  Chain ID:      ${CHAIN_ID}"
echo "  Runtime Slot:  ${RUNTIME_SLOT}"
echo "  SHA256:        ${EXPECTED_SHA256}"
echo
echo "Seed string:"
echo "  ${SEEDS}"
