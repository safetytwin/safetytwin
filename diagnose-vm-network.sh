#!/bin/bash
# diagnose-vm-network.sh
# Diagnostyka sieci VM (libvirt, cloud-init, dnsmasq)
set -euo pipefail

VM_NAME="safetytwin-vm"
NET_NAME="default"
USER_DATA="/var/lib/safetytwin/cloud-init/user-data"

log() { echo -e "[DIAG] $1"; }

log "--- 1. Status sieci libvirt ---"
sudo virsh net-list --all
sudo virsh net-info "$NET_NAME"

log "--- 2. Konfiguracja sieci (default.xml) ---"
sudo cat /etc/libvirt/qemu/networks/default.xml || true

log "--- 3. Lista interfejsów VM ---"
sudo virsh domiflist "$VM_NAME"

log "--- 4. Procesy dnsmasq ---"
ps aux | grep dnsmasq

log "--- 5. Pliki DHCP leases ---"
sudo ls -l /var/lib/libvirt/dnsmasq/
sudo cat /var/lib/libvirt/dnsmasq/default.leases || echo "[BRAK pliku default.leases]"

log "--- 6. Logi libvirtd ---"
sudo journalctl -u libvirtd -n 30

log "--- 7. Plik user-data ---"
sudo cat "$USER_DATA"

log "--- 8. Konsola VM: stan interfejsów ---"
sudo virsh console "$VM_NAME" <<EOF
sleep 2
ip a
cat /etc/netplan/*.yaml
cat /run/cloud-init/network-config
systemctl status systemd-networkd || systemctl status NetworkManager
journalctl -u cloud-init -n 20
exit
EOF

log "--- 9. Cloud-init log (host) ---"
sudo cat /var/log/cloud-init.log | tail -n 30 || true

log "--- DIAGNOSTYKA ZAKOŃCZONA ---"
