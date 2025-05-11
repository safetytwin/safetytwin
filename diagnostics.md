# diagnostics.sh - VM Diagnostic Script for Ubuntu


## How to Use This Script

1. **Transfer to VM**: After creating and starting your VM, copy this script to it:
   ```bash
   # From host, assuming you know the VM's IP
   scp diagnostics.sh ubuntu@VM_IP_ADDRESS:~
   
   # Or create it directly in the VM
   ssh ubuntu@VM_IP_ADDRESS "cat > diagnostics.sh" < diagnostics.sh 
   ```

2. **Run inside VM**: Connect to VM and run with sudo:
   ```bash
   ssh ubuntu@VM_IP_ADDRESS
   chmod +x diagnostics.sh
   sudo ./diagnostics.sh
   ```


## How to Use the VM Diagnostics Tool

This improved script adds VM detection and clearer instructions for running in the correct environment:

1. **Copy to VM**:
   ```bash
   # Save script on host first
   scp diagnostics.sh ubuntu@VM_IP_ADDRESS:~/
   scp diagnostics.sh ubuntu@192.168.122.98:~/
   ssh ubuntu@192.168.122.98 "cat > diagnostics.sh" < diagnostics.sh 
   scp ubuntu@192.168.122.98:/tmp/vm_diagnostics_20250511_102644.log diagnostics.log

   ```

2. **SSH to VM**:
   ```bash
   ssh ubuntu@VM_IP_ADDRESS
   ```

3. **Run with sudo**:
   ```bash
   sudo bash diagnostics.sh
   ```
   
3. **Review Results**: The script will display a comprehensive report in the console and save it to `/tmp/diagnostics.log`.

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

