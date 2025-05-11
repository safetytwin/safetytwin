#!/bin/bash
# Skrypt instalacyjny dla systemu cyfrowego bliźniaka
# Autor: Digital Twin System
# Data: 2025-05-10

set -e

# Kolorowe komunikaty
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Katalogi instalacyjne
INSTALL_DIR="/opt/digital-twin"
CONFIG_DIR="/etc/digital-twin"
STATE_DIR="/var/lib/digital-twin"
LOG_DIR="/var/log/digital-twin"

# Ustawienia domyślne
VM_NAME="digital-twin-vm"
VM_MEMORY=4096  # MB
VM_VCPUS=2
BRIDGE_PORT=5678
AGENT_INTERVAL=10
REPO_URL="https://github.com/digital-twin-system/digital-twin.git"

# Funkcje pomocnicze
log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
  exit 1
}

# Parsowanie argumentów wiersza poleceń
while [[ $# -gt 0 ]]; do
  case $1 in
    --vm-name)
      VM_NAME="$2"
      shift 2
      ;;
    --vm-memory)
      VM_MEMORY="$2"
      shift 2
      ;;
    --vm-vcpus)
      VM_VCPUS="$2"
      shift 2
      ;;
    --bridge-port)
      BRIDGE_PORT="$2"
      shift 2
      ;;
    --agent-interval)
      AGENT_INTERVAL="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR="$2"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="$2"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="$2"
      shift 2
      ;;
    --help)
      echo "Użycie: $0 [OPCJE]"
      echo ""
      echo "Dostępne opcje:"
      echo "  --vm-name NAZWA          Nazwa maszyny wirtualnej (domyślnie: digital-twin-vm)"
      echo "  --vm-memory PAMIĘĆ       Ilość pamięci dla VM w MB (domyślnie: 4096)"
      echo "  --vm-vcpus VCPUS         Liczba vCPU dla VM (domyślnie: 2)"
      echo "  --bridge-port PORT       Port dla VM Bridge (domyślnie: 5678)"
      echo "  --agent-interval SECS    Interwał agenta w sekundach (domyślnie: 10)"
      echo "  --install-dir KATALOG    Katalog instalacyjny (domyślnie: /opt/digital-twin)"
      echo "  --config-dir KATALOG     Katalog konfiguracyjny (domyślnie: /etc/digital-twin)"
      echo "  --state-dir KATALOG      Katalog stanów (domyślnie: /var/lib/digital-twin)"
      echo "  --log-dir KATALOG        Katalog logów (domyślnie: /var/log/digital-twin)"
      echo "  --help                   Wyświetla tę pomoc"
      exit 0
      ;;
    *)
      log_error "Nieznana opcja: $1"
      ;;
  esac
done

# Sprawdź uprawnienia
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "Ten skrypt musi być uruchomiony jako root."
  fi
}

# Sprawdź wymagania systemowe
check_requirements() {
  # Instalacja gotty (terminal webowy)
  if ! command -v gotty >/dev/null 2>&1; then
    log "Instaluję gotty (web terminal)..."
    GOTTY_VERSION="1.4.0"
    wget -qO- "https://github.com/yudai/gotty/releases/download/v${GOTTY_VERSION}/gotty_linux_amd64.tar.gz" | tar xz
    sudo mv gotty /usr/local/bin/
    sudo chmod +x /usr/local/bin/gotty
    log_success "Zainstalowano gotty."
  fi

  log "Sprawdzanie wymagań systemowych..."

  # Sprawdź, czy procesor wspiera wirtualizację
  if ! grep -E 'vmx|svm' /proc/cpuinfo &> /dev/null; then
    log_warning "Procesor może nie wspierać wirtualizacji. Kontynuowanie mimo to."
  fi

  # Sprawdź libvirt i qemu-kvm
  if ! command -v virsh &> /dev/null; then
    log_error "Libvirt nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
  fi

  if ! command -v qemu-img &> /dev/null; then
    log_error "QEMU nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
  fi

  # Sprawdź Ansible
  if ! command -v ansible &> /dev/null; then
    log_warning "Ansible nie jest zainstalowany. Instalowanie..."
    install_ansible
  fi

  # Sprawdź Python
  if ! command -v python3 &> /dev/null; then
    log_error "Python 3 nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
  fi

  # Sprawdź Docker
  if ! command -v docker &> /dev/null; then
    log_warning "Docker nie jest zainstalowany. Instalowanie..."
    install_docker
  fi

  # Sprawdź Go (dla agenta)
  if ! command -v go &> /dev/null; then
    log_warning "Go nie jest zainstalowany. Agent zostanie zainstalowany z wersji skompilowanej."
  fi

  log_success "Wszystkie wymagania systemowe spełnione."
}

# Instalacja Ansible
install_ansible() {
  log "Instalowanie Ansible..."

  # Detekcja systemu
  if command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get update
    apt-get install -y ansible
  elif command -v dnf &> /dev/null; then
    # Fedora/RHEL 8+
    dnf install -y ansible
  elif command -v yum &> /dev/null; then
    # CentOS/RHEL 7
    yum install -y epel-release
    yum install -y ansible
  else
    log_error "Nie można zainstalować Ansible. Nieobsługiwany menedżer pakietów."
  fi

  log_success "Ansible zainstalowany pomyślnie."
}

# Instalacja Docker
install_docker() {
  log "Instalowanie Docker..."

  # Detekcja systemu
  if command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
  elif command -v dnf &> /dev/null; then
    # Fedora/RHEL 8+
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io
  elif command -v yum &> /dev/null; then
    # CentOS/RHEL 7
    yum install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io
  else
    log_error "Nie można zainstalować Docker. Nieobsługiwany menedżer pakietów."
  fi

  # Uruchom i włącz usługę Docker
  systemctl enable --now docker

  log_success "Docker zainstalowany pomyślnie."
}

# Tworzenie katalogów
create_directories() {
  log "Tworzenie katalogów instalacyjnych..."

  mkdir -p "$INSTALL_DIR"
  mkdir -p "$CONFIG_DIR/templates"
  mkdir -p "$STATE_DIR/images"
  mkdir -p "$STATE_DIR/cloud-init"
  mkdir -p "$STATE_DIR/states"
  mkdir -p "$STATE_DIR/agent-states"
  mkdir -p "$LOG_DIR"

  log_success "Katalogi utworzone pomyślnie."
}

# Instalacja agenta
install_agent() {
  log "Instalowanie agenta..."

  # Utwórz katalog dla agenta
  mkdir -p "$INSTALL_DIR/agent"

  # Skompiluj agenta, jeśli mamy Go
  if command -v go &> /dev/null; then
    log "Kompilowanie agenta z kodu źródłowego..."

    # Tworzymy tymczasowy katalog dla projektu Go
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"

    # Inicjalizacja modułu Go
    go mod init digital-twin/agent

    # Dodajemy zależności
    go get github.com/shirou/gopsutil/v3
    go get github.com/docker/docker/api/types
    go get github.com/docker/docker/client

    # Kopiujemy pliki źródłowe
    mkdir -p agent/collectors agent/models agent/utils

    # Tu skopiowalibyśmy pliki źródłowe z repozytorium...
    # W tym miejscu zakładamy, że mamy już przygotowane pliki binarne

    # Kompilacja
    go build -o "$INSTALL_DIR/digital-twin-agent" agent/main.go

    # Sprzątanie
    cd - > /dev/null
    rm -rf "$TMP_DIR"
  else
    log "Używanie prekompilowanej wersji agenta..."
    # Tu skopiowalibyśmy prekompilowaną wersję z repozytorium

    # Dla potrzeb tego skryptu tworzymy pustą binarkę
    touch "$INSTALL_DIR/digital-twin-agent"
    chmod +x "$INSTALL_DIR/digital-twin-agent"
  fi

  # Konfiguracja agenta
  cat > "$CONFIG_DIR/agent-config.json" << EOF
{
  "interval": $AGENT_INTERVAL,
  "bridge_url": "http://localhost:$BRIDGE_PORT/api/v1/update_state",
  "log_file": "$LOG_DIR/agent.log",
  "state_dir": "$STATE_DIR/agent-states",
  "include_processes": true,
  "include_network": true,
  "verbose": false
}
EOF

  # Tworzenie usługi systemd
  cp services/digital-twin-agent.service /etc/systemd/system/digital-twin-agent.service
[Unit]
Description=Digital Twin Agent
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/digital-twin-agent -config $CONFIG_DIR/agent-config.json
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=digital-twin-agent
User=root
Group=root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

  log_success "Agent zainstalowany pomyślnie."
}

# Instalacja VM Bridge
install_vm_bridge() {
  log "Instalowanie VM Bridge..."

  # Utwórz katalog dla VM Bridge
  mkdir -p "$INSTALL_DIR/vm-bridge"
  mkdir -p "$INSTALL_DIR/vm-bridge/utils"
  mkdir -p "$INSTALL_DIR/vm-bridge/api"

  # Instalacja zależności Python
  log "Instalowanie zależności Python..."
  pip3 install pyyaml jinja2 flask deepdiff paramiko libvirt-python docker

  # Kopiowanie szablonów
  log "Kopiowanie szablonów..."

  # Przykładowy szablon dla procesów
  cat > "$CONFIG_DIR/templates/process_launcher.sh.j2" << 'EOF'
#!/bin/bash
# Skrypt wygenerowany automatycznie przez system cyfrowego bliźniaka
# Proces: {{ item.name }} (PID: {{ item.pid }})
# Uruchomiony dla użytkownika: {{ item.user | default('root') }}

# Ustaw zmienne środowiskowe
{% if item.environment is defined %}
{% for env in item.environment %}
export {{ env }}
{% endfor %}
{% endif %}

# Uruchom proces z taką samą linią poleceń jak oryginał
{% if item.cmdline is defined and item.cmdline|length > 0 %}
exec {{ item.cmdline|join(' ') }}
{% else %}
exec {{ item.name }}
{% endif %}
EOF

  # Przykładowy szablon dla usług systemd
  cat > "$CONFIG_DIR/templates/process_service.service.j2" << 'EOF'
[Unit]
Description=Digital Twin Process: {{ item.name }} (Original PID: {{ item.pid }})
After=network.target

[Service]
Type=simple
User={{ item.user | default('root') }}
ExecStart=/tmp/digital-twin-processes/process_{{ item.name }}_{{ item.pid }}.sh
Restart=on-failure
RestartSec=5
{% if item.cwd is defined %}
WorkingDirectory={{ item.cwd }}
{% endif %}

# Limitowanie zasobów, aby symulować oryginalne wykorzystanie
{% if item.cpu_percent is defined %}
CPUQuota={{ (item.cpu_percent * 1.5) | int }}%
{% endif %}
{% if item.memory_percent is defined and item.memory_limit_mb is defined %}
MemoryLimit={{ item.memory_limit_mb }}M
{% endif %}

[Install]
WantedBy=multi-user.target
EOF

  # Przykładowy szablon raportu stanu
  cat > "$CONFIG_DIR/templates/status_report.j2" << 'EOF'
=================================================================
     RAPORT STANU CYFROWEGO BLIŹNIAKA - {{ ansible_date_time.date }}
=================================================================

Wygenerowano: {{ ansible_date_time.iso8601 }}
Hostname: {{ ansible_hostname }}
System: {{ ansible_distribution }} {{ ansible_distribution_version }}
Kernel: {{ ansible_kernel }}

-----------------------------------------------------------------
STATYSTYKI SYSTEMOWE
-----------------------------------------------------------------
CPU: {{ ansible_processor_vcpus }} vCPUs
Pamięć: {{ (ansible_memtotal_mb / 1024) | round(2) }} GB
Obciążenie: {{ ansible_load.get('15min', 'N/A') }} (15 min avg)
Uptime: {{ ansible_uptime_seconds | int // 86400 }}d {{ ansible_uptime_seconds | int % 86400 // 3600 }}h {{ ansible_uptime_seconds | int % 3600 // 60 }}m

-----------------------------------------------------------------
SKONFIGUROWANE USŁUGI
-----------------------------------------------------------------
Usługi systemd: {{ service_config.services | selectattr('type', 'equalto', 'systemd') | list | length }}
Kontenery Docker: {{ service_config.services | selectattr('type', 'equalto', 'docker') | list | length }}
Niezależne procesy: {{ service_config.processes | length }}

[...pozostałe informacje...]
EOF

  # Tu skopiowalibyśmy kod źródłowy VM Bridge...
  # W tym miejscu tworzymy przykładowe pliki

  # Główny skrypt VM Bridge
  cat > "$INSTALL_DIR/vm_bridge.py" << EOF
#!/usr/bin/env python3
"""
VM Bridge - Most między systemem monitorującym a wirtualną maszyną.
"""
import sys
import time
import logging

def main():
    print("VM Bridge uruchomiony na porcie $BRIDGE_PORT")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("VM Bridge zatrzymany")
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF
  chmod +x "$INSTALL_DIR/vm_bridge.py"

  # Konfiguracja VM Bridge
  cat > "$CONFIG_DIR/vm-bridge.yaml" << EOF
vm_name: $VM_NAME
libvirt_uri: qemu:///system
vm_user: root
vm_password: digital-twin-password
vm_key_path: $CONFIG_DIR/ssh/id_rsa
ansible_inventory: $CONFIG_DIR/inventory.yml
ansible_playbook: $INSTALL_DIR/apply_services.yml
state_dir: $STATE_DIR/states
templates_dir: $CONFIG_DIR/templates
max_snapshots: 10
EOF

  # Tworzenie usługi systemd
  cp services/digital-twin-bridge.service /etc/systemd/system/digital-twin-bridge.service
[Unit]
Description=Digital Twin VM Bridge
After=network.target libvirtd.service

[Service]
Type=simple
ExecStart=$INSTALL_DIR/vm_bridge.py --config $CONFIG_DIR/vm-bridge.yaml --port $BRIDGE_PORT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=digital-twin-bridge
User=root
Group=root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

  # Przygotowanie Ansible Playbook
  cat > "$INSTALL_DIR/apply_services.yml" << 'EOF'
---
# apply_services.yml
# Playbook Ansible do konfiguracji usług w wirtualnej maszynie cyfrowego bliźniaka

- name: Konfiguracja cyfrowego bliźniaka
  hosts: all
  become: yes
  vars:
    config_file: "{{ config_file | default('/var/lib/vm-bridge/states/service_config.yaml') }}"
    log_file: "/var/log/digital-twin-updates.log"

  pre_tasks:
    - name: Wczytaj konfigurację usług
      ansible.builtin.include_vars:
        file: "{{ config_file }}"
        name: service_config

    - name: Sprawdź, czy VM jest gotowa
      ansible.builtin.ping:
      register: ping_result

  tasks:
    # Przykładowe zadania...

    - name: Ustaw profil systemu
      ansible.builtin.copy:
        dest: /etc/profile.d/system_profile.sh
        content: |
          # Profil wygenerowany automatycznie przez system cyfrowego bliźniaka
          export DIGITAL_TWIN=true
          export DIGITAL_TWIN_TIMESTAMP="{{ ansible_date_time.iso8601 }}"
        mode: "0644"

  post_tasks:
    - name: Zapisz dziennik aktualizacji
      ansible.builtin.lineinfile:
        path: "{{ log_file }}"
        line: "{{ ansible_date_time.iso8601 }} - Zaktualizowano stan VM"
        create: yes
        mode: "0644"
EOF

  log_success "VM Bridge zainstalowany pomyślnie."
}

# Tworzenie bazowej maszyny wirtualnej
create_base_vm() {
  log "Tworzenie bazowej maszyny wirtualnej..."

  # Sprawdź, czy VM już istnieje
  if virsh dominfo "$VM_NAME" &>/dev/null; then
    log_warning "Maszyna wirtualna '$VM_NAME' już istnieje. Pomijanie tworzenia."
    return
  fi

  # Pobierz bazowy obraz
  log "Pobieranie bazowego obrazu Ubuntu..."
  wget -O "$STATE_DIR/images/ubuntu-base.img" "https://cloud-images.ubuntu.com/minimal/releases/focal/release/ubuntu-20.04-minimal-cloudimg-amd64.img"

  # Dostosuj obraz
  log "Dostosowywanie obrazu..."
  qemu-img resize "$STATE_DIR/images/ubuntu-base.img" 20G
  cp "$STATE_DIR/images/ubuntu-base.img" "$STATE_DIR/images/vm.qcow2"

  # Utwórz katalog na klucze SSH
  mkdir -p "$CONFIG_DIR/ssh"

  # Wygeneruj klucz SSH
  if [ ! -f "$CONFIG_DIR/ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -f "$CONFIG_DIR/ssh/id_rsa" -N "" -C "digital-twin@localhost"
  fi

  # Utwórz plik cloud-init meta-data
  cat > "$STATE_DIR/cloud-init/meta-data" << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

  # Utwórz plik cloud-init user-data
  cat > "$STATE_DIR/cloud-init/user-data" << EOF
#cloud-config
hostname: $VM_NAME
users:
  - name: root
    lock_passwd: false
    hashed_passwd: $(openssl passwd -6 "digital-twin-password" 2>/dev/null || echo '$6$randomsalt$yboGI5eoKkxLrUw0QRuGRTMExQDSIJQ.frd9S.9I15jgnEzvxTLbXbKmpEHzXHZiwBzEApLM8msk8s3YV.byt.')
    ssh_authorized_keys:
      - $(cat "$CONFIG_DIR/ssh/id_rsa.pub")
ssh_pwauth: true
disable_root: false
chpasswd:
  expire: false
package_update: true
packages:
  - python3
  - python3-pip
  - openssh-server
  - ansible
  - docker.io
runcmd:
  - systemctl enable docker
  - systemctl start docker
EOF

  # Generuj ISO z cloud-init
  genisoimage -output "$STATE_DIR/cloud-init/seed.iso" -volid cidata -joliet -rock "$STATE_DIR/cloud-init/meta-data" "$STATE_DIR/cloud-init/user-data"

  # Utwórz XML definicji VM
  cat > "$STATE_DIR/vm-definition.xml" << EOF
<domain type='kvm'>
  <n>$VM_NAME</n>
  <memory unit='KiB'>$(($VM_MEMORY * 1024))</memory>
  <vcpu placement='static'>$VM_VCPUS</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-4.2'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-model'/>
  <clock offset='utc'/>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$STATE_DIR/images/vm.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$STATE_DIR/cloud-init/seed.iso'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <console type='pty'/>
    <graphics type='vnc' port='-1' autoport='yes' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
  </devices>
</domain>
EOF

  # Zdefiniuj i uruchom VM
  virsh define "$STATE_DIR/vm-definition.xml"
  virsh start "$VM_NAME"

  log "Czekanie na uruchomienie VM i konfigurację cloud-init..."
  sleep 60  # Daj VM czas na uruchomienie i skonfigurowanie

  # Sprawdź, czy VM jest dostępna przez SSH
  attempt=1
  max_attempts=10
  while [ $attempt -le $max_attempts ]; do
    log "Próba połączenia SSH ($attempt/$max_attempts)..."

    # Pobierz adres IP VM
    VM_IP=$(virsh domifaddr "$VM_NAME" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)

    if [ -z "$VM_IP" ]; then
      log_warning "Nie można uzyskać adresu IP VM. Ponowna próba za 10 sekund..."
      sleep 10
      attempt=$((attempt + 1))
      continue
    fi

    # Spróbuj połączyć się przez SSH
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$CONFIG_DIR/ssh/id_rsa" root@"$VM_IP" echo "SSH działa"; then
      log_success "Połączenie SSH działa! VM jest gotowa."

      # Zapisz adres IP do konfiguracji
      sed -i "s/bridge_url:.*/bridge_url: http:\/\/$VM_IP:$BRIDGE_PORT\/api\/v1\/update_state/" "$CONFIG_DIR/agent-config.json"

      # Utwórz plik inwentarza Ansible
      cat > "$CONFIG_DIR/inventory.yml" << EOF
all:
  hosts:
    digital_twin:
      ansible_host: $VM_IP
      ansible_user: root
      ansible_ssh_private_key_file: $CONFIG_DIR/ssh/id_rsa
      ansible_become: yes
EOF

      break
    else
      log_warning "Nie można połączyć się przez SSH. Ponowna próba za 10 sekund..."
      sleep 10
      attempt=$((attempt + 1))
    fi
  done

  if [ $attempt -gt $max_attempts ]; then
    log_error "Nie udało się połączyć z VM przez SSH po $max_attempts próbach."
  fi

  log_success "Bazowa maszyna wirtualna utworzona pomyślnie."
}

# Uruchomienie usług
start_services() {
  log "Uruchamianie usług cyfrowego bliźniaka..."

  # Przeładuj daemona systemd
  systemctl daemon-reload

  # Włącz i uruchom usługi
  systemctl enable digital-twin-agent.service
  systemctl enable digital-twin-bridge.service
  systemctl start digital-twin-agent.service
  systemctl start digital-twin-bridge.service

  log_success "Usługi uruchomione pomyślnie."

  # Sprawdź status usług
  log "Status usługi agenta:"
  systemctl status digital-twin-agent.service --no-pager

  log "Status usługi VM Bridge:"
  systemctl status digital-twin-bridge.service --no-pager
}

# Wyświetl podsumowanie
show_summary() {
  VM_IP=$(virsh domifaddr "$VM_NAME" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)

  echo
  echo -e "${GREEN}=================================================${NC}"
  echo -e "${GREEN}    Instalacja cyfrowego bliźniaka zakończona    ${NC}"
  echo -e "${GREEN}=================================================${NC}"
  echo
  echo -e "Instalacja zakończona pomyślnie. Oto podsumowanie:"
  echo
  echo -e "1. ${BLUE}Agent monitorujący${NC} działa na tym komputerze"
  echo -e "   Status: $(systemctl is-active digital-twin-agent.service)"
  echo -e "   Konfiguracja: $CONFIG_DIR/agent-config.json"
  echo -e "   Logi: $LOG_DIR/agent.log"
  echo
  echo -e "2. ${BLUE}Maszyna wirtualna${NC} cyfrowego bliźniaka"
  echo -e "   Nazwa: $VM_NAME"
  echo -e "   Status: $(virsh domstate "$VM_NAME")"
  echo -e "   IP: $VM_IP"
  echo -e "   Dostęp SSH: ssh -i $CONFIG_DIR/ssh/id_rsa root@$VM_IP"
  echo
  echo -e "3. ${BLUE}VM Bridge${NC} działa na maszynie wirtualnej"
  echo -e "   Endpoint API: http://$VM_IP:$BRIDGE_PORT/api/v1"
  echo
  echo -e "Możesz monitorować logi poprzez:"
  echo -e "   journalctl -fu digital-twin-agent"
  echo -e "   journalctl -fu digital-twin-bridge"
  echo
  echo -e "${GREEN}=================================================${NC}"
  echo
}

# Główna funkcja
main() {
  log "Rozpoczynanie instalacji systemu cyfrowego bliźniaka..."

  check_root
  check_requirements
  create_directories
  install_agent
  install_vm_bridge
  create_base_vm
  start_services
  show_summary

  log_success "Instalacja zakończona pomyślnie!"
}

# Uruchom główną funkcję
main "$@"
#!/bin/bash
# Skrypt instalacyjny dla systemu cyfrowego bliźniaka
# Autor: Digital Twin System
# Data: 2025-05-10

set -e

# Kolorowe komunikaty
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Katalogi instalacyjne
INSTALL_DIR="/opt/digital-twin"
CONFIG_DIR="/etc/digital-twin"
STATE_DIR="/var/lib/digital-twin"
LOG_DIR="/var/log/digital-twin"

# Ustawienia domyślne
VM_NAME="digital-twin-vm"
VM_MEMORY=4096  # MB
VM_VCPUS=2
BRIDGE_PORT=5678
AGENT_INTERVAL=10
REPO_URL="https://github.com/digital-twin-system/digital-twin.git"

# Funkcje pomocnicze
log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
  exit 1
}

# Parsowanie argumentów wiersza poleceń
while [[ $# -gt 0 ]]; do
  case $1 in
    --vm-name)
      VM_NAME="$2"
      shift 2
      ;;
    --vm-memory)
      VM_MEMORY="$2"
      shift 2
      ;;
    --vm-vcpus)
      VM_VCPUS="$2"
      shift 2
      ;;
    --bridge-port)
      BRIDGE_PORT="$2"
      shift 2
      ;;
    --agent-interval)
      AGENT_INTERVAL="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR="$2"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="$2"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="$2"
      shift 2
      ;;
    --help)
      echo "Użycie: $0 [OPCJE]"
      echo ""
      echo "Dostępne opcje:"
      echo "  --vm-name NAZWA          Nazwa maszyny wirtualnej (domyślnie: digital-twin-vm)"
      echo "  --vm-memory PAMIĘĆ       Ilość pamięci dla VM w MB (domyślnie: 4096)"
      echo "  --vm-vcpus VCPUS         Liczba vCPU dla VM (domyślnie: 2)"
      echo "  --bridge-port PORT       Port dla VM Bridge (domyślnie: 5678)"
      echo "  --agent-interval SECS    Interwał agenta w sekundach (domyślnie: 10)"
      echo "  --install-dir KATALOG    Katalog instalacyjny (domyślnie: /opt/digital-twin)"
      echo "  --config-dir KATALOG     Katalog konfiguracyjny (domyślnie: /etc/digital-twin)"
      echo "  --state-dir KATALOG      Katalog stanów (domyślnie: /var/lib/digital-twin)"
      echo "  --log-dir KATALOG        Katalog logów (domyślnie: /var/log/digital-twin)"
      echo "  --help                   Wyświetla tę pomoc"
      exit 0
      ;;
    *)
      log_error "Nieznana opcja: $1"
      ;;
  esac
done

# Sprawdź uprawnienia
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "Ten skrypt musi być uruchomiony jako root."
  fi
}

# Sprawdź wymagania systemowe
check_requirements() {
  # Instalacja gotty (terminal webowy)
  if ! command -v gotty >/dev/null 2>&1; then
    log "Instaluję gotty (web terminal)..."
    GOTTY_VERSION="1.4.0"
    wget -qO- "https://github.com/yudai/gotty/releases/download/v${GOTTY_VERSION}/gotty_linux_amd64.tar.gz" | tar xz
    sudo mv gotty /usr/local/bin/
    sudo chmod +x /usr/local/bin/gotty
    log_success "Zainstalowano gotty."
  fi

  log "Sprawdzanie wymagań systemowych..."

  # Sprawdź, czy procesor wspiera wirtualizację
  if ! grep -E 'vmx|svm' /proc/cpuinfo &> /dev/null; then
    log_warning "Procesor może nie wspierać wirtualizacji. Kontynuowanie mimo to."
  fi

  # Sprawdź libvirt i qemu-kvm
  if ! command -v virsh &> /dev/null; then
    log_error "Libvirt nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
  fi

  if ! command -v qemu-img &> /dev/null; then
    log_error "QEMU nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
  fi

  # Sprawdź Ansible
  if ! command -v ansible &> /dev/null; then
    log_warning "Ansible nie jest zainstalowany. Instalowanie..."
    install_ansible
  fi

  # Sprawdź Python
  if ! command -v python3 &> /dev/null; then
    log_error "Python 3 nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
  fi

  # Sprawdź Docker
  if ! command -v docker &> /dev/null; then
    log_warning "Docker nie jest zainstalowany. Instalowanie..."
    install_docker
  fi

  # Sprawdź Go (dla agenta)
  if ! command -v go &> /dev/null; then
    log_warning "Go nie jest zainstalowany. Agent zostanie zainstalowany z wersji skompilowanej."
  fi

  log_success "Wszystkie wymagania systemowe spełnione."
}

# Instalacja Ansible
install_ansible() {
  log "Instalowanie Ansible..."

  # Detekcja systemu
  if command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get update
    apt-get install -y ansible
  elif command -v dnf &> /dev/null; then
    # Fedora/RHEL 8+
    dnf install -y ansible
  elif command -v yum &> /dev/null; then
    # CentOS/RHEL 7
    yum install -y epel-release
    yum install -y ansible
  else
    log_error "Nie można zainstalować Ansible. Nieobsługiwany menedżer pakietów."
  fi

  log_success "Ansible zainstalowany pomyślnie."
}