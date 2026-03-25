#!/usr/bin/env bash

cat <<EOF
[Unit]
Description=ALYX Validator
After=network-online.target

[Service]
User=root
ExecStart=/root/go/bin/cosmovisor run start
Restart=always
RestartSec=5
LimitNOFILE=4096

Environment="DAEMON_NAME=alyxd"
Environment="DAEMON_HOME=/root/.alyx"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"

[Install]
WantedBy=multi-user.target
EOF
