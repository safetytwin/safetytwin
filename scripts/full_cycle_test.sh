#!/bin/bash
# Full cycle test: install, diagnose, shutdown, reset, recreate, diagnose again
# For rapid validation and debugging of the whole SafetyTwin stack

set -e
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGDIR="/tmp/full_cycle_test_logs"
mkdir -p "$LOGDIR"

log() {
    echo "[$(date)] $1" | tee -a "$LOGDIR/full_cycle_test.log"
}

log "[1] Running install.sh (clean setup)"
sudo "$PROJECT_ROOT/install.sh" | tee -a "$LOGDIR/install.log"

log "[2] Diagnosing all VMs after install"
if [ -f "$PROJECT_ROOT/scripts/vm_diagnose.sh" ]; then
    bash "$PROJECT_ROOT/scripts/vm_diagnose.sh" | tee -a "$LOGDIR/diagnose_after_install.log"
else
    echo "[ERROR] vm_diagnose.sh not found!" | tee -a "$LOGDIR/diagnose_after_install.log"
fi

log "[3] Shutting down all VMs"
for VM in $(virsh list --all --name | grep -v '^$'); do
    log "Shutting down $VM..."
    virsh destroy "$VM" || true
done

log "[4] Starting all VMs again"
for VM in $(virsh list --all --name | grep -v '^$'); do
    log "Starting $VM..."
    virsh start "$VM" || true
done

log "[5] Diagnosing all VMs after restart"
if [ -f "$PROJECT_ROOT/scripts/vm_diagnose.sh" ]; then
    bash "$PROJECT_ROOT/scripts/vm_diagnose.sh" | tee -a "$LOGDIR/diagnose_after_restart.log"
else
    echo "[ERROR] vm_diagnose.sh not found!" | tee -a "$LOGDIR/diagnose_after_restart.log"
fi

log "[6] Running full environment reset (reset_libvirt_env.sh)"
if [ -f "$PROJECT_ROOT/scripts/reset_libvirt_env.sh" ]; then
    bash "$PROJECT_ROOT/scripts/reset_libvirt_env.sh" | tee -a "$LOGDIR/reset_env.log"
else
    echo "[ERROR] reset_libvirt_env.sh not found!" | tee -a "$LOGDIR/reset_env.log"
fi

log "[7] Diagnosing all VMs after full reset/recreate"
if [ -f "$PROJECT_ROOT/scripts/vm_diagnose.sh" ]; then
    bash "$PROJECT_ROOT/scripts/vm_diagnose.sh" | tee -a "$LOGDIR/diagnose_after_reset.log"
else
    echo "[ERROR] vm_diagnose.sh not found!" | tee -a "$LOGDIR/diagnose_after_reset.log"
fi

log "Full cycle test complete. All logs in $LOGDIR."
