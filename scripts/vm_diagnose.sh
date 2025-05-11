#!/bin/bash
# Diagnose all libvirt VMs: show state, IP, SSH, and fetch cloud-init/system logs

LOGDIR="/tmp/vm_diagnose_logs"
mkdir -p "$LOGDIR"

VM_LIST=$(virsh list --all --name | grep -v '^$')

for VM in $VM_LIST; do
    echo "==== Diagnosing $VM ====" | tee "$LOGDIR/$VM.log"
    echo "[1] State:" | tee -a "$LOGDIR/$VM.log"
    virsh domstate "$VM" | tee -a "$LOGDIR/$VM.log"

    echo "[2] Network Interfaces:" | tee -a "$LOGDIR/$VM.log"
    virsh domiflist "$VM" | tee -a "$LOGDIR/$VM.log"

    echo "[3] IP Addresses:" | tee -a "$LOGDIR/$VM.log"
    virsh domifaddr "$VM" | tee -a "$LOGDIR/$VM.log"

    # Try SSH if IP is available
    IP=$(virsh domifaddr "$VM" | awk '/ipv4/ {print $4}' | cut -d'/' -f1 | head -n1)
    if [[ -n "$IP" ]]; then
        echo "[4] SSH test (user: ubuntu)..." | tee -a "$LOGDIR/$VM.log"
        ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$IP" 'echo "SSH OK"; sudo journalctl -b --no-pager | tail -n 40' 2>&1 | tee -a "$LOGDIR/$VM.log"
    else
        echo "[4] SSH test skipped: no IP found." | tee -a "$LOGDIR/$VM.log"
    fi

    echo "[5] Cloud-init log (if accessible via console):" | tee -a "$LOGDIR/$VM.log"
    virsh console "$VM" --safe --devname console --force 2>&1 | head -n 40 | tee -a "$LOGDIR/$VM.log"
    echo -e "\n==== End of $VM ====" | tee -a "$LOGDIR/$VM.log"
done

echo "Diagnosis complete. Logs in $LOGDIR."
