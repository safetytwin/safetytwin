#!/bin/bash
# set-ubuntu-password.sh - Force set ubuntu password inside VM disk image
# Usage: sudo bash set-ubuntu-password.sh [password]
# Default password: safetytwin
set -e

VM_IMG="/var/lib/safetytwin/images/ubuntu-base.img"
MNT_DIR="/mnt/safetytwin-vm-root"
PASSWORD="${1:-safetytwin}"

if ! command -v guestmount >/dev/null; then
  echo "[ERROR] guestmount (libguestfs-tools) not installed. Installing..."
  sudo apt-get update && sudo apt-get install -y libguestfs-tools
fi

# Unmount if already mounted
if mount | grep -q "$MNT_DIR"; then
  echo "[INFO] Unmounting previous mount at $MNT_DIR ..."
  sudo guestunmount "$MNT_DIR" || sudo umount "$MNT_DIR" || true
fi

# Create mount dir
sudo mkdir -p "$MNT_DIR"
echo "[INFO] Mounting VM image..."
sudo guestmount -a "$VM_IMG" -i --rw "$MNT_DIR"

# Set password inside chroot
cat << EOF | sudo chroot "$MNT_DIR" /bin/bash
  echo "ubuntu:$PASSWORD" | chpasswd
  echo "[INFO] Password for ubuntu set to '$PASSWORD'"
EOF

# Unmount
sudo guestunmount "$MNT_DIR"
echo "[INFO] Done. Password for ubuntu user forcibly set to '$PASSWORD' in VM image."
