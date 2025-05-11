#!/bin/bash
# diagnostics.sh - Comprehensive diagnostic and comparison tool for SafetyTwin VMs
# Author: Tom Sapletta
# Version: 1.1
# Usage: Run inside the VM after creation to verify configuration and compare with host

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log file
DIAGNOSTIC_LOG="/tmp/diagnostics_$(date +%Y%m%d_%H%M%S).log"

# Logging functions
log() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$DIAGNOSTIC_LOG"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$DIAGNOSTIC_LOG"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$DIAGNOSTIC_LOG"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$DIAGNOSTIC_LOG"; }
log_header() { echo -e "\n${CYAN}=========== $1 ===========${NC}" | tee -a "$DIAGNOSTIC_LOG"; }
separator() { echo -e "--------------------------------------------------------" | tee -a "$DIAGNOSTIC_LOG"; }

# Check if running on a VM or host
is_vm() {
    # Methods to detect if running in a VM
    if [ -e /sys/class/dmi/id/product_name ]; then
        product=$(cat /sys/class/dmi/id/product_name)
        if [[ "$product" == *"Virtual"* || "$product" == *"VMware"* || "$product" == *"QEMU"* ]]; then
            return 0
        fi
    fi

    # Check for common VM hypervisor processes
    if ps aux | grep -iE 'qemu|kvm|virtualbox|vmware' | grep -v grep > /dev/null; then
        return 0
    fi

    # Check for cloud-init
    if [ -d /var/lib/cloud/instance ]; then
        return 0
    fi

    # Check if running in a container
    if grep -q container=lxc /proc/1/environ 2>/dev/null; then
        return 0
    fi

    return 1
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run as root.${NC}"
    echo "Please re-run as: sudo $(basename $0)"
    exit 1
fi

# Detect if running on host or VM
if ! is_vm; then
    log_header "WARNING: RUNNING ON HOST SYSTEM"
    echo -e "${YELLOW}This script is designed to run inside a VM, but it appears you're running it on the host system.${NC}"
    echo -e "To run this script properly:"
    echo -e "  1. Copy this script to your VM using: ${CYAN}scp $(realpath $0) ubuntu@VM_IP_ADDRESS:~/${NC}"
    echo -e "  2. SSH into your VM: ${CYAN}ssh ubuntu@VM_IP_ADDRESS${NC}"
    echo -e "  3. Run inside the VM: ${CYAN}sudo bash $(basename $0)${NC}"
    echo
    read -p "Do you want to continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    echo "Continuing on host system..."
fi

# Start diagnostics
log_header "SafetyTwin VM Diagnostics"
log "Starting diagnostic checks on $(hostname) at $(date)"
log "Diagnostic results will be saved to $DIAGNOSTIC_LOG"
separator

# System Information
log_header "System Information"
echo "Hostname: $(hostname)" | tee -a "$DIAGNOSTIC_LOG"
echo "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)" | tee -a "$DIAGNOSTIC_LOG"
echo "Kernel: $(uname -r)" | tee -a "$DIAGNOSTIC_LOG"
echo "CPU Cores: $(nproc)" | tee -a "$DIAGNOSTIC_LOG"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')" | tee -a "$DIAGNOSTIC_LOG"
echo "Disk Size: $(df -h / | awk 'NR==2 {print $2}')" | tee -a "$DIAGNOSTIC_LOG"
echo "IP Addresses:" | tee -a "$DIAGNOSTIC_LOG"
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | while read ip; do
    if [[ $ip != "127.0.0.1" ]]; then
        echo "  - $ip (Primary External IP)" | tee -a "$DIAGNOSTIC_LOG"
    else
        echo "  - $ip (Loopback)" | tee -a "$DIAGNOSTIC_LOG"
    fi
done
separator

# User Configuration
log_header "User Configuration"
# Expected values for the VM
EXPECTED_USERNAME="ubuntu"

if id "$EXPECTED_USERNAME" &>/dev/null; then
    log_success "User '$EXPECTED_USERNAME' exists"

    # Check sudo privileges
    if groups "$EXPECTED_USERNAME" | grep -q -E '\bsudo\b|\badmin\b'; then
        log_success "User '$EXPECTED_USERNAME' has sudo privileges"
    else
        log_error "User '$EXPECTED_USERNAME' does not have sudo privileges"
    fi

    # Check password authentication
    if [ -f /etc/ssh/sshd_config ]; then
        if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config; then
            log_success "Password authentication is enabled in SSH"
        elif grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
            log_error "Password authentication is explicitly disabled in SSH"
        else
            # Check the default
            if grep -q "^#PasswordAuthentication" /etc/ssh/sshd_config; then
                log_warning "Password authentication uses default setting (usually yes)"
            else
                log_warning "Could not determine SSH password authentication setting"
            fi
        fi
    else
        log_error "SSH config file not found at /etc/ssh/sshd_config"
    fi

    # Check if password is set
    if grep -q "^$EXPECTED_USERNAME:[^*\!]" /etc/shadow; then
        log_success "User '$EXPECTED_USERNAME' has a password set"
    else
        log_error "User '$EXPECTED_USERNAME' has no password or account is locked"
    fi
else
    log_error "Expected user '$EXPECTED_USERNAME' does not exist"
fi
separator

# Network Configuration
log_header "Network Configuration"
# Check network interfaces
log "Network interfaces:"
ip -o link show | grep -v "lo:" | awk -F': ' '{print $2}' | while read iface; do
    echo "Interface: $iface" | tee -a "$DIAGNOSTIC_LOG"

    # Check if interface is up
    if ip link show "$iface" | grep -q "state UP"; then
        log_success "  - Interface is UP"
    else
        log_warning "  - Interface is DOWN"
    fi

    # Check if interface has IP
    if ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
        ip=$(ip addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        log_success "  - Has IP address: $ip"

        # Check if IP is in the expected range for VMs
        if [[ "$ip" == 192.168.122.* ]]; then
            log_success "  - IP is in the expected libvirt default network range (192.168.122.x)"
        fi
    else
        log_warning "  - No IP address assigned"
    fi
done

# Check default gateway
if ip route | grep -q "default"; then
    gateway=$(ip route | grep default | awk '{print $3}')
    log_success "Default gateway is set: $gateway"
else
    log_error "No default gateway configured"
fi

# Check DNS resolution
if [ -f /etc/resolv.conf ]; then
    if grep -q "nameserver" /etc/resolv.conf; then
        nameservers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
        log_success "DNS servers configured: $nameservers"
    else
        log_error "No DNS servers configured in resolv.conf"
    fi
else
    log_error "resolv.conf file not found"
fi

# DNS resolution test
if ping -c 1 google.com &>/dev/null; then
    log_success "DNS resolution working (pinged google.com)"
else
    log_error "DNS resolution failing (couldn't ping google.com)"
fi
separator

# Expected Values for VM
EXPECTED_PACKAGES="qemu-guest-agent openssh-server python3 net-tools iproute2"

# Package Installation
log_header "Package Installation"
for pkg in $EXPECTED_PACKAGES; do
    if command -v dpkg >/dev/null; then
        # For Debian-based systems
        if dpkg -l | grep -q " $pkg "; then
            log_success "Package $pkg is installed"
        else
            log_error "Package $pkg is NOT installed"
        fi
    elif command -v rpm >/dev/null; then
        # For RPM-based systems
        if rpm -q $pkg >/dev/null 2>&1; then
            log_success "Package $pkg is installed"
        else
            log_error "Package $pkg is NOT installed"
        fi
    else
        # Fallback check
        if command -v $pkg >/dev/null 2>&1; then
            log_success "Command $pkg is available"
        else
            log_warning "Could not verify if $pkg is installed (dpkg/rpm not found)"
        fi
    fi
done
separator

# Service Status
log_header "Service Status"
# Check SSH service
if command -v systemctl >/dev/null; then
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        log_success "SSH service is running"
    else
        log_error "SSH service is NOT running"
    fi
else
    # Fallback for non-systemd systems
    if ps aux | grep -v grep | grep -q "sshd"; then
        log_success "SSH process is running"
    else
        log_error "SSH process is NOT running"
    fi
fi

# Check if SSH is listening on port 22
if command -v ss >/dev/null; then
    if ss -tuln | grep -q ":22 "; then
        log_success "SSH is listening on port 22"
    else
        log_error "SSH is NOT listening on port 22"
    fi
elif command -v netstat >/dev/null; then
    if netstat -tuln | grep -q ":22 "; then
        log_success "SSH is listening on port 22"
    else
        log_error "SSH is NOT listening on port 22"
    fi
else
    log_warning "Cannot check if SSH is listening (ss/netstat not found)"
fi

# Check qemu-guest-agent
if command -v systemctl >/dev/null; then
    if systemctl is-active --quiet qemu-guest-agent; then
        log_success "QEMU Guest Agent is running"
    else
        log_warning "QEMU Guest Agent is NOT running (might not be installed)"
    fi
fi
separator

# Cloud-init status
log_header "Cloud-init Status"
if [ -f /run/cloud-init/result.json ]; then
    if grep -q '"errors": \[\]' /run/cloud-init/result.json; then
        log_success "Cloud-init completed successfully"
    else
        log_error "Cloud-init reported errors"
        errors=$(grep -o '"errors": \[[^]]*\]' /run/cloud-init/result.json)
        echo "$errors" | tee -a "$DIAGNOSTIC_LOG"
    fi
elif [ -f /var/lib/cloud/data/status.json ]; then
    status=$(grep -o '"status": "[^"]*"' /var/lib/cloud/data/status.json | cut -d'"' -f4)
    if [ "$status" = "done" ]; then
        log_success "Cloud-init status: $status"
    else
        log_warning "Cloud-init status: $status"
    fi
else
    log_warning "Cloud-init status files not found"
fi

# Check cloud-init logs for errors
if [ -f /var/log/cloud-init.log ]; then
    if grep -i "error" /var/log/cloud-init.log | grep -v "Errno 32" | grep -v "Errno 111" | head -5 > /tmp/cloud_init_errors; then
        if [ -s /tmp/cloud_init_errors ]; then
            log_warning "Found errors in cloud-init.log:"
            cat /tmp/cloud_init_errors | tee -a "$DIAGNOSTIC_LOG"
        else
            log_success "No significant errors found in cloud-init.log"
        fi
    else
        log_success "No errors found in cloud-init.log"
    fi
    rm -f /tmp/cloud_init_errors
else
    log_warning "Cloud-init log file not found"
fi
separator

# Resource utilization
log_header "Resource Utilization"
echo "CPU usage:" | tee -a "$DIAGNOSTIC_LOG"
if command -v top >/dev/null; then
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "  - CPU idle: "$1"%"}' | tee -a "$DIAGNOSTIC_LOG"
fi

echo "Memory usage:" | tee -a "$DIAGNOSTIC_LOG"
free -h | grep -E "Mem|Swap" | tee -a "$DIAGNOSTIC_LOG"

echo "Disk usage:" | tee -a "$DIAGNOSTIC_LOG"
df -h / | awk 'NR==2 {print "  - Used: "$5", Free: "$4}' | tee -a "$DIAGNOSTIC_LOG"
separator

# Performance tests
log_header "Basic Performance Tests"

# Disk speed test with smaller file size for VMs
echo "Disk write speed test:" | tee -a "$DIAGNOSTIC_LOG"
dd if=/dev/zero of=/tmp/test bs=1M count=100 conv=fdatasync 2>&1 | grep -oP '\d+(\.\d+)? \w+/s' | tee -a "$DIAGNOSTIC_LOG"
rm -f /tmp/test

# Network test
echo "Network connectivity test:" | tee -a "$DIAGNOSTIC_LOG"
ping -c 4 8.8.8.8 2>/dev/null | grep -E "transmitted|rtt" | tee -a "$DIAGNOSTIC_LOG"
if [ $? -ne 0 ]; then
    echo "Failed to ping 8.8.8.8" | tee -a "$DIAGNOSTIC_LOG"
fi
separator

# Compliance Check
log_header "System Compliance Check"

# Expected configuration for VM
EXPECTED_CORES=2
EXPECTED_MEM_KB=2000000  # ~2GB
EXPECTED_DISK_GB=10

# Check CPU cores
ACTUAL_CORES=$(nproc)
if [ "$ACTUAL_CORES" -ge "$EXPECTED_CORES" ]; then
    log_success "CPU cores: $ACTUAL_CORES (expected minimum: $EXPECTED_CORES)"
else
    log_error "CPU cores: $ACTUAL_CORES (expected minimum: $EXPECTED_CORES)"
fi

# Check memory
ACTUAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "$ACTUAL_MEM_KB" -ge "$EXPECTED_MEM_KB" ]; then
    log_success "Memory: $(($ACTUAL_MEM_KB / 1024)) MB (expected minimum: $(($EXPECTED_MEM_KB / 1024)) MB)"
else
    log_error "Memory: $(($ACTUAL_MEM_KB / 1024)) MB (expected minimum: $(($EXPECTED_MEM_KB / 1024)) MB)"
fi

# Check disk space
ACTUAL_DISK_GB=$(df -BG / | awk 'NR==2 {gsub("G","",$2); print $2+0}') # +0 to convert to number
if [ "$ACTUAL_DISK_GB" -ge "$EXPECTED_DISK_GB" ]; then
    log_success "Disk space: ${ACTUAL_DISK_GB}GB (expected minimum: ${EXPECTED_DISK_GB}GB)"
else
    log_error "Disk space: ${ACTUAL_DISK_GB}GB (expected minimum: ${EXPECTED_DISK_GB}GB)"
fi

# VM vs Host identification
if is_vm; then
    log_success "System correctly identified as a VM"

    # More VM specific checks
    if [ -d /var/lib/cloud ]; then
        log_success "Cloud-init directories exist"
    else
        log_warning "Cloud-init directories not found"
    fi
else
    log_error "System appears to be a host, not a VM"
fi
separator

# Summary report
log_header "Diagnostic Summary"
ERRORS=$(grep -c "\[ERROR\]" "$DIAGNOSTIC_LOG")
WARNINGS=$(grep -c "\[WARNING\]" "$DIAGNOSTIC_LOG")
SUCCESS=$(grep -c "\[OK\]" "$DIAGNOSTIC_LOG")

echo "Date: $(date)" | tee -a "$DIAGNOSTIC_LOG"
echo "Hostname: $(hostname)" | tee -a "$DIAGNOSTIC_LOG"
primary_ip=$(ip -4 addr show | grep -v "127.0.0.1" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
echo "Primary IP: $primary_ip" | tee -a "$DIAGNOSTIC_LOG"
echo "Checks passed: $SUCCESS" | tee -a "$DIAGNOSTIC_LOG"
echo "Warnings: $WARNINGS" | tee -a "$DIAGNOSTIC_LOG"
echo "Errors: $ERRORS" | tee -a "$DIAGNOSTIC_LOG"

if [ "$ERRORS" -eq 0 ]; then
    if [ "$WARNINGS" -eq 0 ]; then
        log_success "All checks passed successfully. VM meets all requirements."
    else
        log_warning "VM meets essential requirements with $WARNINGS warnings. Review warnings above."
    fi
else
    log_error "VM has $ERRORS issues that need attention. See errors above."
fi

if ! is_vm; then
    log_error "This script was run on the host system. Please run it inside your VM for accurate results."
    log "To run this script inside the VM, use:"
    log "  scp $(basename $0) ubuntu@VM_IP:~/"
    log "  ssh ubuntu@VM_IP"
    log "  sudo bash $(basename $0)"
fi

echo "" | tee -a "$DIAGNOSTIC_LOG"
log "Complete diagnostic report saved to $DIAGNOSTIC_LOG"
log "To view condensed results: grep -E '\[ERROR\]|\[WARNING\]|\[OK\]' $DIAGNOSTIC_LOG"