#!/bin/bash
# Skrypt do usuwania bieżącej maszyny wirtualnej Digital Twin (libvirt)
set -euo pipefail

VM_NAME="safetytwin-vm"

if virsh list --all | grep -q "$VM_NAME"; then
  echo "[INFO] Zatrzymuję VM..."
  sudo virsh destroy "$VM_NAME" || true
  echo "[INFO] Usuwam VM z libvirt..."
  sudo virsh undefine "$VM_NAME" --remove-all-storage || sudo virsh undefine "$VM_NAME"
  echo "[INFO] Usunięto VM: $VM_NAME"
else
  echo "[INFO] VM $VM_NAME nie istnieje."
fi
