#!/usr/bin/env bash
set -e

CHAIN_ID="alyxtest-4"
DAEMON_HOME="$HOME/.alyx"

echo "Setting up Cosmovisor directories..."

mkdir -p $DAEMON_HOME/cosmovisor/genesis/bin

echo "Download ALYX binary:"
echo "wget https://alyxai.org/downloads/$CHAIN_ID/v0.1.0/linux-amd64/alyxd"

echo "Then move it:"
echo "mv alyxd $DAEMON_HOME/cosmovisor/genesis/bin/"
echo "chmod +x $DAEMON_HOME/cosmovisor/genesis/bin/alyxd"

echo "Download genesis:"
echo "wget https://alyxai.org/networks/$CHAIN_ID/genesis.json -O $DAEMON_HOME/config/genesis.json"

echo "Done."
