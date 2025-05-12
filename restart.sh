#!/bin/bash
# restart.sh - Automate full VM teardown, install, diagnose, and repair for safetytwin
# Author: Tom Sapletta
# Date: 2025-05-11
set -e

# Vars
VM_NAME="safetytwin-vm"
CLOUD_INIT_DIR="/var/lib/safetytwin/cloud-init"
IMG_DIR="/var/lib/safetytwin/images"
BASE_IMG="$IMG_DIR/ubuntu-base.img"
USER_DATA="$CLOUD_INIT_DIR/user-data"
META_DATA="$CLOUD_INIT_DIR/meta-data"
ISO="$CLOUD_INIT_DIR/cloud-init.iso"

# 1. Stop and remove existing VM (ignore errors if not present)
echo "[restart.sh] Shutting down and removing old VM if exists..."
if sudo virsh dominfo "$VM_NAME" &>/dev/null; then
  sudo virsh shutdown "$VM_NAME" || true
  SNAPSHOTS=$(sudo virsh snapshot-list "$VM_NAME" --name 2>/dev/null | grep -v '^$' | grep -v '^Name')
  if [ -n "$SNAPSHOTS" ]; then
    echo "[restart.sh] Deleting snapshots for VM: $VM_NAME"
    for SNAP in $SNAPSHOTS; do
      echo "  - Deleting snapshot: $SNAP"
      sudo virsh snapshot-delete "$VM_NAME" "$SNAP" --metadata || true
    done
  fi
  sudo virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
  sleep 10
  sudo virsh undefine --nvram "$VM_NAME" || true
else
  echo "[restart.sh] No existing VM named $VM_NAME found, skipping shutdown/undefine."
fi

# 2. Regenerate cloud-init user-data and meta-data
echo "[restart.sh] Regenerating cloud-init user-data and meta-data..."
sudo bash -c "cat > $USER_DATA << EOF
#cloud-config
hostname: safetytwin-vm
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: \$6\$rounds=4096\$OX4t4MRpbg\$QJLlRfXTl9Jgp9YlUhg5vpZ72X9vK49XnfUm.XIekX.ZD5xQvS3DVJ9jYmTvS0wIULgBX6Ix0NVx2xEIyNVYv/
ssh_pwauth: true
chpasswd:
  expire: false
package_update: true
packages:
  - qemu-guest-agent
  - openssh-server
  - python3

network:
  version: 2
  ethernets:
    ens3:
      dhcp4: true
    eth0:
      dhcp4: true
    enp1s0:
      dhcp4: true
EOF"

sudo bash -c "cat > $META_DATA << EOF
instance-id: safetytwin-vm
local-hostname: safetytwin-vm
EOF"

# 3. Rebuild cloud-init ISO
echo "[restart.sh] Rebuilding cloud-init ISO..."
sudo genisoimage -output "$ISO" -volid cidata -joliet -rock "$META_DATA" "$USER_DATA"
sudo chmod 644 "$ISO"
sudo chown libvirt-qemu:libvirt-qemu "$ISO"

# 4. Recreate and start the VM
echo "[restart.sh] Creating and starting new VM..."
# 4. Recreate and start the VM, attach cloud-init ISO as IDE CD-ROM (hdc)
sudo virt-install --name "$VM_NAME" \
  --memory 2048 \
  --vcpus 2 \
  --disk "$BASE_IMG",device=disk,bus=virtio \
  --disk "$ISO",device=cdrom,bus=sata \
  --os-variant ubuntu20.04 \
  --virt-type kvm \
  --graphics none \
  --network network=default,model=virtio \
  --import \
  --noautoconsole \
  --check path_in_use=off

# 5. Run main install script
echo "[restart.sh] Running install.sh..."
sudo bash install.sh

# 6. Optionally run diagnostics and repair if available
if [ -f "repair.sh" ]; then
  echo "[restart.sh] Running repair.sh..."
  sudo bash repair.sh INSTALL_RESULT.yaml | tee -a install.log
fi
if [ -f "diagnose-vm-network.sh" ]; then
  echo "[restart.sh] Running diagnose-vm-network.sh..."
  sudo bash diagnose-vm-network.sh | tee -a install.log
fi

echo "[restart.sh] All steps complete. Check install.log and VM status."
