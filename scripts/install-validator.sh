#!/usr/bin/env bash
set -euo pipefail

NETWORK="${NETWORK:-mainnet}"
MONIKER="${MONIKER:-alyx-validator}"
ALYX_HOME="${ALYX_HOME:-$HOME/.alyx}"
ALYX_USER="${ALYX_USER:-$USER}"

ALYX_VERSION="${ALYX_VERSION:-v0.2.2}"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://alyxai.org/downloads}"
NETWORK_BASE="${NETWORK_BASE:-https://alyxai.org/networks}"

COSMOVISOR_BIN="${COSMOVISOR_BIN:-$HOME/go/bin/cosmovisor}"
DAEMON_NAME="${DAEMON_NAME:-alyxd}"
SERVICE_NAME="${SERVICE_NAME:-alyxd}"

case "$NETWORK" in
  mainnet)
    CHAIN_ID="${CHAIN_ID:-alyx-1}"
    RUNTIME_SLOT="${RUNTIME_SLOT:-genesis}"
    EXPECTED_SHA256="${EXPECTED_SHA256:-65931a3c15ec57712c11e6006e56d8e3f64a5a4982c441da9e3b5b08a5a5a9c6}"

    # Mainnet public seed/peer infrastructure should be added here once confirmed.
    # Until then, addrbook.json + CometBFT peer discovery will be used.
    SEEDS="${SEEDS:-}"
    PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
    ;;
  testnet)
    CHAIN_ID="${CHAIN_ID:-alyxtest-4}"
    RUNTIME_SLOT="${RUNTIME_SLOT:-tokenfactory-v1}"

    # Leave empty by default so the downloaded sha256sum.txt is the source of truth.
    EXPECTED_SHA256="${EXPECTED_SHA256:-}"

    SEEDS="${SEEDS:-150de304a7f498bd10d68f9fe6698a6a7addd48f@seed.alyxai.org:26656,cf242dd238a236074d8551d2fe04f6e8f409a6a3@seed2.alyxai.org:26656}"
    PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
    ;;
  *)
    echo "Invalid NETWORK: $NETWORK"
    echo "Use NETWORK=mainnet or NETWORK=testnet"
    exit 1
    ;;
esac

BINARY_URL="${BINARY_URL:-$DOWNLOAD_BASE/$CHAIN_ID/$ALYX_VERSION/linux-amd64/alyxd}"
CHECKSUM_URL="${CHECKSUM_URL:-$DOWNLOAD_BASE/$CHAIN_ID/$ALYX_VERSION/linux-amd64/sha256sum.txt}"
GENESIS_URL="${GENESIS_URL:-$NETWORK_BASE/$CHAIN_ID/genesis.json}"
ADDRBOOK_URL="${ADDRBOOK_URL:-$NETWORK_BASE/$CHAIN_ID/addrbook.json}"

echo "============================================"
echo " ALYX VALIDATOR BOOTSTRAP"
echo "============================================"
echo "Network:         $NETWORK"
echo "Chain ID:        $CHAIN_ID"
echo "Moniker:         $MONIKER"
echo "ALYX Home:       $ALYX_HOME"
echo "Runtime Slot:    $RUNTIME_SLOT"
echo "Download Path:   $ALYX_VERSION"
echo "Binary URL:      $BINARY_URL"
echo "Genesis URL:     $GENESIS_URL"
echo "Addrbook URL:    $ADDRBOOK_URL"
echo "============================================"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Linux required"
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required"
  exit 1
fi

echo "[1/13] Installing dependencies..."
sudo apt update
sudo apt install -y curl wget jq git build-essential

if ! command -v go >/dev/null 2>&1; then
  echo "Go is required to install Cosmovisor"
  echo "Install Go 1.24+ and rerun this installer."
  exit 1
fi

echo "[2/13] Installing Cosmovisor..."
if [[ ! -x "$COSMOVISOR_BIN" ]]; then
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest
fi

export PATH="$HOME/go/bin:$PATH"

if [[ ! -x "$COSMOVISOR_BIN" ]]; then
  echo "Cosmovisor install failed"
  exit 1
fi

echo "[3/13] Checking public artifacts..."
for URL in "$BINARY_URL" "$CHECKSUM_URL" "$GENESIS_URL"; do
  if ! curl -fsI "$URL" >/dev/null; then
    echo "Missing or unreachable artifact:"
    echo "$URL"
    exit 1
  fi
done

if ! curl -fsI "$ADDRBOOK_URL" >/dev/null; then
  echo "Warning: addrbook.json is not reachable. Continuing without addrbook."
fi

echo "[4/13] Creating directories..."
mkdir -p \
  "$ALYX_HOME/config" \
  "$ALYX_HOME/data" \
  "$ALYX_HOME/cosmovisor/genesis/bin" \
  "$ALYX_HOME/cosmovisor/upgrades/$RUNTIME_SLOT/bin"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[5/13] Downloading binary..."
wget -q -O "$TMP_DIR/alyxd" "$BINARY_URL"
chmod +x "$TMP_DIR/alyxd"

echo "[6/13] Verifying checksum..."
wget -q -O "$TMP_DIR/sha256sum.txt" "$CHECKSUM_URL"

DOWNLOADED_EXPECTED="$(awk '/alyxd/ {print $1; exit} /^[a-fA-F0-9]{64}/ {print $1; exit}' "$TMP_DIR/sha256sum.txt")"
ACTUAL_SHA256="$(sha256sum "$TMP_DIR/alyxd" | awk '{print $1}')"

if [[ -z "$DOWNLOADED_EXPECTED" ]]; then
  echo "Could not read expected checksum from sha256sum.txt"
  exit 1
fi

if [[ -n "$EXPECTED_SHA256" && "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "Checksum mismatch against locked checksum"
  echo "Expected: $EXPECTED_SHA256"
  echo "Actual:   $ACTUAL_SHA256"
  exit 1
fi

if [[ "$ACTUAL_SHA256" != "$DOWNLOADED_EXPECTED" ]]; then
  echo "Checksum mismatch against downloaded sha256sum.txt"
  echo "Expected: $DOWNLOADED_EXPECTED"
  echo "Actual:   $ACTUAL_SHA256"
  exit 1
fi

echo "Checksum OK: $ACTUAL_SHA256"

echo "[7/13] Installing binary..."
install -m 755 "$TMP_DIR/alyxd" "$ALYX_HOME/cosmovisor/genesis/bin/alyxd"
install -m 755 "$TMP_DIR/alyxd" "$ALYX_HOME/cosmovisor/upgrades/$RUNTIME_SLOT/bin/alyxd"

if [[ "$RUNTIME_SLOT" == "genesis" ]]; then
  ln -sfn "$ALYX_HOME/cosmovisor/genesis" "$ALYX_HOME/cosmovisor/current"
else
  ln -sfn "$ALYX_HOME/cosmovisor/upgrades/$RUNTIME_SLOT" "$ALYX_HOME/cosmovisor/current"
fi

sudo ln -sf "$ALYX_HOME/cosmovisor/current/bin/alyxd" /usr/local/bin/alyxd

echo "[8/13] Initializing node..."
if [[ ! -f "$ALYX_HOME/config/node_key.json" ]]; then
  /usr/local/bin/alyxd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$ALYX_HOME"
fi

echo "[9/13] Downloading network files..."
wget -q -O "$ALYX_HOME/config/genesis.json" "$GENESIS_URL"

if curl -fsI "$ADDRBOOK_URL" >/dev/null; then
  wget -q -O "$ALYX_HOME/config/addrbook.json" "$ADDRBOOK_URL"
fi

echo "[10/13] Validating genesis chain ID..."
GENESIS_CHAIN_ID="$(jq -r '.chain_id' "$ALYX_HOME/config/genesis.json")"

if [[ "$GENESIS_CHAIN_ID" != "$CHAIN_ID" ]]; then
  echo "Genesis chain_id mismatch"
  echo "Expected: $CHAIN_ID"
  echo "Actual:   $GENESIS_CHAIN_ID"
  exit 1
fi

echo "Genesis OK: $GENESIS_CHAIN_ID"

echo "[11/13] Applying safe config..."
sed -i 's|^indexer *=.*|indexer = "null"|' "$ALYX_HOME/config/config.toml"
sed -i 's|^prometheus *=.*|prometheus = true|' "$ALYX_HOME/config/config.toml"
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0ualyx"|' "$ALYX_HOME/config/app.toml"

sed -i 's|^pruning *=.*|pruning = "custom"|' "$ALYX_HOME/config/app.toml"
sed -i 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' "$ALYX_HOME/config/app.toml"
sed -i 's|^pruning-interval *=.*|pruning-interval = "10"|' "$ALYX_HOME/config/app.toml"

if [[ -n "$SEEDS" ]]; then
  sed -i 's|^seeds *=.*|seeds = "'"$SEEDS"'"|' "$ALYX_HOME/config/config.toml"
else
  sed -i 's|^seeds *=.*|seeds = ""|' "$ALYX_HOME/config/config.toml"
fi

if [[ -n "$PERSISTENT_PEERS" ]]; then
  sed -i 's|^persistent_peers *=.*|persistent_peers = "'"$PERSISTENT_PEERS"'"|' "$ALYX_HOME/config/config.toml"
else
  sed -i 's|^persistent_peers *=.*|persistent_peers = ""|' "$ALYX_HOME/config/config.toml"
fi

# Do not enable state sync by default until production snapshot serving is confirmed.
if grep -q '^\[statesync\]' "$ALYX_HOME/config/config.toml"; then
  sed -i '/^\[statesync\]/,/^\[/ s|^enable *=.*|enable = false|' "$ALYX_HOME/config/config.toml"
fi

echo "[12/13] Creating systemd service..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<EOF
[Unit]
Description=ALYX Node
After=network-online.target
Wants=network-online.target

[Service]
User=${ALYX_USER}
ExecStart=${COSMOVISOR_BIN} run start --home ${ALYX_HOME}
Restart=always
RestartSec=5
LimitNOFILE=65535
Environment="DAEMON_NAME=${DAEMON_NAME}"
Environment="DAEMON_HOME=${ALYX_HOME}"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="UNSAFE_SKIP_BACKUP=false"

[Install]
WantedBy=multi-user.target
EOF

echo "[13/13] Enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}

echo
echo "============================================"
echo " ALYX BOOTSTRAP COMPLETE"
echo "============================================"
echo "Network:       ${NETWORK}"
echo "Chain ID:      ${CHAIN_ID}"
echo "Runtime Slot:  ${RUNTIME_SLOT}"
echo "SHA256:        ${ACTUAL_SHA256}"
echo "Service:       ${SERVICE_NAME}"
echo
echo "The node has been installed but not started automatically."
echo
echo "Start:"
echo "  sudo systemctl start ${SERVICE_NAME}"
echo
echo "Logs:"
echo "  sudo journalctl -u ${SERVICE_NAME} -f"
echo
echo "Status:"
echo "  curl -s http://127.0.0.1:26657/status | jq '.result.node_info.network, .result.sync_info.latest_block_height, .result.sync_info.catching_up'"
echo
echo "Cosmovisor current:"
echo "  readlink -f ${ALYX_HOME}/cosmovisor/current"
echo "============================================"
