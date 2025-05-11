#!/bin/bash
# vm_diagnostics_runner.sh - Start VM, run diagnostics, and download log files
# Author: Tom Sapletta
# Usage: bash vm_diagnostics_runner.sh [VM_NAME]

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
REMOTE_DIAGNOSTIC_SCRIPT="/tmp/vm_diagnostics.sh"
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

# Create VM diagnostics script
log "Creating VM diagnostics script..."
cat > /tmp/vm_diagnostics.sh << 'EOF'
#!/bin/bash
# VM Diagnostics Script - Verify VM configuration and create comprehensive logs
# Run with: sudo bash vm_diagnostics.sh

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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="/tmp/vm_diagnostics_report_$TIMESTAMP.log"
SYSTEM_LOG="/tmp/vm_system_info_$TIMESTAMP.log"
NETWORK_LOG="/tmp/vm_network_$TIMESTAMP.log"
DISK_LOG="/tmp/vm_disk_$TIMESTAMP.log"
SERVICE_LOG="/tmp/vm_services_$TIMESTAMP.log"
PERFORMANCE_LOG="/tmp/vm_performance_$TIMESTAMP.log"
SYSLOG_EXTRACT="/tmp/vm_syslog_extract_$TIMESTAMP.log"
DMESG_LOG="/tmp/vm_dmesg_$TIMESTAMP.log"

exec > >(tee $REPORT_FILE) 2>&1
  free -h
  echo -e "\nDisk Space:"
  df -h
  echo -e "\nMount Points:"
  mount | sort
  echo -e "\nFstab Configuration:"
  cat /etc/fstab
  echo -e "\nKernel Parameters:"
  sysctl -a 2>/dev/null | grep -E 'vm\.dirty|vm\.swappiness|fs\.'
  echo -e "\nRunning Processes (Top 10 by CPU):"
  ps aux --sort=-%cpu | head -11
  echo -e "\nRunning Processes (Top 10 by Memory):"
  ps aux --sort=-%mem | head -11
  echo -e "\nUser List:"
  cat /etc/passwd | grep -E '/home|/root' | cut -d: -f1
  echo -e "\nSudo Access:"
  grep -r "sudo" /etc/group /etc/sudoers.d 2>/dev/null
) | tee "$SYSTEM_LOG"
echo "Full system information saved to $SYSTEM_LOG"
separator

# Check filesystem
echo -e "${BLUE}Filesystem Status:${NC}"
(
  echo "=== DISK AND FILESYSTEM INFORMATION ==="
  echo "Date: $(date)"
  echo -e "\nMount Information:"
  mount | grep -v "tmpfs\|proc\|sys\|cgroup\|securityfs"
  echo -e "\nRoot Filesystem:"
  mount | grep " / " | grep -v "rootfs"
  if mount | grep " / " | grep -q "ro"; then
    echo "[ERROR] Root filesystem is mounted READ-ONLY!"
  else
    echo "[OK] Root filesystem is mounted read-write."
  fi
  echo -e "\nFilesystem Types:"
  df -T
  echo -e "\nDisk Usage:"
  df -h
  echo -e "\nBlock Devices:"
  lsblk -f
  echo -e "\nDisk by UUID:"
  ls -la /dev/disk/by-uuid/
  echo -e "\nDisk by Path:"
  ls -la /dev/disk/by-path/ 2>/dev/null || echo "No disk by path information"
  echo -e "\nFstab Configuration:"
  cat /etc/fstab
  echo -e "\nLast 10 Lines from dmesg related to disks:"
  dmesg | grep -iE 'sd|disk|fs|ext4|vda|error|warn' | tail -10
  echo -e "\nBoot Command Line:"
  cat /proc/cmdline
) | tee "$DISK_LOG"

# Test write access
echo -e "${BLUE}Write Access Test:${NC}"
TEST_DIR="/tmp/write-test-$(date +%s)"
mkdir -p "$TEST_DIR"
for i in {1..5}; do
  TEST_FILE="$TEST_DIR/test-$i.txt"
  if echo "Test data $i" > "$TEST_FILE" 2>/dev/null; then
    log_success "Successfully wrote to $TEST_FILE"
  else
    log_error "Failed to write to $TEST_FILE"
  fi
done

# Test file creation in various directories
for dir in "/tmp" "/home/$SUDO_USER" "/var/tmp" "/opt" "/usr/local/bin"; do
  if [ -d "$dir" ]; then
    TEST_FILE="$dir/write-test-$(date +%s).txt"
    if touch "$TEST_FILE" 2>/dev/null; then
      echo "Test data for $dir" > "$TEST_FILE"
      log_success "Successfully created file in $dir"
      rm "$TEST_FILE"
    else
      log_error "Failed to create file in $dir"
    fi
  else
    log_warning "Directory $dir does not exist"
  fi
done

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
(
  echo "=== NETWORK INFORMATION ==="
  echo "Date: $(date)"
  echo -e "\nIP Addresses:"
  hostname -I
  echo -e "\nHostname Resolution:"
  hostname
  hostname -f
  cat /etc/hostname
  cat /etc/hosts
  echo -e "\nDNS Configuration:"
  cat /etc/resolv.conf
  echo -e "\nNetwork Interfaces:"
  ip -br a
  echo -e "\nDetailed Interface Information:"
  ip a
  echo -e "\nRouting Table:"
  ip route
  echo -e "\nNetwork Statistics:"
  netstat -tuln
  echo -e "\nConnections:"
  netstat -tn
  echo -e "\nActive Internet Connections:"
  netstat -tuanp
  echo -e "\nArp Table:"
  arp -a || echo "arp command not available"
  echo -e "\nDHCP Client Configuration:"
  ls -la /var/lib/dhcp/
  [ -f /var/lib/dhcp/dhclient.leases ] && cat /var/lib/dhcp/dhclient.leases
  echo -e "\nNetwork Configuration Files:"
  ls -la /etc/netplan/ 2>/dev/null || echo "No netplan directory"
  find /etc/netplan -type f -exec cat {} \; 2>/dev/null
  echo -e "\nNetworkd Status:"
  systemctl status systemd-networkd || echo "systemd-networkd not running"
  echo -e "\nFirewall Status:"
  ufw status 2>/dev/null || echo "ufw not installed"
  iptables -L 2>/dev/null || echo "iptables command not available"
) | tee "$NETWORK_LOG"
echo "Full network information saved to $NETWORK_LOG"
separator

# Check services
echo -e "${BLUE}Services:${NC}"
(
  echo "=== SERVICE INFORMATION ==="
  echo "Date: $(date)"
  echo -e "\nSSH Status:"
  systemctl status ssh || echo "SSH service not found!"
  echo -e "\nSSH Configuration:"
  grep -v "^#" /etc/ssh/sshd_config | grep -v "^$"
  echo -e "\nQEMU Guest Agent Status:"
  systemctl status qemu-guest-agent || echo "QEMU Guest Agent not found!"
  echo -e "\nCritical Services Status:"
  systemctl status systemd-networkd systemd-resolved systemd-journald systemd-logind systemd-timesyncd
  echo -e "\nFailed Services:"
  systemctl --failed
  echo -e "\nAll Active Services:"
  systemctl list-units --type=service --state=active
  echo -e "\nService Boot Times:"
  systemd-analyze blame | head -20
  echo -e "\nTimers:"
  systemctl list-timers
  echo -e "\nCloud-Init Status:"
  cloud-init status
  echo -e "\nCloud-Init Result:"
  [ -f /run/cloud-init/result.json ] && cat /run/cloud-init/result.json
) | tee "$SERVICE_LOG"
echo "Full service information saved to $SERVICE_LOG"
separator

# Performance test
echo -e "${BLUE}Performance Test:${NC}"
(
  echo "=== PERFORMANCE INFORMATION ==="
  echo "Date: $(date)"
  echo -e "\nCPU Info:"
  cat /proc/cpuinfo
  echo -e "\nMemory Info:"
  cat /proc/meminfo
  echo -e "\nDisk Write Speed:"
  dd if=/dev/zero of=/tmp/testfile bs=1M count=100 conv=fdatasync 2>&1
  rm -f /tmp/testfile
  echo -e "\nDisk Read Speed:"
  dd if=/tmp/testfile of=/dev/null bs=1M count=100 2>&1
  echo -e "\nFile System Caching:"
  free -h
  echo 3 > /proc/sys/vm/drop_caches
  free -h
  echo -e "\nLoad Average:"
  cat /proc/loadavg
  echo -e "\nUptime:"
  cat /proc/uptime
  uptime
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
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 /tmp/vm_diagnostics.sh "$VM_USER@$VM_IP:$REMOTE_DIAGNOSTIC_SCRIPT" || {
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