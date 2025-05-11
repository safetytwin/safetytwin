# SafetyTwin VM Provisioning Script - Documentation

## Overview

The `safetytwin_vm.sh` script is a comprehensive tool for creating and configuring virtual machines for the SafetyTwin project. It automates the creation of VMs using cloud-init, configures networking, and sets up SSH access, making the process of VM deployment consistent and reliable.

## Features

- Downloads and uses official Ubuntu cloud images
- Configures cloud-init for proper VM initialization
- Sets up network interfaces with DHCP
- Installs essential packages
- Configures SSH for password authentication
- Waits for VM boot and verifies IP address acquisition
- Tests SSH connectivity
- Creates SSH configuration for easy access
- Saves VM information for future reference

## Requirements

- Ubuntu/Debian host system
- KVM/QEMU and libvirt installed
- virsh and virt-install commands available
- sudo privileges

## Installation

1. Download the script:
   ```bash
   wget -O safetytwin_vm.sh https://raw.githubusercontent.com/yourusername/safetytwin/main/safetytwin_vm.sh
   chmod +x safetytwin_vm.sh
   ```

2. Ensure required packages are installed:
   ```bash
   sudo apt-get update
   sudo apt-get install -y qemu-kvm libvirt-daemon-system virtinst \
     libvirt-clients bridge-utils genisoimage netcat-openbsd
   ```

## Usage

### Basic Usage

```bash
sudo ./safetytwin_vm.sh
```

This creates a VM with the default name "safetytwin-vm".

### Custom VM Name

```bash
sudo ./safetytwin_vm.sh custom-vm-name
```

### Listing Available VMs

To list all available virtual machines and their status:

```bash
sudo virsh list --all
```

This will display a table of VMs with their state (running, shut off, etc.).

To see only running VMs:

```bash
sudo virsh list
```

```aiignore
 Id   Name            State
-------------------------------
 1    safetytwin-vm   running
```


### Getting VM IP Addresses

To find the IP address of a specific VM:

```bash
sudo virsh domifaddr safetytwin-vm
```

```aiignore
 Name       MAC address          Protocol     Address
-------------------------------------------------------------------------------
 vnet0      52:54:00:de:3d:40    ipv4         192.168.122.113/24
```

To list all VMs with their IP addresses (useful script):

```bash
for vm in $(sudo virsh list --name); do
  echo -n "$vm: "
  sudo virsh domifaddr "$vm" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo "No IP"
done
```

### Configuration Options

You can customize the VM by editing the following variables at the top of the script:

| Variable | Default | Description |
|----------|---------|-------------|
| VM_NAME | safetytwin-vm | Name of the virtual machine |
| VM_MEMORY | 2048 | VM memory allocation in MB |
| VM_CPUS | 2 | Number of virtual CPUs |
| VM_DISK_SIZE | 20G | Disk size for the VM |
| USERNAME | ubuntu | Default username |
| PASSWORD | ubuntu | Default password |
| INSTALL_PACKAGES | qemu-guest-agent openssh-server python3 net-tools iproute2 | Space-separated list of packages to install |

## VM Access Methods

After successful VM creation, you can access it using:

### SSH Access

```bash
# Using the IP address
ssh ubuntu@<VM_IP>

# Using the SSH config entry (if created)
ssh safetytwin-vm
```

### SSH Password Login

The default login credentials are:
- Username: `ubuntu`
- Password: `ubuntu`

When prompted for a password during SSH, enter the password configured in the script.

### Passwordless SSH with Keys

To set up passwordless SSH access:

1. Generate SSH keys if you don't have them:
   ```bash
   ssh-keygen -t rsa
   ```

2. Edit the script to include your public key:
   ```bash
   # Add to the user section in cloud-init configuration:
   ssh_authorized_keys:
     - $(cat ~/.ssh/id_rsa.pub)
   ```

3. Run the script to create the VM with key authentication

### Console Access

Access the VM console directly (useful when SSH isn't working):

```bash
sudo virsh console safetytwin-vm
```

To exit the console session, press: `Ctrl + ]`

### VNC Access (Optional)

If you modify the script to enable VNC:

1. Change the graphics line to:
   ```
   --graphics vnc,listen=0.0.0.0
   ```

2. Connect using a VNC client to your host's IP on the assigned port (check with `sudo virsh vncdisplay safetytwin-vm`)

## VM Management

### Starting and Stopping VMs

```bash
# Start a VM
sudo virsh start safetytwin-vm

# Gracefully shutdown a VM
sudo virsh shutdown safetytwin-vm

# Force stop a VM
sudo virsh destroy safetytwin-vm
```

### Deleting a VM

```bash
# Shutdown the VM first
sudo virsh shutdown safetytwin-vm

# Then remove it completely
sudo virsh undefine safetytwin-vm --remove-all-storage
```

## File Locations

| File | Location | Description |
|------|----------|-------------|
| VM Disk Image | /var/lib/safetytwin/images/safetytwin-vm.qcow2 | VM disk image |
| Cloud-init ISO | /var/lib/safetytwin/cloud-init/cloud-init.iso | Cloud-init configuration ISO |
| VM Info | /var/lib/safetytwin/safetytwin-vm-info.txt | VM information summary |
| SSH Config | ~/.ssh/config | SSH configuration file |

## Troubleshooting

### VM Creation Issues

If VM creation fails:
1. Check the libvirt logs: `sudo journalctl -u libvirtd`
2. Verify disk permissions: `ls -la /var/lib/safetytwin/images/`
3. Check cloud-init files: `cat /var/lib/safetytwin/cloud-init/user-data`

### Networking Issues

If the VM doesn't get an IP address:
1. Check libvirt network status: `sudo virsh net-list --all`
2. Verify network is active: `sudo virsh net-info default`
3. Check dnsmasq: `sudo cat /var/lib/libvirt/dnsmasq/default.leases`

### SSH Issues

If you can't SSH into the VM:
1. Check VM status: `sudo virsh dominfo safetytwin-vm`
2. Verify IP address: `sudo virsh domifaddr safetytwin-vm`
3. Test SSH port: `nc -zv <VM_IP> 22`
4. Access console to check services: `sudo virsh console safetytwin-vm`

Inside the VM console, verify SSH service:
```bash
systemctl status sshd
# If not running, start it:
sudo systemctl start sshd
# Check configuration:
sudo cat /etc/ssh/sshd_config | grep PasswordAuthentication
```

### Login Issues

If you can't log in with the provided credentials:

1. From the console, reset the password:
   ```bash
   sudo passwd ubuntu
   ```

2. Verify the user exists:
   ```bash
   cat /etc/passwd | grep ubuntu
   ```

3. Check cloud-init logs for errors in user creation:
   ```bash
   sudo cat /var/log/cloud-init.log
   ```

## Examples

### Creating a Development VM with More Resources

```bash
# Edit script to set:
# VM_NAME="dev-vm"
# VM_MEMORY=4096
# VM_CPUS=4
# VM_DISK_SIZE=40G
sudo ./safetytwin_vm.sh dev-vm
```

### Creating Multiple VMs

```bash
sudo ./safetytwin_vm.sh node1
sudo ./safetytwin_vm.sh node2
sudo ./safetytwin_vm.sh node3
```

## Advanced Configuration

For advanced cloud-init configurations, edit the `cat > "$USER_DATA"` section of the script to include:

- Custom software installations
- System configurations
- Scripts to run on first boot
- Network configurations
- User setup and SSH keys

## Security Considerations

- The default configuration uses password authentication with a known password
- For production systems, consider:
  - Using SSH keys instead of passwords
  - Setting unique passwords
  - Implementing proper network isolation
  - Disabling root access

## Support

For issues or questions regarding this script, contact the SafetyTwin development team.

| VM_MEMORY | 2048 | VM memory allocation in MB |
| VM_CPUS | 2 | Number of virtual CPUs |
| VM_DISK_SIZE | 20G | Disk size for the VM |
| USERNAME | ubuntu | Default username |
| PASSWORD | ubuntu | Default password |
| INSTALL_PACKAGES | qemu-guest-agent openssh-server python3 net-tools iproute2 | Space-separated list of packages to install |

## VM Access Methods

After successful VM creation, you can access it using:

### SSH Access

```bash
# Using the IP address
ssh ubuntu@<VM_IP>

# Using the SSH config entry (if created)
ssh safetytwin-vm
```

### Console Access

```bash
sudo virsh console safetytwin-vm
```

## File Locations

| File | Location | Description |
|------|----------|-------------|
| VM Disk Image | /var/lib/safetytwin/images/safetytwin-vm.qcow2 | VM disk image |
| Cloud-init ISO | /var/lib/safetytwin/cloud-init/cloud-init.iso | Cloud-init configuration ISO |
| VM Info | /var/lib/safetytwin/safetytwin-vm-info.txt | VM information summary |
| SSH Config | ~/.ssh/config | SSH configuration file |

## Troubleshooting

### VM Creation Issues

If VM creation fails:
1. Check the libvirt logs: `sudo journalctl -u libvirtd`
2. Verify disk permissions: `ls -la /var/lib/safetytwin/images/`
3. Check cloud-init files: `cat /var/lib/safetytwin/cloud-init/user-data`

### Networking Issues

If the VM doesn't get an IP address:
1. Check libvirt network status: `sudo virsh net-list --all`
2. Verify network is active: `sudo virsh net-info default`
3. Check dnsmasq: `sudo cat /var/lib/libvirt/dnsmasq/default.leases`

### SSH Issues

If you can't SSH into the VM:
1. Check VM status: `sudo virsh dominfo safetytwin-vm`
2. Verify IP address: `sudo virsh domifaddr safetytwin-vm`
3. Test SSH port: `nc -zv <VM_IP> 22`
4. Access console to check services: `sudo virsh console safetytwin-vm`

## Examples

### Creating a Development VM with More Resources

```bash
# Edit script to set:
# VM_NAME="dev-vm"
# VM_MEMORY=4096
# VM_CPUS=4
# VM_DISK_SIZE=40G
sudo ./preinstall.sh dev-vm
```

### Creating Multiple VMs

```bash
sudo ./preinstall.sh node1
sudo ./preinstall.sh node2
sudo ./preinstall.sh node3
```

## Advanced Configuration

For advanced cloud-init configurations, edit the `cat > "$USER_DATA"` section of the script to include:

- Custom software installations
- System configurations
- Scripts to run on first boot
- Network configurations
- User setup and SSH keys

## Security Considerations

- The default configuration uses password authentication with a known password
- For production systems, consider:
  - Using SSH keys instead of passwords
  - Setting unique passwords
  - Implementing proper network isolation
  - Disabling root access


## Updated preinstall.sh with Enhanced Disk Access Configuration

### Key Improvements in This Version

1. **Proper Image Format Handling**:
   - Explicitly converts to qcow2 format to avoid corruption
   - Uses proper cache and I/O settings for better disk performance

2. **Enhanced Filesystem Configuration**:
   - Adds filesystem repair parameters to GRUB
   - Sets up system performance parameters
   - Creates a test file to verify write access

3. **Improved Network Configuration**:
   - Configures multiple possible interface names
   - Verifies default network is active before VM creation

4. **Better Error Recovery**:
   - Increases timeout values for more reliable boot
   - Handles SSH directory creation if missing

5. **Included Diagnostics Script**:
   - Creates and transfers a comprehensive diagnostics script
   - Adds detailed testing of write access

6. **More Complete Initialization**:
   - Enables QEMU guest agent
   - Configures system for optimal VM performance
   - Verifies write access during VM creation

These changes should resolve the filesystem corruption and read-only issues you were experiencing with the previous VMs. The script is also more resilient to potential issues during VM creation.