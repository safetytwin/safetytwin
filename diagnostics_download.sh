#!/bin/bash
# diagnostics_download.sh - Run diagnostics on SafetyTwin VM and download logs
# Author: Tom Sapletta
# Last updated: 2025-05-11
#
# Purpose:
#   This script automates the process of copying diagnostics.sh to a VM, executing it, and downloading the resulting log file to the host for review.
#
# Usage:
#   sudo bash diagnostics_download.sh [VM_NAME]
#
# What it does:
#   - Starts the VM if needed and finds its IP address
#   - Copies diagnostics.sh to the VM
#   - Executes diagnostics.sh remotely (as root)
#   - Downloads the latest diagnostics log to a local directory
#   - Informs the user of log location and how to view condensed results
#
# This script should be run on the host/controller. It requires sshpass, scp, and virsh.
#
# Contact: tom@sapletta.com

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
VM_NAME="${1:-safetytwin-vm}"
VM_USER="ubuntu"
VM_PASS="ubuntu"
LOCAL_LOG_DIR="./vm_logs_$(date +%Y%m%d_%H%M%S)"
REMOTE_DIAGNOSTIC_SCRIPT="/tmp/diagnostics.sh"
REMOTE_LOG_PATTERN="/tmp/*.log"
TIMEOUT_SECONDS=300  # 5 minutes max wait time

# Functions
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
for cmd in virsh sshpass ssh scp; do
    if ! command -v $cmd &> /dev/null; then
        log_error "Command '$cmd' not found. Please install it and try again."
        case $cmd in
            sshpass) echo "  Install with: sudo apt-get install sshpass" ;;
            virsh) echo "  Install with: sudo apt-get install libvirt-clients" ;;
            ssh|scp) echo "  Install with: sudo apt-get install openssh-client" ;;
        esac
        exit 1
    fi
done

# Create local directory for logs
mkdir -p "$LOCAL_LOG_DIR"
log "Created local directory for logs: $LOCAL_LOG_DIR"

# Check VM status
log "Checking VM status..."
if ! virsh dominfo "$VM_NAME" &>/dev/null; then
    log_error "VM '$VM_NAME' does not exist. Please create it first."
    exit 1
fi

# Start VM if not running
if ! virsh list | grep -q "$VM_NAME"; then
    log "VM is not running. Starting it now..."
    virsh start "$VM_NAME"
    if [ $? -ne 0 ]; then
        log_error "Failed to start VM '$VM_NAME'. Check virsh error message."
        exit 1
    fi
    log_success "VM '$VM_NAME' started successfully"
    log "Waiting 30 seconds for boot sequence..."
    sleep 30
else
    log_success "VM '$VM_NAME' is already running"
fi

# Get VM IP address
log "Getting VM IP address..."
VM_IP=""
start_time=$(date +%s)
while [ -z "$VM_IP" ]; do
    VM_IP=$(virsh domifaddr "$VM_NAME" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    if [ -n "$VM_IP" ]; then
        log_success "Found VM IP address: $VM_IP"
        break
    fi

    # Check timeout
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    if [ $elapsed -gt $TIMEOUT_SECONDS ]; then
        log_error "Timeout waiting for VM to get IP address."
        log "Try accessing the VM console: sudo virsh console $VM_NAME"
        exit 1
    fi

    log "Waiting for VM IP address... ($elapsed seconds elapsed)"
    sleep 5
done

# Wait for SSH to be ready
log "Waiting for SSH service to be ready..."
start_time=$(date +%s)
ssh_ready=false
while [ "$ssh_ready" = false ]; do
    if sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$VM_USER@$VM_IP" "echo SSH is ready" &>/dev/null; then
        log_success "SSH connection successful"
        ssh_ready=true
    else
        # Check timeout
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        if [ $elapsed -gt $TIMEOUT_SECONDS ]; then
            log_error "Timeout waiting for SSH to be ready."
            log "Try accessing the VM console: sudo virsh console $VM_NAME"
            exit 1
        fi

        log "Waiting for SSH to be ready... ($elapsed seconds elapsed)"
        sleep 5
    fi
done

# Ensure diagnostics.sh exists locally and copy it to the VM
if [ ! -f "./diagnostics.sh" ]; then
    log_error "Local diagnostics script ./diagnostics.sh not found! Please provide it."
    exit 1
fi

# Copy diagnostics.sh to the VM
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no "./diagnostics.sh" "$VM_USER@$VM_IP:$REMOTE_DIAGNOSTIC_SCRIPT"

# Execute diagnostics.sh remotely
sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "sudo bash $REMOTE_DIAGNOSTIC_SCRIPT"

# Find the latest diagnostics log file on the VM
LATEST_LOG=$(sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "ls -1t /tmp/diagnostics_*.log | head -n1")
if [ -n "$LATEST_LOG" ]; then
    # Download it to your local log directory
    sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no "$VM_USER@$VM_IP:$LATEST_LOG" "$LOCAL_LOG_DIR/"
    log_success "Downloaded diagnostics log to $LOCAL_LOG_DIR/"
    echo "[INFO] To view condensed results: grep -E '\[ERROR\]|\[WARNING\]|\[OK\]' $LOCAL_LOG_DIR/$(basename $LATEST_LOG)"
else
    log_warning "No diagnostics log found on the VM."
fi
  echo -e "\nDisk I/O Stats:"
  iostat 2>/dev/null || echo "iostat not available"
  echo -e "\nVMStat:"
  vmstat 2>/dev/null || echo "vmstat not available"
) | tee "$PERFORMANCE_LOG"
echo "Full performance information saved to $PERFORMANCE_LOG"
separator

# Extract relevant system logs
echo -e "${BLUE}System Logs:${NC}"
(
  echo "=== SYSTEM LOGS EXTRACT ==="
  echo "Date: $(date)"
  echo -e "\nJournal Logs (Last 100 lines):"
  journalctl -n 100 --no-pager
  echo -e "\nJournal Errors:"
  journalctl -p err --no-pager | tail -100
  echo -e "\nSyslog Entries (Last 100 lines):"
  tail -100 /var/log/syslog 2>/dev/null || echo "No syslog file found"
  echo -e "\nDmesg Output:"
  dmesg | tail -100
  echo -e "\nBoot Log:"
  journalctl -b --no-pager | head -100
  echo -e "\nCloud-Init Log (Last 100 lines):"
  tail -100 /var/log/cloud-init.log 2>/dev/null || echo "No cloud-init.log found"
  echo -e "\nCloud-Init Output Log (Last 100 lines):"
  tail -100 /var/log/cloud-init-output.log 2>/dev/null || echo "No cloud-init-output.log found"
  echo -e "\nAuth Log (Last 50 lines):"
  tail -50 /var/log/auth.log 2>/dev/null || echo "No auth.log found"
) | tee "$SYSLOG_EXTRACT"
echo "System logs saved to $SYSLOG_EXTRACT"

# Save full dmesg output to a separate file
dmesg > "$DMESG_LOG"
echo "Full dmesg output saved to $DMESG_LOG"
separator

echo -e "${BLUE}============ END OF REPORT ============${NC}"
echo "Main report saved to: $REPORT_FILE"
echo "All diagnostic files are in /tmp/ with timestamp $TIMESTAMP"

# List all created log files
echo -e "\nCreated log files:"
ls -la /tmp/*_$TIMESTAMP.log
EOF

# Copy the diagnostics script to the VM
log "Transferring diagnostics script to VM..."
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 /tmp/diagnostics.sh "$VM_USER@$VM_IP:$REMOTE_DIAGNOSTIC_SCRIPT" || {
    log_error "Failed to copy diagnostics script to VM."
    exit 1
}
log_success "Diagnostics script transferred successfully"

# Run the diagnostics script on the VM
log "Running diagnostics script on VM..."
sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "sudo bash $REMOTE_DIAGNOSTIC_SCRIPT" || {
    log_error "Failed to run diagnostics script on VM."
    exit 1
}
log_success "Diagnostics script executed successfully"

# Download log files from the VM
log "Downloading log files from VM..."
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no "$VM_USER@$VM_IP:$REMOTE_LOG_PATTERN" "$LOCAL_LOG_DIR/" || {
    log_warning "Failed to download some log files from VM."
}
log_success "Log files downloaded to $LOCAL_LOG_DIR"

# Generate summary
log "Generating summary report..."
echo "============ VM Diagnostics Summary ============" > "$LOCAL_LOG_DIR/summary.txt"
echo "Date: $(date)" >> "$LOCAL_LOG_DIR/summary.txt"
echo "VM Name: $VM_NAME" >> "$LOCAL_LOG_DIR/summary.txt"
echo "VM IP: $VM_IP" >> "$LOCAL_LOG_DIR/summary.txt"
echo "" >> "$LOCAL_LOG_DIR/summary.txt"
echo "Log Files:" >> "$LOCAL_LOG_DIR/summary.txt"
ls -la "$LOCAL_LOG_DIR" | grep -v summary.txt >> "$LOCAL_LOG_DIR/summary.txt"
echo "" >> "$LOCAL_LOG_DIR/summary.txt"
echo "Quick Results:" >> "$LOCAL_LOG_DIR/summary.txt"
grep -E '\[OK\]|\[ERROR\]|\[WARNING\]' "$LOCAL_LOG_DIR"/*.log 2>/dev/null | sort >> "$LOCAL_LOG_DIR/summary.txt"

# Final output
log_success "VM diagnostics completed successfully!"
log "All log files have been saved to: $LOCAL_LOG_DIR"
log "Summary report: $LOCAL_LOG_DIR/summary.txt"
log "To connect to the VM: ssh $VM_USER@$VM_IP (password: $VM_PASS)"