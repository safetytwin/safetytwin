#!/bin/bash
# Usage: gotty_vm_shell.sh <VM_NAME>
# Dynamically runs gotty for the current IP of the VM

if [ -z "$1" ]; then
  echo "Usage: $0 <VM_NAME>"
  exit 1
fi

VM_NAME="$1"
USER="ubuntu"
PORT=8080

# Find the current IP of the VM using virsh domifaddr
VM_IP=$(virsh domifaddr "$VM_NAME" | awk '/ipv4/ {print $4}' | cut -d'/' -f1 | head -n 1)
if [ -z "$VM_IP" ]; then
  echo "Could not find IP for VM $VM_NAME"
  exit 2
fi

# Check if gotty is installed
if ! command -v gotty >/dev/null 2>&1; then
  echo "gotty not found. Please install gotty first."
  exit 3
fi

# Run gotty to provide a web terminal for this VM
exec gotty -p $PORT --permit-write --reconnect /usr/bin/ssh -o StrictHostKeyChecking=no $USER@$VM_IP
