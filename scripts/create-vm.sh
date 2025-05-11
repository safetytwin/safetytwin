#!/bin/bash
# Automated multi-VM creation with snapshotting and health checks
#
# [Permission Fix]
# If you get 'Permission denied' errors, run:
#   sudo chown -R $USER:$USER /var/lib/safetytwin/images /var/lib/safetytwin/cloud-init
#   sudo rm -f /tmp/create-vm.log
# This ensures you can create images and log files as your user.
set -e

# === CONFIGURATION ===
VM_NAMES=("safetytwin-vm" "safetytwin-vm-2" "basic-test-vm")

# === IMAGE OPTIONS ===
IMAGES=(
    "Ubuntu 24.04 Server Cloud Image|ubuntu|ubuntu|https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
    "Ubuntu 22.04 Server Cloud Image|ubuntu|ubuntu|https://cloud-images.ubuntu.com/releases/jammy/release/20250508/ubuntu-22.04-server-cloudimg-amd64.img"
    "Ubuntu 22.04 Minimal Cloud Image|ubuntu|ubuntu|https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img"
    "Ubuntu 20.04 Server Cloud Image|ubuntu|ubuntu|https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img"
    "Debian 12 Bookworm Cloud Image|debian|debian|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    "Debian 11 Bullseye Cloud Image|debian|debian|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
    "CentOS 9 Stream Cloud Image|centos|centos|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
    "Rocky Linux 9 Cloud Image|rocky|rocky|https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
    "Rocky Linux 8 Cloud Image|rocky|rocky|https://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud.latest.x86_64.qcow2"
    "AlmaLinux 9 Cloud Image|almalinux|almalinux|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
    "AlmaLinux 8 Cloud Image|almalinux|almalinux|https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2"
    "Fedora 40 Cloud Image|fedora|fedora|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2"
    "Fedora 39 Cloud Image|fedora|fedora|https://download.fedoraproject.org/pub/fedora/linux/releases/39/Cloud/x86_64/images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2"
    "openSUSE Leap 15.5 Cloud Image|opensuse|opensuse|https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.5/images/openSUSE-Leap-15.5.x86_64-NoCloud.qcow2"
    "Oracle Linux 9 Cloud Image|oracle|oracle|https://yum.oracle.com/ol9/cloud/x86_64/oraclelinux-9-cloud-latest.x86_64.qcow2"
    "Oracle Linux 8 Cloud Image|oracle|oracle|https://yum.oracle.com/ol8/cloud/x86_64/oraclelinux-8-cloud-latest.x86_64.qcow2"
    "Arch Linux Cloud Image|arch|arch|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
)

ENV_FILE="$(dirname "$0")/../.env"

# Load from .env if present
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# Prompt for image/user/pass if not set
if [ -z "$BASE_IMAGE_URL" ] || [ -z "$VM_USER" ] || [ -z "$VM_PASS" ]; then
    echo "Wybierz obraz bazowy VM (podaj numer):"
    for i in "${!IMAGES[@]}"; do
        IFS='|' read -r NAME USER PASS URL <<< "${IMAGES[$i]}"
        echo "$((i+1)). $NAME (user: $USER, pass: $PASS)"
    done
    read -rp "Numer obrazu [1-${#IMAGES[@]}]: " IMG_NUM
    IMG_IDX=$((IMG_NUM-1))
    IFS='|' read -r IMG_NAME VM_USER VM_PASS BASE_IMAGE_URL <<< "${IMAGES[$IMG_IDX]}"
    echo "Wybrano: $IMG_NAME"
    # Aktualizacja .env
    grep -vE '^(BASE_IMAGE_URL|VM_USER|VM_PASS|BASE_IMAGE_PATH)=' "$ENV_FILE" 2>/dev/null > "$ENV_FILE.tmp" || true
    echo "BASE_IMAGE_URL=\"$BASE_IMAGE_URL\"" >> "$ENV_FILE.tmp"
    echo "VM_USER=\"$VM_USER\"" >> "$ENV_FILE.tmp"
    echo "VM_PASS=\"$VM_PASS\"" >> "$ENV_FILE.tmp"
    BASE_IMAGE_PATH="/var/lib/safetytwin/images/$(basename "$BASE_IMAGE_URL")"
    echo "BASE_IMAGE_PATH=\"$BASE_IMAGE_PATH\"" >> "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
    source "$ENV_FILE"
fi

BASE_IMAGE_PATH="${BASE_IMAGE_PATH:-/var/lib/safetytwin/images/ubuntu-base.img}"
BASE_IMAGE="$BASE_IMAGE_PATH"
VM_IMAGE_DIR="/var/lib/safetytwin/images"
CLOUD_INIT_DIR="/var/lib/safetytwin/cloud-init"

# Pobierz obraz jeśli nie istnieje
if [ ! -f "$BASE_IMAGE_PATH" ]; then
    echo "Pobieram obraz bazowy: $BASE_IMAGE_URL ..."
    wget -O "$BASE_IMAGE_PATH" "$BASE_IMAGE_URL"
fi

VM_RAM=2048    # MB
VM_VCPUS=2
LOGFILE="/tmp/create-vm.log"

function log() {
    echo "[$(date)] $1" | tee -a "$LOGFILE"
}

log "Starting multi-VM creation..."

# Clean up old cloud-init ISOs and ensure directory exists
mkdir -p "$CLOUD_INIT_DIR"
rm -f "$CLOUD_INIT_DIR"/*.iso

for VM in "${VM_NAMES[@]}"; do
    VM_IMAGE="${VM_IMAGE_DIR}/${VM}.qcow2"
    CLOUD_INIT_ISO="$CLOUD_INIT_DIR/${VM}-cloud-init.iso"
    CLOUD_INIT_CFG="$CLOUD_INIT_DIR/${VM}-cloud-init.cfg"
    log "Creating cloud-init ISO for $VM..."
    # You may want to generate a proper cloud-init config here. For now, create a minimal one if missing.
    # Generate robust cloud-init config for DHCP and serial console
    cat > "$CLOUD_INIT_CFG" <<EOF
#cloud-config
hostname: $VM
manage_etc_hosts: true
users:
  - name: ${VM_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
    lock_passwd: false
    passwd: ${VM_PASS}
ssh_pwauth: true
chpasswd:
  list: |
    ${VM_USER}:${VM_PASS}
  expire: false
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp-identifier: mac
      renderer: networkd
bootcmd:
  - [ sh, -c, 'echo "ttyS0" >> /etc/securetty' ]
runcmd:
  - systemctl enable serial-getty@ttyS0.service
  - netplan generate
  - netplan apply
  - ip a > /dev/ttyS0
  - dmesg > /dev/ttyS0
  - cat /etc/netplan/*.yaml > /dev/ttyS0
EOF
    cloud-localds "$CLOUD_INIT_ISO" "$CLOUD_INIT_CFG"
    if [ $? -ne 0 ] || [ ! -f "$CLOUD_INIT_ISO" ]; then
        log "ERROR: Nie udało się utworzyć ISO cloud-init dla $VM ($CLOUD_INIT_ISO)!"
        continue
    fi
    log "Creating image for $VM..."
    if [ ! -f "$BASE_IMAGE" ]; then
        log "ERROR: Base image $BASE_IMAGE not found. Aborting."
        exit 1
    fi
    if [[ "$BASE_IMAGE" == "$VM_IMAGE" ]]; then
        log "ERROR: Base image and VM image paths are identical! Skipping $VM."
        continue
    fi
    qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$VM_IMAGE" 20G
    if [ $? -ne 0 ] || [ ! -f "$VM_IMAGE" ]; then
        log "ERROR: Nie udało się utworzyć obrazu $VM_IMAGE!"
        continue
    fi

    log "Defining and starting $VM..."
    virt-install --name "$VM" \
        --ram $VM_RAM --vcpus $VM_VCPUS \
        --disk path="$VM_IMAGE",format=qcow2 \
        --disk path="$CLOUD_INIT_ISO",device=cdrom \
        --os-type linux --os-variant ubuntu22.04 \
        --network network=default \
        --graphics none --noautoconsole \
        --console pty,target_type=serial --serial pty \
        --import 2>&1 | tee -a "$LOGFILE"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log "ERROR: virt-install failed for $VM. Skipping. Sprawdzam logi QEMU..."
        QEMU_LOG="/var/log/libvirt/qemu/${VM}.log"
        if [ -f "$QEMU_LOG" ]; then
            log "--- QEMU log for $VM ---"
            tail -n 40 "$QEMU_LOG" | tee -a "$LOGFILE"
            log "--- END QEMU log ---"
        else
            log "Brak logu QEMU dla $VM ($QEMU_LOG)"
        fi
        continue
    fi

    log "Waiting for $VM to appear in virsh list..."
    sleep 10

    # Optional: Create initial snapshot
    log "Creating initial snapshot for $VM..."
    virsh snapshot-create-as "$VM" "init-snap" "Initial snapshot" --atomic || log "Warning: snapshot failed for $VM"

    # Health check: Is VM running?
    STATE=$(virsh domstate "$VM")
    if [[ "$STATE" == "running" ]]; then
        log "$VM is running."
    else
        log "Error: $VM is not running!"
    fi

done

log "All VMs created and checked."
