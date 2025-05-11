#!/bin/bash
# repair.sh - automatyczna naprawa systemu safetytwin na bazie INSTALL_RESULT.yaml
# Użycie: sudo bash repair.sh [INSTALL_RESULT.yaml]

set -e
YAML_FILE="${1:-INSTALL_RESULT.yaml}"

if [ ! -f "$YAML_FILE" ]; then
  echo "Brak pliku $YAML_FILE!"
  exit 1
fi

log() { echo -e "\033[1;34m[REPAIR]\033[0m $1"; }
log_ok() { echo -e "\033[1;32m[OK]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_err() { echo -e "\033[1;31m[ERR]\033[0m $1"; }

# Helper: sprawdź i napraw plik/katalog
repair_file() {
  local path="$1"
  local type="$2" # file/dir
  if [ "$type" = "dir" ]; then
    if [ ! -d "$path" ]; then
      log_warn "Tworzę katalog: $path"
      mkdir -p "$path"
    else
      log_ok "Katalog istnieje: $path"
    fi
  else
    if [ ! -f "$path" ]; then
      log_warn "Brak pliku: $path (ręczna interwencja wymagana)"
    else
      log_ok "Plik istnieje: $path"
    fi
  fi
}

# Helper: restart usługi jeśli nieaktywna
repair_service() {
  local svc="$1"
  if ! systemctl is-active --quiet "$svc"; then
    log_warn "Usługa $svc nieaktywna, próbuję uruchomić..."
    systemctl daemon-reload
    systemctl enable --now "$svc" && log_ok "Usługa $svc uruchomiona." || log_err "Nie udało się uruchomić $svc!"
  else
    log_ok "Usługa aktywna: $svc"
  fi
}

# Helper: dodaj cron jeśli brak
repair_cron() {
  if ! crontab -l 2>/dev/null | grep -q '/usr/local/bin/monitor_storage.sh'; then
    log_warn "Dodaję zadanie monitoringu storage do crona."
    (crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/monitor_storage.sh >> /var/log/safetytwin/storage.log 2>&1") | crontab -
    log_ok "Zadanie crona dodane."
  else
    log_ok "Cron monitoringu storage już istnieje."
  fi
}

# Helper: napraw VM jeśli nie działa
repair_vm() {
  if ! virsh list --all | grep -q safetytwin-vm; then
    log_warn "VM nie jest zdefiniowana. Próba definicji..."
    if [ -f /var/lib/safetytwin/vm-definition.xml ]; then
      virsh define /var/lib/safetytwin/vm-definition.xml && log_ok "VM zdefiniowana." || log_err "Nie udało się zdefiniować VM!"
    else
      log_err "Brak pliku vm-definition.xml!"
    fi
  fi
  if ! virsh list --state-running | grep -q safetytwin-vm; then
    log_warn "VM nie jest uruchomiona. Próba uruchomienia..."
    virsh start safetytwin-vm && log_ok "VM uruchomiona." || log_err "Nie udało się uruchomić VM!"
  else
    log_ok "VM uruchomiona."
  fi
  # Diagnostyka sieci VM
  log "[AUTO-FIX] Diagnostyka sieci VM..."
  virsh domiflist safetytwin-vm || true
  virsh net-list --all || true
  virsh net-info default || true
  cat /var/lib/libvirt/dnsmasq/default.leases || true
  # Naprawa podłączenia do sieci
  if ! virsh domiflist safetytwin-vm | grep -q default; then
    log_warn "VM nie jest podłączona do sieci 'default'. Próbuję naprawić..."
    virsh detach-interface safetytwin-vm --type network --mac $(virsh domiflist safetytwin-vm | awk '/network/ {print $5}') --persistent || true
    virsh attach-interface safetytwin-vm network default --model virtio --config --live || true
    log_ok "Podłączono VM do sieci 'default'."
  fi
  if ! virsh net-info default | grep -q 'Active: yes'; then
    log_warn "Sieć 'default' nieaktywna. Próbuję uruchomić..."
    virsh net-start default
    virsh net-autostart default
  fi
  # Naprawa user-data
  if ! grep -q 'network:' /var/lib/safetytwin/cloud-init/user-data; then
    log_warn "Dodaję domyślną konfigurację sieci do user-data."
    echo -e '\nnetwork:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: true' >> /var/lib/safetytwin/cloud-init/user-data
  fi
  sleep 5
  IP_VM=$(cat /var/lib/libvirt/dnsmasq/default.leases | grep $(virsh domiflist safetytwin-vm | awk '/network/ {print $5}') | awk '{print $3}')
  if [ -z "$IP_VM" ]; then
    log_err "Nie można uzyskać adresu IP VM. Wykonaj ręcznie diagnostykę:\n  sudo virsh domiflist safetytwin-vm\n  sudo virsh net-list --all\n  sudo virsh net-info default\n  sudo cat /var/lib/libvirt/dnsmasq/default.leases\n  sudo virsh console safetytwin-vm\n  sudo cat /var/lib/safetytwin/cloud-init/user-data"
  else
    log_ok "VM ma adres IP: $IP_VM"
  fi
}

# Helper: dodaj automatyczną naprawę sieci VM
repair_vm_network() {
  # Diagnostyka sieci VM
  log "[AUTO-FIX] Diagnostyka sieci VM..."
  virsh domiflist safetytwin-vm || true
  virsh net-list --all || true
  virsh net-info default || true
  cat /var/lib/libvirt/dnsmasq/default.leases || true
  # Naprawa podłączenia do sieci
  if ! virsh domiflist safetytwin-vm | grep -q default; then
    log_warn "VM nie jest podłączona do sieci 'default'. Próbuję naprawić..."
    virsh detach-interface safetytwin-vm --type network --mac $(virsh domiflist safetytwin-vm | awk '/network/ {print $5}') --persistent || true
    virsh attach-interface safetytwin-vm network default --model virtio --config --live || true
    log_ok "Podłączono VM do sieci 'default'."
  fi
  if ! virsh net-info default | grep -q 'Active: yes'; then
    log_warn "Sieć 'default' nieaktywna. Próbuję uruchomić..."
    virsh net-start default
    virsh net-autostart default
  fi
  # Naprawa user-data
  if ! grep -q 'network:' /var/lib/safetytwin/cloud-init/user-data; then
    log_warn "Dodaję domyślną konfigurację sieci do user-data."
    echo -e '\nnetwork:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: true' >> /var/lib/safetytwin/cloud-init/user-data
  fi
  sleep 5
  IP_VM=$(cat /var/lib/libvirt/dnsmasq/default.leases | grep $(virsh domiflist safetytwin-vm | awk '/network/ {print $5}') | awk '{print $3}')
  if [ -z "$IP_VM" ]; then
    log_err "Nie można uzyskać adresu IP VM. Wykonaj ręcznie diagnostykę:\n  sudo virsh domiflist safetytwin-vm\n  sudo virsh net-list --all\n  sudo virsh net-info default\n  sudo cat /var/lib/libvirt/dnsmasq/default.leases\n  sudo virsh console safetytwin-vm\n  sudo cat /var/lib/safetytwin/cloud-init/user-data"
  else
    log_ok "VM ma adres IP: $IP_VM"
  fi
}

log "Analizuję $YAML_FILE..."

# Katalogi
for dir in /var/lib/safetytwin /etc/safetytwin /var/log/safetytwin /var/lib/safetytwin/images /etc/safetytwin/ssh; do
  repair_file "$dir" dir
done

# --- TWORZENIE DOMYŚLNYCH PLIKÓW KONFIGURACYJNYCH ---
create_default_file() {
  local path="$1"
  local content="$2"
  if [ ! -f "$path" ]; then
    echo "$content" > "$path"
    log "[AUTO-FIX] Utworzono domyślny plik: $path"
  fi
}

create_default_file "/etc/safetytwin/agent-config.json" '{
  "agent_id": "default-agent",
  "log_level": "info",
  "monitor_interval": 30,
  "bridge_url": "http://localhost:8080",
  "hardware_monitoring": true,
  "service_monitoring": true,
  "process_monitoring": true
}'

create_default_file "/etc/safetytwin/bridge-config.yaml" 'bridge:
  listen: 0.0.0.0:8080
  log_level: info
  agent_auth: false
  storage_dir: /var/lib/safetytwin/bridge
  allowed_agents:
    - default-agent
'

create_default_file "/etc/safetytwin/inventory.yml" 'all:
  hosts:
    safetytwin-vm:
      ansible_host: 192.168.122.100
      ansible_user: ubuntu
      ansible_ssh_private_key_file: /etc/safetytwin/ssh/id_rsa
  vars:
    ansible_python_interpreter: /usr/bin/python3
'
# --- KONIEC TWORZENIA DOMYŚLNYCH PLIKÓW ---

# Pliki kluczowe (nie nadpisujemy, tylko ostrzegamy jeśli brak)
for f in /etc/safetytwin/agent-config.json /etc/safetytwin/bridge-config.yaml /etc/safetytwin/ssh/id_rsa /etc/safetytwin/ssh/id_rsa.pub /etc/safetytwin/inventory.yml /etc/systemd/system/safetytwin-agent.service /etc/systemd/system/safetytwin-bridge.service /var/lib/safetytwin/cloud-init/user-data /var/lib/safetytwin/cloud-init/meta-data /var/lib/safetytwin/images/ubuntu-base.img /var/lib/safetytwin/vm-definition.xml; do
  repair_file "$f" file
done

# Usługi
repair_service safetytwin-agent.service
repair_service safetytwin-bridge.service
repair_service libvirtd.service

# Cron monitoring
repair_cron

# VM
repair_vm

log_ok "Naprawa zakończona. Sprawdź ponownie INSTALL_RESULT.yaml."
