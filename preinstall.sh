#!/bin/bash
# preinstall.sh - Minimal VM/cloud-init test for troubleshooting SSH and provisioning
# Author: Tom Sapletta
# Date: 2025-05-11
set -e

# Configuration variables
VM_NAME="${1:-safetytwin-vm}"
VM_MEMORY=2048
VM_CPUS=2
VM_DISK_SIZE=20G
USERNAME="ubuntu"
PASSWORD="ubuntu"
INSTALL_PACKAGES="qemu-guest-agent openssh-server python3 net-tools iproute2"

# Paths
WORK_DIR="/var/lib/safetytwin"
CLOUD_INIT_DIR="$WORK_DIR/cloud-init"
IMG_DIR="$WORK_DIR/images"
USER_DATA="$CLOUD_INIT_DIR/user-data"
META_DATA="$CLOUD_INIT_DIR/meta-data"
ISO="$CLOUD_INIT_DIR/cloud-init.iso"
VM_IMAGE="$IMG_DIR/$VM_NAME.qcow2"

# Functions
log() { echo -e "\033[1;34m[safetytwin_vm]\033[0m $1"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

# Create directories
log "Creating directories..."
mkdir -p "$CLOUD_INIT_DIR" "$IMG_DIR"

# Check for existing VM
if virsh dominfo "$VM_NAME" &>/dev/null; then
    log_warning "VM '$VM_NAME' already exists."
    read -p "Do you want to destroy and recreate it? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Destroying existing VM '$VM_NAME'..."
        virsh destroy "$VM_NAME" &>/dev/null || true
        virsh undefine "$VM_NAME" --remove-all-storage --nvram &>/dev/null || true
    else
        log "Exiting without changes."
        exit 0
    fi
fi

# Download Ubuntu cloud image if needed
UBUNTU_IMAGE="$IMG_DIR/jammy-server-cloudimg-amd64.img"
if [ ! -f "$UBUNTU_IMAGE" ]; then
    log "Downloading Ubuntu cloud image..."
    wget -O "$UBUNTU_IMAGE" "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
else
    log "Using existing Ubuntu cloud image at $UBUNTU_IMAGE"
fi

# Create a copy for our VM
log "Creating VM disk image ($VM_DISK_SIZE)..."
cp "$UBUNTU_IMAGE" "$VM_IMAGE"
qemu-img resize "$VM_IMAGE" "$VM_DISK_SIZE"

# Create cloud-init files
log "Creating cloud-init configuration..."
cat > "$USER_DATA" << EOF
#cloud-config
hostname: $VM_NAME
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: '$PASSWORD'
ssh_pwauth: true
disable_root: false

# Network configuration
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true

# Package management
package_update: true
package_upgrade: true
packages:
$(for pkg in $INSTALL_PACKAGES; do echo "  - $pkg"; done)

# Final commands
runcmd:
  - echo '$USERNAME:$PASSWORD' | chpasswd
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  - systemctl restart ssh
EOF

cat > "$META_DATA" << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Create cloud-init ISO
log "Creating cloud-init ISO..."
genisoimage -output "$ISO" -volid cidata -joliet -rock "$META_DATA" "$USER_DATA"
chmod 644 "$ISO"
chown libvirt-qemu:libvirt-qemu "$ISO" "$VM_IMAGE" 2>/dev/null || true

# Create and start the VM
log "Creating and starting VM '$VM_NAME'..."
virt-install --name "$VM_NAME" \
  --memory "$VM_MEMORY" \
  --vcpus "$VM_CPUS" \
  --disk "$VM_IMAGE",device=disk,format=qcow2 \
  --disk "$ISO",device=cdrom \
  --os-variant ubuntu22.04 \
  --virt-type kvm \
  --network default \
  --graphics none \
  --import \
  --noautoconsole

log "VM creation initiated. Waiting for boot process..."

# Wait for VM to get IP address
log "Waiting for VM to obtain an IP address (this may take a minute or two)..."
VM_IP=""
MAX_ATTEMPTS=12  # 12 x 10 seconds = 2 minutes
for i in $(seq 1 $MAX_ATTEMPTS); do
    log "Attempt $i/$MAX_ATTEMPTS: Checking for IP address..."
    VM_IP=$(virsh domifaddr "$VM_NAME" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -n "$VM_IP" ]; then
        log_success "VM has IP address: $VM_IP"
        break
    fi
    sleep 10
done

if [ -z "$VM_IP" ]; then
    log_error "Could not obtain IP address after 2 minutes."
    log "You can try to access the VM console: sudo virsh console $VM_NAME"
    exit 1
fi

# Test SSH connectivity
log "Testing SSH connectivity to $VM_IP..."
MAX_SSH_ATTEMPTS=6  # 6 x 10 seconds = 1 minute
for i in $(seq 1 $MAX_SSH_ATTEMPTS); do
    log "SSH test attempt $i/$MAX_SSH_ATTEMPTS..."
    if nc -z -w 5 "$VM_IP" 22 &>/dev/null; then
        log_success "SSH port is open! Waiting 10 more seconds for SSH to be fully ready..."
        sleep 10
        break
    fi

    if [ $i -eq $MAX_SSH_ATTEMPTS ]; then
        log_warning "SSH port is not responding after $MAX_SSH_ATTEMPTS attempts."
        log "You may need to wait longer or check the VM console: sudo virsh console $VM_NAME"
    else
        log "SSH not ready yet. Waiting 10 seconds..."
        sleep 10
    fi
done

# Create SSH config for easy access
SSH_CONFIG_FILE="$HOME/.ssh/config"
if [ -w "$HOME/.ssh" ]; then
    log "Creating SSH config entry for easy access..."

    # Check if entry already exists
    if grep -q "Host $VM_NAME" "$SSH_CONFIG_FILE" 2>/dev/null; then
        sed -i "/Host $VM_NAME/,/^\s*$/d" "$SSH_CONFIG_FILE"
    fi

    # Add new entry
    cat >> "$SSH_CONFIG_FILE" << EOF

Host $VM_NAME
    HostName $VM_IP
    User $USERNAME
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

    chmod 600 "$SSH_CONFIG_FILE"
    log_success "SSH config updated. You can now use: ssh $VM_NAME"
else
    log_warning "Cannot write to SSH config. Make sure ~/.ssh directory exists and is writable."
fi

# Done
log_success "VM '$VM_NAME' created successfully!"
log_success "IP Address: $VM_IP"
log_success "SSH Access: ssh $USERNAME@$VM_IP (password: $PASSWORD)"
log_success "           or simply: ssh $VM_NAME (if SSH config was updated)"
log "Console Access: sudo virsh console $VM_NAME"

# Save VM info to a file
cat > "$WORK_DIR/${VM_NAME}-info.txt" << EOF
VM Name: $VM_NAME
IP Address: $VM_IP
Username: $USERNAME
Password: $PASSWORD
SSH Command: ssh $USERNAME@$VM_IP
Alternative: ssh $VM_NAME
Console Access: sudo virsh console $VM_NAME
Created: $(date)
EOF

log "VM information saved to $WORK_DIR/${VM_NAME}-info.txt"


echo "[preinstall.sh] Script completed. Manual steps if needed:"
echo "1. Access console: sudo virsh console $VM_NAME"
echo "2. Login with: ubuntu / ubuntu"
echo "3. Check network: ip a"
echo "4. Force DHCP: sudo dhclient -v"
echo "5. Check SSH: systemctl status sshd"