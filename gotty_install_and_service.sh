#!/bin/bash
# gotty_install_and_service.sh - Install and enable gotty web terminal as a systemd service for Ubuntu VM
# Usage: bash gotty_install_and_service.sh

set -e

GOTTY_VERSION="1.4.0"
GOTTY_URL="https://github.com/yudai/gotty/releases/download/v$GOTTY_VERSION/gotty_linux_amd64.tar.gz"
GOTTY_BIN="/usr/local/bin/gotty"

if ! command -v gotty &>/dev/null; then
  echo "[gotty] Installing gotty..."
  wget -O /tmp/gotty.tar.gz "$GOTTY_URL"
  tar -xzf /tmp/gotty.tar.gz -C /tmp
  sudo mv /tmp/gotty "$GOTTY_BIN"
  sudo chmod +x "$GOTTY_BIN"
else
  echo "[gotty] Already installed."
fi

# Create gotty systemd service
cat <<EOF | sudo tee /etc/systemd/system/gotty.service
[Unit]
Description=GoTTY Web Terminal
After=network.target

[Service]
Type=simple
User=ubuntu
ExecStart=$GOTTY_BIN --port 8080 --permit-write --credential ubuntu:ubuntu bash
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable gotty.service
sudo systemctl restart gotty.service

echo "[gotty] Service enabled and started on port 8080."
