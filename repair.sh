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

# Helper: automatyczna naprawa sieci VM
repair_vm_network() {
  log "[NET] Sprawdzam status sieci libvirt..."
  if sudo virsh net-info default | grep -q 'Active: yes'; then
    log_ok "Sieć default aktywna."
  else
    log_warn "Sieć default nieaktywna. Próbuję uruchomić..."
    sudo virsh net-start default || log_err "Nie udało się uruchomić sieci default!"
    sudo virsh net-autostart default
  fi
  # Sprawdź interfejs virbr0
  log "[NET] Sprawdzam interfejs virbr0 na hoście..."
  ip a s virbr0 || log_warn "Brak interfejsu virbr0! Sieć NAT libvirt nie działa prawidłowo."

  # Sprawdź plik default.xml
  if [ ! -f /etc/libvirt/qemu/networks/default.xml ]; then
    log_warn "Brak pliku default.xml. Tworzę domyślną konfigurację..."
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || log_err "Nie udało się odtworzyć default.xml!"
  fi

  # Sprawdź czy działa dnsmasq
  if ! pgrep dnsmasq >/dev/null; then
    log_warn "dnsmasq nie działa, próbuję uruchomić..."
    sudo systemctl restart libvirtd || log_err "Nie udało się zrestartować libvirtd!"
  else
    log_ok "dnsmasq działa."
  fi

  # Sprawdź plik default.leases
  if [ ! -f /var/lib/libvirt/dnsmasq/default.leases ]; then
    log_warn "Brak pliku default.leases — VM nie pobrała adresu IP."
  else
    log_ok "Plik default.leases istnieje."
  fi

  # Sprawdź czy VM ma IP
  VM_IP=$(sudo virsh domifaddr safetytwin-vm | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
  if [ -z "$VM_IP" ]; then
    log_warn "VM nie uzyskała adresu IP, próbuję naprawić konfigurację sieci w cloud-init..."
    # Dodaj domyślną konfigurację netplan/cloud-init
    if ! grep -q 'network:' /var/lib/safetytwin/cloud-init/user-data; then
      echo -e '\nnetwork:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: true' | sudo tee -a /var/lib/safetytwin/cloud-init/user-data
      log_ok "Dodano domyślną konfigurację sieci do user-data."
    fi
    # Spróbuj zrestartować VM
    sudo virsh reset safetytwin-vm || sudo virsh reboot safetytwin-vm
    sleep 5
    VM_IP=$(sudo virsh domifaddr safetytwin-vm | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
    if [ -z "$VM_IP" ]; then
      log_err "VM nadal nie uzyskała adresu IP. Wymagana ręczna diagnostyka."
    else
      log_ok "VM uzyskała adres IP: $VM_IP"
    fi
  else
    log_ok "VM ma adres IP: $VM_IP"
  fi
}

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
  if virsh net-info default | grep -q 'Active: yes'; then
    log_ok "Sieć 'default' aktywna."
  else
    log_warn "Sieć 'default' nieaktywna. Próbuję uruchomić..."
    virsh net-start default
    virsh net-autostart default
  fi
  log "[NET] Sprawdzam interfejs virbr0 na hoście..."
  ip a s virbr0 || log_warn "Brak interfejsu virbr0! Sieć NAT libvirt nie działa prawidłowo."

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
  if virsh net-info default | grep -q 'Active: yes'; then
    log_ok "Sieć 'default' aktywna."
  else
    log_warn "Sieć 'default' nieaktywna. Próbuję uruchomić..."
    virsh net-start default
    virsh net-autostart default
  fi
  log "[NET] Sprawdzam interfejs virbr0 na hoście..."
  ip a s virbr0 || log_warn "Brak interfejsu virbr0! Sieć NAT libvirt nie działa prawidłowo."

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
for f in /etc/safetytwin/agent-config.json /etc/safetytwin/bridge-config.yaml /etc/safetytwin/ssh/id_rsa /etc/safetytwin/ssh/id_rsa.pub /etc/safetytwin/inventory.yml services/safetytwin-agent.service /etc/systemd/system/safetytwin-bridge.service /var/lib/safetytwin/cloud-init/user-data /var/lib/safetytwin/cloud-init/meta-data /var/lib/safetytwin/images/ubuntu-base.img /var/lib/safetytwin/vm-definition.xml; do
  repair_file "$f" file
done

# Usługi
repair_service services/safetytwin-agent.service
repair_service services/safetytwin-bridge.service
repair_service libvirtd.service

# Cron monitoring
repair_cron

# VM
repair_vm

# Automatyczna detekcja i naprawa konfiguracji sieci VM (interfejs, netplan, cloud-init)
fix_vm_network_config() {
  log "[AUTO] Detekcja nazwy interfejsu sieciowego w VM..."
  IFACE_NAME=$(sudo virsh console safetytwin-vm <<EOF | grep -E '^[0-9]+: ' | grep -v 'lo:' | head -n1 | awk -F: '{print $2}' | xargs
sleep 2
ip link
exit
EOF
)
  if [ -z "$IFACE_NAME" ]; then
    log_err "Nie udało się wykryć interfejsu VM! Ręczna interwencja wymagana."
    return 1
  fi
  log_ok "Wykryto interfejs VM: $IFACE_NAME"
  # Popraw user-data jeśli trzeba
  sudo sed -i "s/eth0:/$IFACE_NAME:/g" /var/lib/safetytwin/cloud-init/user-data
  # Dodaj domyślną konfigurację netplan w VM
  log "[AUTO] Tworzę domyślny plik netplan w VM dla $IFACE_NAME..."
  sudo virsh console safetytwin-vm <<EOF
sleep 2
cat <<NETPLAN | sudo tee /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    $IFACE_NAME:
      dhcp4: true
NETPLAN
netplan apply
dhclient -v $IFACE_NAME
exit
EOF
  log_ok "Wymuszono ponowną konfigurację sieci w VM ($IFACE_NAME)."
}

# Wykonaj naprawę sieci VM (host) i automatyczną detekcję/interfejs
repair_vm_network
fix_vm_network_config

# Diagnostyka VM i zapis do TWIN.yaml
repair_twin_diagnostics() {
  log "[TWIN] Zbieram diagnostykę z VM i zapisuję do /var/lib/safetytwin/TWIN.yaml..."
  # Zamknij aktywną sesję virsh console jeśli istnieje
  if sudo virsh console safetytwin-vm --force 2>/dev/null | grep -q 'Closed console session'; then
    log_ok "Zamknięto aktywną sesję virsh console."
  else
    log_warn "Nie wykryto aktywnej sesji lub nie udało się zamknąć konsoli. Jeśli nadal występuje problem, zamknij ręcznie: Ctrl + ] lub sudo virsh reset safetytwin-vm."
  fi
  OUT=/var/lib/safetytwin/TWIN.yaml
  echo "# Diagnostyka VM Safetytwin" > "$OUT"

  run_vm_diag() {
    local label="$1"
    local cmd="$2"
    echo "$label: |" >> "$OUT"
    local result
    result=$(sudo timeout 10 virsh console safetytwin-vm <<EOF
sleep 2
$cmd
exit
EOF
 2>&1 | sed 's/^/  /')
    if echo "$result" | grep -q "Escape character is"; then
      # Konsola się otworzyła, ale czy polecenie dało wynik?
      local filtered=$(echo "$result" | grep -v "Escape character is" | grep -v "Connected to domain" | grep -v "Press ^"]" | grep -v "^$" | tail -n +2)
      if [ -z "$filtered" ]; then
        echo "  [BŁĄD] Brak danych z VM lub polecenie nie powiodło się." >> "$OUT"
        echo "  [INSTRUKCJA] Zaloguj się ręcznie: sudo virsh console safetytwin-vm, potem: $cmd" >> "$OUT"
        log_warn "Nie udało się zebrać danych dla: $label. Sprawdź ręcznie."
      else
        echo "$filtered" >> "$OUT"
        log_ok "Zebrano dane: $label."
      fi
    else
      echo "  [BŁĄD] Nie można połączyć się z VM przez virsh console." >> "$OUT"
      echo "  [INSTRUKCJA] Zaloguj się ręcznie: sudo virsh console safetytwin-vm, potem: $cmd" >> "$OUT"
      log_warn "Nie udało się połączyć z VM dla: $label. Sprawdź ręcznie."
    fi
  }

  run_vm_diag "ip_a" "ip a"
  run_vm_diag "netplan" "cat /etc/netplan/*.yaml"
  run_vm_diag "cloud_init_log" "cat /var/log/cloud-init.log | tail -30"
  run_vm_diag "cloud_init_status" "cloud-init status"
  run_vm_diag "systemd_networkd_status" "systemctl status systemd-networkd"
  run_vm_diag "hostname" "hostname"
  run_vm_diag "resolv_conf" "cat /etc/resolv.conf"

  log_ok "Zapisano diagnostykę VM do $OUT. Jeśli któraś sekcja zawiera [BŁĄD], wykonaj polecenie ręcznie w VM."
}


repair_twin_diagnostics

# Podsumowanie naprawy
log_ok "Naprawa zakończona. Sprawdź ponownie INSTALL_RESULT.yaml oraz TWIN.yaml."
log "--- RAPORT NAPRAWY ---"
log "Katalogi, pliki, usługi, cron oraz sieć VM zostały sprawdzone i naprawione (jeśli było to możliwe)."
log "Jeśli nadal występują problemy, sprawdź logi: /var/log/safetytwin/ oraz uruchom diagnose-vm-network.sh dla pogłębionej diagnostyki."
