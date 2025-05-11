#!/bin/bash
# Script to regenerate all systemd service files from template and copy them to /etc/systemd/system
# Requires root privileges for the copy step

set -e

PYTHON_SCRIPT="$HOME/safetytwin/safetytwin/scripts/generate_services.py"
SERVICES_DIR="$HOME/safetytwin/safetytwin/services"
SYSTEMD_DIR="/etc/systemd/system"

# Regenerate service files from template
echo "Generating service files using $PYTHON_SCRIPT..."
python3 "$PYTHON_SCRIPT"

# Copy all generated .service files to systemd directory
echo "Copying generated service files to $SYSTEMD_DIR (requires sudo)..."
sudo cp "$SERVICES_DIR"/*.service "$SYSTEMD_DIR"/

# Reload systemd and show status
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Checking status of updated services:"
for svc in "$SERVICES_DIR"/*.service; do
  svcname=$(basename "$svc")
  sudo systemctl status "$svcname" --no-pager || true
done

echo "Done."
