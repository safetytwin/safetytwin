#!/bin/bash
set -e
cd "$(dirname "$0")"
VM="safetytwin-vm"
SNAP="auto-backup-$(date +%Y%m%d%H%M%S)"
virsh snapshot-create-as "$VM" "$SNAP" --description "Automatyczny backup SafetyTwin VM"
echo "[OK] Utworzono snapshot $SNAP dla $VM"
