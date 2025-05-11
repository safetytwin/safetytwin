# SafetyTwin VM Provisioning Script - Documentation

The `preinstall.sh` script is a comprehensive tool for creating and configuring virtual machines for the SafetyTwin project. It automates the creation of VMs using cloud-init, configures networking, and sets up SSH access, making the process of VM deployment consistent and reliable.

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
   wget -O preinstall.sh https://raw.githubusercontent.com/safetytwin/safetytwin/main/preinstall.sh
   chmod +x preinstall.sh
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
sudo ./preinstall.sh
```

This creates a VM with the default name "safetytwin-vm".

### Custom VM Name

```bash
sudo ./preinstall.sh custom-vm-name
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


