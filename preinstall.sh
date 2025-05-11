#!/bin/bash
# preinstall.sh - Minimal VM/cloud-init test for troubleshooting SSH and provisioning
# Author: Tom Sapletta
# Date: 2025-05-11
set -e

VM_NAME="safetytwin-vm"
CLOUD_INIT_DIR="/var/lib/safetytwin/cloud-init"
IMG_DIR="/var/lib/safetytwin/images"
BASE_IMG="$IMG_DIR/ubuntu-base.img"
USER_DATA="$CLOUD_INIT_DIR/user-data"
META_DATA="$CLOUD_INIT_DIR/meta-data"
ISO="$CLOUD_INIT_DIR/cloud-init.iso"

# 1. Stop and remove existing VM (ignore errors if not present)
echo "[preinstall.sh] Shutting down and removing old VM if exists..."
sudo virsh destroy "$VM_NAME" || true
sudo virsh undefine --nvram "$VM_NAME" || true

# 2. Generate minimal cloud-init user-data and meta-data with improved configuration
echo "[preinstall.sh] Generating minimal cloud-init user-data and meta-data..."
sudo bash -c "cat > $USER_DATA << EOF
#cloud-config
hostname: $VM_NAME
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: 'ubuntu'
ssh_pwauth: true
disable_root: false

# Ensure network is properly configured - Try more aggressive approach
network:
  version: 2
  renderer: networkd
  ethernets:
    # Try all possible network interfaces with both networkd and dhcp
    enp1s0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: true
        use-dns: true
    ens3:
      dhcp4: true
      dhcp4-overrides:
        use-routes: true
        use-dns: true
    eth0:
      dhcp4: true
      dhcp4-overrides:
        use-routes: true
        use-dns: true

# Install basic packages
package_update: true
packages:
  - qemu-guest-agent
  - openssh-server
  - net-tools
  - iproute2

# Force SSH to accept password authentication and configure network
runcmd:
  - echo 'ubuntu:ubuntu' | chpasswd
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  - systemctl restart ssh
  - dhclient -v
  - ip link set dev enp1s0 up || true
  - ip link set dev ens3 up || true
  - ip link set dev eth0 up || true
  - dhclient -v enp1s0 || true
  - dhclient -v ens3 || true
  - dhclient -v eth0 || true
  - netplan apply || true
  - systemctl restart systemd-networkd
EOF"

sudo bash -c "cat > $META_DATA << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF"

# 3. Rebuild cloud-init ISO with proper permissions
echo "[preinstall.sh] Rebuilding cloud-init ISO..."
sudo genisoimage -output "$ISO" -volid cidata -joliet -rock "$META_DATA" "$USER_DATA"
sudo chmod 644 "$ISO"
sudo chown libvirt-qemu:libvirt-qemu "$ISO"

# 4. Create and start the VM with adequate resources
echo "[preinstall.sh] Creating and starting new VM..."
sudo virt-install --name "$VM_NAME" \
  --memory 2048 \
  --vcpus 2 \
  --disk "$BASE_IMG",device=disk,bus=virtio \
  --disk "$ISO",device=cdrom,bus=sata \
  --os-variant ubuntu20.04 \
  --virt-type kvm \
  --graphics none \
  --network network=default,model=virtio \
  --import \
  --noautoconsole \
  --check path_in_use=off

echo "[preinstall.sh] VM created. Now waiting for VM to boot and get an IP address..."

# 5. Wait and check for VM connectivity
MAX_ATTEMPTS=8  # 8 x 15 seconds = 2 minutes
ATTEMPT=1
VM_IP=""

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
  echo "[preinstall.sh] Attempt $ATTEMPT/$MAX_ATTEMPTS: Checking if VM has an IP address..."

  # Check if VM has an IP address
  VM_IP=$(sudo virsh domifaddr "$VM_NAME" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

  if [ -n "$VM_IP" ]; then
    echo "[preinstall.sh] SUCCESS! VM has IP address: $VM_IP"

    # Try to check SSH port
    echo "[preinstall.sh] Testing SSH connectivity to $VM_IP..."
    if nc -z -w 5 "$VM_IP" 22 2>/dev/null; then
      echo "[preinstall.sh] SUCCESS! SSH port is open on $VM_IP"
      echo "[preinstall.sh] Attempting to login via SSH..."

      # Create expect script for automated SSH login
      cat > /tmp/ssh_login.exp << EOL
#!/usr/bin/expect -f
spawn ssh ubuntu@$VM_IP
expect {
  "yes/no" { send "yes\r"; exp_continue }
  "password:" { send "ubuntu\r" }
}
expect "ubuntu@"
send "ip a\r"
expect "ubuntu@"
send "sudo systemctl status sshd\r"
expect "ubuntu@"
send "exit\r"
expect eof
EOL
      chmod +x /tmp/ssh_login.exp
      echo "[preinstall.sh] Running automated SSH login test..."
      /usr/bin/expect -f /tmp/ssh_login.exp || echo "[preinstall.sh] SSH login failed but connectivity was detected."

      break
    else
      echo "[preinstall.sh] SSH port not responding yet. Will keep checking..."
    fi
  else
    echo "[preinstall.sh] VM doesn't have an IP address yet."
  fi

  if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "[preinstall.sh] Maximum attempts reached."
    if [ -n "$VM_IP" ]; then
      echo "[preinstall.sh] VM has IP address: $VM_IP but SSH may not be ready."
      echo "[preinstall.sh] Try: ssh ubuntu@$VM_IP (password: ubuntu)"
    else
      echo "[preinstall.sh] VM did not get an IP address in the allocated time."
      echo "[preinstall.sh] Accessing VM console for troubleshooting..."

      # Create expect script for automated console login
      cat > /tmp/console_login.exp << EOL
#!/usr/bin/expect -f
spawn sudo virsh console $VM_NAME
expect {
  "Escape character is" { sleep 1; send "\r" }
}
expect {
  "login:" { send "ubuntu\r" }
}
expect {
  "Password:" { send "ubuntu\r" }
}
expect {
  "ubuntu@" {
    send "ip a\r"
    expect "ubuntu@"
    send "sudo dhclient -v enp1s0\r"
    expect "ubuntu@"
    send "sudo systemctl status systemd-networkd\r"
    expect "ubuntu@"
    send "sudo systemctl status sshd\r"
    expect "ubuntu@"
    send "sudo cat /etc/ssh/sshd_config | grep PasswordAuthentication\r"
  }
  timeout {
    send_user "Failed to login to console\n"
  }
}
expect {
  "ubuntu@" {
    send "exit\r"
  }
}
EOL
      chmod +x /tmp/console_login.exp
      echo "[preinstall.sh] Running automated console login..."
      /usr/bin/expect -f /tmp/console_login.exp
    fi
  else
    echo "[preinstall.sh] Waiting 15 seconds before next check..."
    sleep 15
  fi

  ATTEMPT=$((ATTEMPT + 1))
done

echo "[preinstall.sh] Script completed. Manual steps if needed:"
echo "1. Access console: sudo virsh console $VM_NAME"
echo "2. Login with: ubuntu / ubuntu"
echo "3. Check network: ip a"
echo "4. Force DHCP: sudo dhclient -v"
echo "5. Check SSH: systemctl status sshd"