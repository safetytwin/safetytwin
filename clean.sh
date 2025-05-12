#!/bin/bash
# clean.sh - Remove all VMs, snapshots, logs, and related resources for a clean environment
set -e
cd "$(dirname "$0")"

# 1. Remove all snapshots for all VMs
echo "[INFO] Removing all VM snapshots..."
for vm in $(virsh list --all --name); do
  for snap in $(virsh snapshot-list "$vm" --name); do
    echo "  Removing snapshot $snap for $vm"
    virsh snapshot-delete "$vm" --snapshotname "$snap" || true
  done
done

# 2. Shutdown all VMs
echo "[INFO] Shutting down all VMs..."
for vm in $(virsh list --all --name); do
  echo "  Shutting down $vm"
  virsh destroy "$vm" || true
done

# 3. Undefine (remove) all VMs
echo "[INFO] Removing all VMs..."
for vm in $(virsh list --all --name); do
  echo "  Undefining $vm"
  virsh undefine "$vm" --remove-all-storage || true
done

# 4. Remove logs
echo "[INFO] Removing logs..."
rm -f /var/log/safetytwin/orchestrator.log /var/log/safetytwin/orchestrator.err.log || true

# 5. Remove test marker files
echo "[INFO] Removing test files..."
rm -f /var/log/test_ansible.log /tmp/test_ansible.log || true

echo "[INFO] Clean up complete."
