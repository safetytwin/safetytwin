#!/bin/bash
# preinstall.sh - Minimal VM/cloud-init test for troubleshooting SSH and provisioning
# Author: Tom Sapletta
# Date: 2025-05-11
set -e

VM_NAME="safetytwin-vm"
CLOUD_INIT_DIR="/var/lib/safetytwin/cloud-init"
IMG_DIR="/var/lib/safetytwin/images"
BASE_IMG="$IMG_DIR/ubuntu-base.img"
USER_DATA="$CLOUD_INIT_DIR/user-data"
META_DATA="$CLOUD_INIT_DIR/meta-data"
ISO="$CLOUD_INIT_DIR/cloud-init.iso"

# 1. Stop and remove existing VM (ignore errors if not present)
echo "[preinstall.sh] Shutting down and removing old VM if exists..."
sudo virsh destroy "$VM_NAME" || true
sudo virsh undefine --nvram "$VM_NAME" || true

# 2. Generate minimal cloud-init user-data and meta-data
echo "[preinstall.sh] Generating minimal cloud-init user-data and meta-data..."
sudo bash -c "cat > $USER_DATA << EOF
#cloud-config
password: ubuntu
chpasswd: { expire: False }
ssh_pwauth: true
EOF"

sudo bash -c "cat > $META_DATA << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF"

# 3. Rebuild cloud-init ISO
echo "[preinstall.sh] Rebuilding cloud-init ISO..."
sudo genisoimage -output "$ISO" -volid cidata -joliet -rock "$META_DATA" "$USER_DATA"
sudo chmod 644 "$ISO"
sudo chown libvirt-qemu:libvirt-qemu "$ISO"

# 4. Create and start the VM with minimal config
echo "[preinstall.sh] Creating and starting new VM..."
sudo virt-install --name "$VM_NAME" \
  --memory 1024 \
  --vcpus 1 \
  --disk "$BASE_IMG",device=disk,bus=virtio \
  --disk "$ISO",device=cdrom,bus=sata \
  --os-variant ubuntu20.04 \
  --virt-type kvm \
  --graphics none \
  --network network=default,model=virtio \
  --import \
  --noautoconsole \
  --check path_in_use=off

echo "[preinstall.sh] VM created. Use 'sudo virsh console $VM_NAME' to access the console."
echo "Try logging in as 'ubuntu' with password 'ubuntu'. If SSH still fails, debug from the console."
