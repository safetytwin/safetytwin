#!/bin/bash
# Automated multi-VM creation with snapshotting and health checks
set -e

# === CONFIGURATION ===
VM_NAMES=("safetytwin-vm" "safetytwin-vm-2" "basic-test-vm")
BASE_IMAGE="/var/lib/safetytwin/images/ubuntu-base.img"
VM_IMAGE_DIR="/var/lib/safetytwin/images"
CLOUD_INIT_ISO="/var/lib/safetytwin/cloud-init/cloud-init.iso"
VM_RAM=2048    # MB
VM_VCPUS=2
LOGFILE="/tmp/create-vm.log"

function log() {
    echo "[$(date)] $1" | tee -a "$LOGFILE"
}

log "Starting multi-VM creation..."

for VM in "${VM_NAMES[@]}"; do
    VM_IMAGE="${VM_IMAGE_DIR}/${VM}.qcow2"
    log "Creating image for $VM..."
    if [ ! -f "$BASE_IMAGE" ]; then
        log "ERROR: Base image $BASE_IMAGE not found. Aborting."
        exit 1
    fi
    qemu-img create -f qcow2 -b "$BASE_IMAGE" "$VM_IMAGE" 20G

    log "Defining and starting $VM..."
    virt-install --name "$VM" \
        --ram $VM_RAM --vcpus $VM_VCPUS \
        --disk path="$VM_IMAGE",format=qcow2 \
        --disk path="$CLOUD_INIT_ISO",device=cdrom \
        --os-type linux --os-variant ubuntu22.04 \
        --network network=default \
        --graphics none --noautoconsole --import || {
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
