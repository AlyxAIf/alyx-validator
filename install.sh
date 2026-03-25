#!/usr/bin/env bash
set -e

echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Installing dependencies..."
sudo apt install -y curl wget git jq build-essential

echo "Install Go manually if needed:"
echo "https://go.dev/dl/"

echo "Install Cosmovisor:"
echo "go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest"

echo "Done."
