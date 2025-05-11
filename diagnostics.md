# diagnostics.sh - VM Diagnostic Script for Ubuntu


## How to Use the Diagnostics Workflow

**Recommended (Automated) Method:**

1. **From the host, run:**
   ```bash
   sudo bash diagnostics_download.sh
   ```
   This will:
   - Start the VM if needed
   - Copy `diagnostics.sh` to the VM
   - Run diagnostics inside the VM (as root)
   - Download the latest diagnostics log to a timestamped local directory (`./vm_logs_YYYYMMDD_HHMMSS/`)

2. **Review the log:**
   - Use:
     ```bash
     grep -E '\[ERROR\]|\[WARNING\]|\[OK\]' ./vm_logs_YYYYMMDD_HHMMSS/diagnostics_*.log
     ```
   - Or open the full log in your editor.

**Manual Method (for advanced troubleshooting):**

- Copy `diagnostics.sh` to the VM manually and run as root:
  ```bash
  scp diagnostics.sh ubuntu@VM_IP_ADDRESS:/tmp/
  ssh ubuntu@VM_IP_ADDRESS
  sudo bash /tmp/diagnostics.sh
  ```
- The log will be saved in `/tmp/diagnostics_YYYYMMDD_HHMMSS.log` inside the VM. Use `scp` to download if needed.

---

## Troubleshooting
- If diagnostics fail to run, check:
  - That the VM is running and accessible via SSH
  - That you have root privileges inside the VM
  - That `diagnostics.sh` exists and is executable
- If logs are not downloaded, ensure `sshpass`, `scp`, and network connectivity are working from host to VM.
- For more details, see [INSTALL.md](INSTALL.md) and [README.md](README.md).

## What This Script Checks

1. **System Information**:
   - Hostname, OS, kernel version
   - CPU, memory, disk resources
   - IP addresses

2. **User Configuration**:
   - Verifies expected username exists
   - Checks sudo privileges
   - Confirms password authentication works

3. **Network Configuration**:
   - Validates network interfaces are up
   - Confirms IP address assignment
   - Checks DHCP, default gateway, DNS

4. **Package Installation**:
   - Verifies all expected packages are installed

5. **Service Status**:
   - Checks critical services like SSH and qemu-guest-agent
   - Validates SSH is listening on port 22

6. **Cloud-init Status**:
   - Examines cloud-init completion and errors

7. **Resource Utilization**:
   - Measures current CPU, memory, disk usage

8. **Performance Tests**:
   - Basic disk I/O test
   - Network connectivity test

9. **Compliance Check**:
   - Compares actual resources with expected minimums

The script will give you both a detailed view of the VM's state and a compliance summary showing if it meets the expected specifications.






1. Detects whether it's being run on a host or VM
2. Provides clearer instructions for transferring to the VM
3. Includes a comparison report between host and VM systems


The script will now:
- Detect if it's running on VM or host
- Provide clear warnings and instructions if run on host
- Perform comprehensive checks of VM configuration
- Compare against expected specifications
- Generate a detailed report

This new version adds several improvements:
1. Host/VM detection to prevent running on the wrong system
2. Better handling of SSH service detection
3. More precise cloud-init checks
4. More robust file existence and command availability checks
5. Clear instructions for transferring to VM
6. More targeted error messages

