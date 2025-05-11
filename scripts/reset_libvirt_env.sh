#!/bin/bash
# reset_libvirt_env.sh - Remove all libvirt VMs, storage pools, and networks, then recreate the environment and restart services
# WARNING: This script will irreversibly delete all VMs and related resources managed by libvirt!

set -e

LOG=/tmp/reset_libvirt_env.log

function log() {
    echo "[$(date)] $1" | tee -a "$LOG"
}

log "Shutting down all running VMs..."
for vm in $(virsh list --name); do
    log "Shutting down $vm..."
    virsh destroy "$vm"
done

log "Undefining all VMs..."
for vm in $(virsh list --all --name); do
    log "Checking for snapshots for $vm..."
    SNAPSHOTS=$(virsh snapshot-list --name "$vm")
    for snap in $SNAPSHOTS; do
        if [ -n "$snap" ] && [ "$snap" != "-" ]; then
            log "Deleting snapshot $snap for $vm..."
            virsh snapshot-delete "$vm" --snapshotname "$snap" || log "Warning: failed to delete snapshot $snap for $vm"
        fi
    done
    log "Undefining $vm..."
    virsh undefine "$vm" || log "Warning: failed to undefine $vm (może są snapshoty?)"
    # Jeśli nadal nie można usunąć, spróbuj --remove-all-storage
    if virsh domuuid "$vm" &>/dev/null; then
        log "Ponowna próba z --remove-all-storage dla $vm..."
        virsh undefine --remove-all-storage "$vm" || log "Warning: failed to undefine $vm z --remove-all-storage"
    fi
    # Usuwanie orphaned cloud-init ISO dla tej VM
    ISO_PATH="/var/lib/safetytwin/cloud-init/${vm}-cloud-init.iso"
    if [ -f "$ISO_PATH" ]; then
        log "Removing orphaned ISO: $ISO_PATH"
        rm -f "$ISO_PATH" || log "Warning: failed to remove $ISO_PATH"
    fi
    # Usuwanie orphaned .lck i .qcow2 jeśli VM nie istnieje
    QCOW_PATH="/var/lib/safetytwin/images/${vm}.qcow2"
    LCK_PATH="/var/lib/safetytwin/images/${vm}.qcow2.lck"
    if ! virsh list --all --name | grep -q "^$vm$"; then
        if [ -f "$QCOW_PATH" ]; then
            log "Removing orphaned disk: $QCOW_PATH"
            rm -f "$QCOW_PATH" || log "Warning: failed to remove $QCOW_PATH"
        fi
        if [ -f "$LCK_PATH" ]; then
            log "Removing orphaned lock: $LCK_PATH"
            rm -f "$LCK_PATH" || log "Warning: failed to remove $LCK_PATH"
        fi
    fi

done

# Dodatkowe czyszczenie orphaned ISO (pozostałe)
for iso in /var/lib/safetytwin/cloud-init/*.iso; do
    if [ -f "$iso" ]; then
        log "Removing orphaned ISO: $iso"
        rm -f "$iso" || log "Warning: failed to remove $iso"
    fi

done

# Naprawa uprawnień do katalogów cloud-init i images
if [ -d "/var/lib/safetytwin/cloud-init" ]; then
    sudo chown -R $(whoami):$(whoami) /var/lib/safetytwin/cloud-init 2>/dev/null || log "Warning: failed to chown cloud-init"
    sudo chmod -R u+rwX /var/lib/safetytwin/cloud-init 2>/dev/null || log "Warning: failed to chmod cloud-init"
fi
if [ -d "/var/lib/safetytwin/images" ]; then
    sudo chown -R $(whoami):$(whoami) /var/lib/safetytwin/images 2>/dev/null || log "Warning: failed to chown images"
    sudo chmod -R u+rwX /var/lib/safetytwin/images 2>/dev/null || log "Warning: failed to chmod images"
fi

log "Removing all storage pools..."
for pool in $(virsh pool-list --all --name); do
    log "Destroying pool $pool..."
    virsh pool-destroy "$pool" || true
    log "Undefining pool $pool..."
    virsh pool-undefine "$pool" || true
done

log "Removing all networks..."
for net in $(virsh net-list --all --name); do
    log "Destroying network $net..."
    virsh net-destroy "$net" || true
    log "Undefining network $net..."
    virsh net-undefine "$net" || true
done

log "Environment cleaned. Recreating default network and pool..."
virsh net-define /usr/share/libvirt/networks/default.xml || true
virsh net-autostart default || true
virsh net-start default || true
virsh pool-define-as default dir - - - - /var/lib/libvirt/images || true
virsh pool-autostart default || true
virsh pool-start default || true

log "Recreating SafetyTwin environment (VMs, etc)..."
bash $HOME/safetytwin/safetytwin/scripts/create-vm.sh | tee -a "$LOG"

log "Restarting orchestrator and agent services..."
sudo systemctl restart orchestrator.service
sudo systemctl restart agent_send_state.service

log "Environment reset and services restarted."
