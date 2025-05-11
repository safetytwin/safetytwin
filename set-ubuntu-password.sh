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

# Check if user exists
if ! sudo grep -q "^ubuntu:" "$MNT_DIR/etc/passwd"; then
  echo "[ERROR] User 'ubuntu' does not exist in the image. Password cannot be set."
  sudo guestunmount "$MNT_DIR"
  exit 2
fi

# Mount /proc, /dev, /sys for full PAM functionality
sudo mount --bind /proc "$MNT_DIR/proc"
sudo mount --bind /dev "$MNT_DIR/dev"
sudo mount --bind /sys "$MNT_DIR/sys"

# Set password inside chroot
sudo chroot "$MNT_DIR" /bin/bash -c "echo 'ubuntu:$PASSWORD' | chpasswd" && \
  echo "[INFO] Password for ubuntu set to '$PASSWORD'"

# Unmount /proc, /dev, /sys
sudo umount "$MNT_DIR/proc"
sudo umount "$MNT_DIR/dev"
sudo umount "$MNT_DIR/sys"

# Unmount image
sudo guestunmount "$MNT_DIR"
echo "[INFO] Done. Password for ubuntu user forcibly set to '$PASSWORD' in VM image."
