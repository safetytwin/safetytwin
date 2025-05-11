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
BASE_IMAGE="/var/lib/safetytwin/images/ubuntu-base.img"
VM_IMAGE_DIR="/var/lib/safetytwin/images"
# Each VM will get its own cloud-init ISO
CLOUD_INIT_DIR="/var/lib/safetytwin/cloud-init"

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
    if [ ! -f "$CLOUD_INIT_CFG" ]; then
        echo "#cloud-config\nhostname: $VM" > "$CLOUD_INIT_CFG"
    fi
    cloud-localds "$CLOUD_INIT_ISO" "$CLOUD_INIT_CFG"
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

    log "Defining and starting $VM..."
    virt-install --name "$VM" \
        --ram $VM_RAM --vcpus $VM_VCPUS \
        --disk path="$VM_IMAGE",format=qcow2 \
        --disk path="$CLOUD_INIT_ISO",device=cdrom \
        --os-type linux --os-variant ubuntu22.04 \
        --network network=default \
        --graphics none --noautoconsole \
        --console pty,target_type=serial --serial pty \
        --import || {  # Add serial console for virsh console diagnostics
            log "ERROR: virt-install failed for $VM. Skipping."
            continue
        }

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
