#!/bin/bash
# ssh_vm_check.sh - Check SSH connectivity to all configured VMs and log errors
# Edit the VM_LIST as needed
VM_LIST=(safetytwin-vm-2 safetytwin-vm basic-test-vm)
LOGFILE="/tmp/ssh_vm_check.log"

for vm in "${VM_LIST[@]}"; do
    echo "Checking SSH for $vm..." >> "$LOGFILE"
    timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 "$vm" exit
    STATUS=$?
    if [ $STATUS -eq 0 ]; then
        echo "[$(date)] $vm: SSH OK" >> "$LOGFILE"
    else
        echo "[$(date)] $vm: SSH FAILED (exit $STATUS)" >> "$LOGFILE"
    fi
done
