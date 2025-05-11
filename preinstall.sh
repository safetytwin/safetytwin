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
INSTALL_PACKAGES="qemu-guest-agent openssh-server python3 net-tools iproute2 vim htop"

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

# Create a copy for our VM and ensure proper format
log "Creating VM disk image ($VM_DISK_SIZE)..."
# Convert to qcow2 format explicitly to ensure proper format
qemu-img convert -f qcow2 -O qcow2 "$UBUNTU_IMAGE" "$VM_IMAGE"
qemu-img resize "$VM_IMAGE" "$VM_DISK_SIZE"

# Create cloud-init files with enhanced filesystem configuration
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

# Filesystem configuration to prevent corruption
bootcmd:
  - echo 'GRUB_CMDLINE_LINUX="consoleblank=0 panic=5 fsck.repair=yes"' >> /etc/default/grub
  - update-grub

# Network configuration
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true
    ens3:
      dhcp4: true
    eth0:
      dhcp4: true

# Package management
package_update: true
package_upgrade: true
packages:
$(for pkg in $INSTALL_PACKAGES; do echo "  - $pkg"; done)

# System performance and stability
write_files:
  - path: /etc/sysctl.d/60-vm-performance.conf
    content: |
      # VM Performance optimizations
      vm.swappiness = 10
      fs.file-max = 2097152
      vm.dirty_ratio = 60
      vm.dirty_background_ratio = 2
    permissions: '0644'

# Final commands
runcmd:
  - echo '$USERNAME:$PASSWORD' | chpasswd
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  - systemctl restart ssh
  - sysctl -p /etc/sysctl.d/60-vm-performance.conf
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "# Filesystem check settings" >> /etc/default/rcS
  - echo "FSCKFIX=yes" >> /etc/default/rcS
  - touch /home/$USERNAME/.hushlogin
  - chown $USERNAME:$USERNAME /home/$USERNAME/.hushlogin
  # Test write access
  - mkdir -p /opt/testdir
  - touch /opt/testdir/test-write-access
  - echo "This file confirms write access is working properly at VM creation time" > /opt/testdir/test-write-access
  - chmod 777 /opt/testdir/test-write-access
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

# Make sure default network is active
log "Checking libvirt default network..."
if ! virsh net-list --all | grep -q "default"; then
    log_warning "Default network not found. Creating..."
    virsh net-define /usr/share/libvirt/networks/default.xml
    virsh net-autostart default
fi

if ! virsh net-list | grep -q "default"; then
    log_warning "Default network not active. Starting..."
    virsh net-start default
fi

# Create and start the VM with optimized disk settings
log "Creating and starting VM '$VM_NAME'..."
virt-install --name "$VM_NAME" \
  --memory "$VM_MEMORY" \
  --vcpus "$VM_CPUS" \
  --disk "$VM_IMAGE",device=disk,format=qcow2,bus=virtio,cache=none,io=native \
  --disk "$ISO",device=cdrom,bus=sata \
  --os-variant ubuntu22.04 \
  --virt-type kvm \
  --network network=default,model=virtio \
  --graphics none \
  --features kvm_hidden=on \
  --import \
  --noautoconsole

log "VM creation initiated. Waiting for boot process..."

# Wait for VM to get IP address
log "Waiting for VM to obtain an IP address (this may take a minute or two)..."
VM_IP=""
MAX_ATTEMPTS=18  # 18 x 10 seconds = 3 minutes (increased for more reliable boot)
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
    log_error "Could not obtain IP address after 3 minutes."
    log "You can try to access the VM console: sudo virsh console $VM_NAME"
    exit 1
fi

# Test SSH connectivity
log "Testing SSH connectivity to $VM_IP..."
MAX_SSH_ATTEMPTS=9  # 9 x 10 seconds = 1.5 minutes (increased)
for i in $(seq 1 $MAX_SSH_ATTEMPTS); do
    log "SSH test attempt $i/$MAX_SSH_ATTEMPTS..."
    if nc -z -w 5 "$VM_IP" 22 &>/dev/null; then
        log_success "SSH port is open! Waiting additional time for SSH to be fully ready..."
        sleep 15  # Increased wait time
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
if [ -n "$HOME" ] && [ -d "$HOME" ]; then
    # Create .ssh directory if it doesn't exist
    if [ ! -d "$HOME/.ssh" ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi

    if [ -w "$HOME/.ssh" ] || [ -w "$HOME" ]; then
        log "Creating SSH config entry for easy access..."

        # Create config file if it doesn't exist
        if [ ! -f "$SSH_CONFIG_FILE" ]; then
            touch "$SSH_CONFIG_FILE"
            chmod 600 "$SSH_CONFIG_FILE"
        fi

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
else
    log_warning "No HOME directory detected. SSH config not updated."
fi

# Create diagnostics script
log "Creating VM diagnostics script..."
cat > /tmp/diagnostics.sh << 'EOF'
#!/bin/bash
# VM Diagnostics Script - Verify VM configuration
# Run with: sudo bash diagnostics.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
separator() { echo "----------------------------------------"; }

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root.${NC}"
    echo "Please re-run as: sudo $(basename $0)"
    exit 1
fi

# Save output to file
REPORT_FILE="/tmp/diagnostics_report.txt"
exec > >(tee $REPORT_FILE) 2>&1

echo -e "${BLUE}============ VM DIAGNOSTIC REPORT ============${NC}"
echo "Date: $(date)"
echo "Hostname: $(hostname)"
separator

# System info
echo -e "${BLUE}System Information:${NC}"
echo "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "CPU: $(nproc) cores"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "Disk: $(df -h / | awk 'NR==2 {print $2}')"
separator

# Check filesystem
echo -e "${BLUE}Filesystem Status:${NC}"
mount | grep " / " | grep -v "rootfs"
if mount | grep " / " | grep -q "ro"; then
    log_error "Root filesystem is mounted READ-ONLY!"
else
    log_success "Root filesystem is mounted read-write."
fi

# Test write access
echo -e "${BLUE}Write Access Test:${NC}"
TEST_FILE="/tmp/write-test-$(date +%s).txt"
if echo "Test data" > $TEST_FILE 2>/dev/null; then
    log_success "Successfully wrote to $TEST_FILE"
    rm $TEST_FILE
else
    log_error "Failed to write to filesystem!"
fi

# Check for write access test file from cloud-init
if [ -f /opt/testdir/test-write-access ]; then
    log_success "Found write access test file from VM initialization"
    cat /opt/testdir/test-write-access
else
    log_warning "Could not find write access test file from VM initialization"
fi
separator

# Check network
echo -e "${BLUE}Network:${NC}"
echo "IP Addresses:"
hostname -I
echo "Network Interfaces:"
ip -br a
echo "Default Route:"
ip route | grep default || echo "No default route!"
separator

# Check services
echo -e "${BLUE}Services:${NC}"
echo "SSH Status:"
systemctl status ssh | grep Active || echo "SSH service not found!"
echo "QEMU Guest Agent Status:"
systemctl status qemu-guest-agent | grep Active || echo "QEMU Guest Agent not found!"
separator

# Performance test
echo -e "${BLUE}Performance Test:${NC}"
echo "Disk Write Speed:"
dd if=/dev/zero of=/tmp/testfile bs=1M count=100 conv=fdatasync 2>&1 | grep copied
rm -f /tmp/testfile
separator

echo -e "${BLUE}============ END OF REPORT ============${NC}"
echo "Report saved to: $REPORT_FILE"
EOF

# Try to copy diagnostics script to VM
if [ -n "$VM_IP" ]; then
    log "Attempting to copy diagnostics script to VM..."
    # Install sshpass if needed and available
    if ! command -v sshpass >/dev/null; then
        if command -v apt-get >/dev/null; then
            log "Installing sshpass for automated script transfer..."
            apt-get update -qq && apt-get install -qq -y sshpass >/dev/null
        fi
    fi

    # Wait a bit more for SSH to be fully available
    sleep 10

    # Copy the script using sshpass if available
    if command -v sshpass >/dev/null; then
        sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 /tmp/diagnostics.sh "$USERNAME@$VM_IP:~/" && {
            log_success "Diagnostics script copied to VM successfully"
            log "To run diagnostics: ssh $USERNAME@$VM_IP 'sudo bash ~/diagnostics.sh'"
        } || {
            log_warning "Could not copy diagnostics script via SCP"
            log "To manually copy: scp /tmp/diagnostics.sh $USERNAME@$VM_IP:~/"
        }
    else
        log "sshpass not available. To copy diagnostics script manually:"
        log "scp /tmp/diagnostics.sh $USERNAME@$VM_IP:~/"
    fi
fi

# Done
log_success "VM '$VM_NAME' created successfully!"
log_success "IP Address: $VM_IP"
log_success "SSH Access: ssh $USERNAME@$VM_IP (password: $PASSWORD)"
if [ -f "$SSH_CONFIG_FILE" ] && grep -q "$VM_NAME" "$SSH_CONFIG_FILE" 2>/dev/null; then
    log_success "           or simply: ssh $VM_NAME"
fi
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

echo "[preinstall.sh] Script completed. Quick steps:"
echo "1. SSH: ssh $USERNAME@$VM_IP (password: $PASSWORD)"
echo "2. Run diagnostics: sudo bash ~/diagnostics.sh"
echo "3. Console access if needed: sudo virsh console $VM_NAME"