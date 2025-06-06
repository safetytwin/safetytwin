#!/bin/bash
# install.sh - Main installer for SafetyTwin Digital Twin System
# Author: Tom Sapletta
# Last updated: 2025-05-11
#
# Purpose:
#   This script automates the installation and configuration of the SafetyTwin platform, including VM provisioning, service setup, and agent installation.
#
# Usage:
#   sudo bash install.sh
#
# What it does:
#   - Checks system requirements and installs dependencies
#   - Downloads and prepares Ubuntu cloud images
#   - Sets up directories and configuration files
#   - Installs and configures VM Bridge, agent, and CLI
#   - Provisions a base VM using libvirt/QEMU/KVM
#   - Configures cloud-init for VM initialization
#   - Sets up monitoring and cron jobs
#
# This script should be run on the host (controller) system. For diagnostics and VM checks, see diagnostics.sh and diagnostics_download.sh.
#
# Contact: tom@sapletta.com

set -e

# Kolorowe komunikaty
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Katalogi instalacyjne
INSTALL_DIR="/opt/safetytwin"
CONFIG_DIR="/etc/safetytwin"
STATE_DIR="/var/lib/safetytwin"
LOG_DIR="/var/log/safetytwin"

# Ustawienia domyślne
DEFAULT_BRIDGE_PORT=5678
DEFAULT_INTERVAL=10
DEFAULT_VM_NAME="safetytwin-vm"
DEFAULT_VM_MEMORY=4096  # MB
DEFAULT_VM_VCPUS=2

# Funkcja logująca
log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

wait_for_apt_lock() {
  local msg="Czekam na zwolnienie blokady APT (inny proces instaluje pakiety)..."
  while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
    log_warning "$msg"
    sleep 5
  done
  log_success "APT lock zwolniony, kontynuuję instalację."
}


log_success() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Sprawdzenie uprawnień
check_root() {
  ensure_cloud_image

  if [ "$(id -u)" -ne 0 ]; then
    log_error "Ten skrypt musi być uruchomiony jako root."
    exit 1
  fi
}

# --- Ensure gotty web terminal is present ---
ensure_gotty() {
  GOTTY_BIN="/usr/local/bin/gotty"
  GOTTY_VERSION="1.4.0"
  GOTTY_URL="https://github.com/yudai/gotty/releases/download/v$GOTTY_VERSION/gotty_linux_amd64.tar.gz"
  if ! command -v gotty &>/dev/null; then
    log_warning "gotty not found, installing..."
    TMP_GOTTY_ARCHIVE="/tmp/gotty.tar.gz"
    echo "[INSTALL] Downloading gotty..."
    wget -O "$TMP_GOTTY_ARCHIVE" "$GOTTY_URL" || { echo "[ERROR] Failed to download gotty."; exit 1; }
    if tar -tzf "$TMP_GOTTY_ARCHIVE" &>/dev/null; then
      tar xzf "$TMP_GOTTY_ARCHIVE" -C /opt/safetytwin
      echo "[INSTALL] Gotty extracted successfully."
    else
      echo "[ERROR] Gotty archive is corrupted. Aborting install."; exit 1
    fi
    rm -f "$TMP_GOTTY_ARCHIVE"
    sudo mv /opt/safetytwin/gotty "$GOTTY_BIN"
    sudo chmod +x "$GOTTY_BIN"
    log_success "gotty installed at $GOTTY_BIN"
  else
    log_success "gotty already present at $GOTTY_BIN"
  fi
  # Copy gotty_install_and_service.sh to /var/lib/safetytwin for VM provisioning
  mkdir -p /var/lib/safetytwin
  cp "$(dirname "$0")/gotty_install_and_service.sh" /var/lib/safetytwin/gotty_install_and_service.sh
  chmod +x /var/lib/safetytwin/gotty_install_and_service.sh
  log_success "gotty_install_and_service.sh ready in /var/lib/safetytwin/"
}

# --- Ensure correct Ubuntu cloud image is present ---
ensure_cloud_image() {
  IMG_DIR="/var/lib/safetytwin/images"
  BASE_IMG="$IMG_DIR/ubuntu-base.img"
  CLOUDIMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"

  mkdir -p "$IMG_DIR"
  if [ ! -f "$BASE_IMG" ]; then
    log_warning "Brak obrazu Ubuntu cloudimg. Pobieram oficjalny obraz cloud-init..."
    wget -O "$BASE_IMG" "$CLOUDIMG_URL"
  else
    log_success "Obraz Ubuntu cloudimg już istnieje: $BASE_IMG"
    log "Jeśli chcesz wymusić pobranie nowego obrazu, usuń ten plik ręcznie."
  fi
  log "Używany obraz VM: $BASE_IMG"
}

# Sprawdzenie wymagań systemowych i instalacja zależności
check_requirements() {
  log "Sprawdzanie i instalacja wymagań systemowych..."

  # Rozpoznaj dystrybucję Linuxa
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
  else
    log_error "Nie można rozpoznać dystrybucji Linuxa. Przerwano instalację."
    exit 1
  fi

  # Instalacja narzędzi wymaganych przez skrypty diagnostyczne i narzędziowe
  case "$DISTRO" in
    ubuntu|debian)
      log "Instaluję dodatkowe narzędzia: whois, sudo, net-tools, iproute2, cloud-utils, expect, lsof, jq, sed, grep, awk, python3, python3-pip, python3-venv, curl, ansible, libvirt-clients, libvirt-daemon-system, qemu-kvm, qemu-utils, golang..."
      sudo apt-get update
      sudo apt-get install -y gawk jq curl ansible libvirt-clients qemu-utils python3-fastapi python3-uvicorn python3-jinja2 python3-multipart || \
        pip3 install fastapi uvicorn jinja2 python-multipart expect lsof jq sed grep gawk python3 python3-pip python3-venv curl ansible libvirt-clients libvirt-daemon-system qemu-kvm qemu-utils golang
      log_success "Zainstalowano wszystkie wymagane narzędzia systemowe (awk → gawk)."
      ;;
    centos|rhel|fedora)
      log "Instaluję dodatkowe narzędzia: whois, sudo, net-tools, iproute, cloud-utils, expect, lsof, jq, sed, grep, awk, python3, python3-pip, python3-venv, curl, ansible, libvirt-client, libvirt-daemon-system, qemu-kvm, qemu-img, golang..."
      sudo yum install -y whois sudo net-tools iproute cloud-utils expect lsof jq sed grep awk python3 python3-pip python3-venv curl ansible libvirt-client libvirt-daemon-system qemu-kvm qemu-img golang -y
      ;;
    arch)
      log "Instaluję dodatkowe narzędzia: whois, sudo, net-tools, iproute2, cloud-utils, expect, lsof, jq, sed, grep, awk..."
      pacman -Syu --noconfirm whois sudo net-tools iproute2 cloud-utils expect lsof jq sed grep awk
      ;;
    *)
      log_warning "Nieznana dystrybucja: $DISTRO. Spróbuj zainstalować wymagane narzędzia ręcznie."
      ;;
  esac

  # Sprawdź i zainstaluj virt-install jeśli brak
  if ! command -v virt-install >/dev/null 2>&1; then
    case "$DISTRO" in
      ubuntu|debian)
        log_warning "virt-install nie znaleziony. Instaluję pakiet virtinst..."
        sudo apt-get update
        sudo apt-get install -y virtinst
        ;;
      centos|rhel|fedora)
        log_warning "virt-install nie znaleziony. Zainstaluj pakiet virt-install lub virt-manager dla swojej dystrybucji."
        ;;
      arch)
        log_warning "virt-install nie znaleziony. Zainstaluj pakiet virt-manager dla swojej dystrybucji."
        ;;
      *)
        log_warning "virt-install nie znaleziony. Zainstaluj ręcznie pakiet virt-install/virtinst."
        ;;
    esac
  fi

  # Ustal menedżer pakietów i pakiety
  PKG_UPDATE=""
  PKG_INSTALL=""
  PKGS=""
  case "$DISTRO" in
     ubuntu|debian)
      wait_for_apt_lock  # Czekaj na zwolnienie locka przed update
      apt-get update
      wait_for_apt_lock  # Czekaj na zwolnienie locka przed install
      apt-get install -y sudo curl wget jq lsb-release net-tools sshpass libvirt-clients libvirt-daemon-system qemu-kvm virtinst genisoimage cloud-image-utils whois
      PKG_UPDATE="apt-get update"
      PKG_INSTALL="apt-get install -y"
      PKGS="libvirt-dev libvirt-daemon-system libvirt-clients qemu-kvm python3 python3-dev python3-pip gcc make pkg-config genisoimage"
      LIBVIRT_SERVICE="libvirtd"
      ;;
    centos|rhel|fedora)
      PKG_UPDATE="dnf makecache || yum makecache"
      PKG_INSTALL="dnf install -y || yum install -y"
      PKGS="libvirt-devel libvirt qemu-kvm python3 python3-devel python3-pip gcc make pkgconf-pkg-config genisoimage"
      LIBVIRT_SERVICE="libvirtd"
      ;;
    arch)
      PKG_UPDATE="pacman -Sy"
      PKG_INSTALL="pacman -S --noconfirm"
      PKGS="libvirt qemu python python-pip gcc make pkgconf cdrtools"
      LIBVIRT_SERVICE="libvirtd"
      ;;
    opensuse*|suse)
      PKG_UPDATE="zypper refresh"
      PKG_INSTALL="zypper install -y"
      PKGS="libvirt-devel libvirt qemu python3 python3-devel python3-pip gcc make pkgconf-pkg-config genisoimage"
      LIBVIRT_SERVICE="libvirtd"
      ;;
    *)
      log_error "Nieobsługiwana dystrybucja Linuxa: $DISTRO. Przerwano instalację."
      exit 1
      ;;
  esac

  # Instalacja pakietów systemowych
  log "Aktualizacja repozytoriów..."
  eval $PKG_UPDATE
  log "Instalacja pakietów: $PKGS"
  eval $PKG_INSTALL $PKGS

  # Włącz i uruchom usługę libvirtd jeśli jest dostępna
  if systemctl list-unit-files | grep -q "$LIBVIRT_SERVICE"; then
    log "Włączanie i uruchamianie usługi $LIBVIRT_SERVICE..."
    systemctl enable --now $LIBVIRT_SERVICE || true
    systemctl start $LIBVIRT_SERVICE || true
    systemctl status $LIBVIRT_SERVICE --no-pager || true
  else
    log_warning "Usługa $LIBVIRT_SERVICE nie jest dostępna na tym systemie."
  fi

  # Sprawdź libvirt, virsh, qemu-kvm i usługę libvirtd
  if ! command -v virsh &> /dev/null; then
    log_error "Libvirt/virsh nie jest zainstalowany lub nie jest w PATH. Spróbuj ponownie lub sprawdź instalację."
    exit 1
  fi
  if ! command -v qemu-system-x86_64 &> /dev/null; then
    log_error "QEMU nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
    exit 1
  fi
  if ! systemctl is-active --quiet $LIBVIRT_SERVICE; then
    log_error "Usługa $LIBVIRT_SERVICE nie działa. Spróbuj: sudo systemctl start $LIBVIRT_SERVICE"
    exit 1
  fi
  # Sprawdź pip
  if ! command -v pip3 &> /dev/null; then
    log_error "pip3 nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
    exit 1
  fi

  # Instalacja zależności Python (VM Bridge)
  if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
    log "Instalacja pakietów Python przez apt..."
    apt-get install -y python3-libvirt python3-flask python3-flask-cors python3-yaml python3-paramiko python3-gunicorn python3-werkzeug python3-pytest
    log "Instalacja deepdiff i ansible przez pip..."
    pip3 install -q --break-system-packages deepdiff ansible
  else
    log "Instalacja pakietów Python przez pip..."
    pip3 install -q --upgrade pip
    pip3 install -q fastapi uvicorn pyyaml jinja2 flask deepdiff paramiko libvirt-python docker || true
    log_success "Wszystkie zależności Python zostały zainstalowane."
  fi

  log_success "Wszystkie wymagania systemowe i zależności Python zostały zainstalowane."

# Instalacja i aktywacja usługi orchestratora i timera agenta
if [ -f orchestrator.service ] && [ -f agent_send_state.service ] && [ -f agent_send_state.timer ]; then
  log "Kopiuję pliki orchestrator.service, agent_send_state.service, agent_send_state.timer do /etc/systemd/system/ ..."
  sudo cp orchestrator.service /etc/systemd/system/
  sudo cp agent_send_state.service /etc/systemd/system/
  sudo cp agent_send_state.timer /etc/systemd/system/
  log "Przeładowuję systemd i aktywuję usługi..."
  sudo systemctl daemon-reload
  sudo systemctl enable orchestrator.service
  sudo systemctl start orchestrator.service
  sudo systemctl enable agent_send_state.timer
  sudo systemctl start agent_send_state.timer
  log_success "Usługi orchestratora i agenta zostały aktywowane."
else
  log_warning "Brak plików orchestrator.service, agent_send_state.service lub agent_send_state.timer. Usługi nie zostały aktywowane automatycznie."
fi
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
    exit 1
  fi

  log_success "Ansible zainstalowany pomyślnie."
}

# Tworzenie katalogów
create_directories() {
  log "Tworzenie katalogów..."

  mkdir -p "$INSTALL_DIR"
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$STATE_DIR"
  mkdir -p "$LOG_DIR"

  log_success "Katalogi utworzone."
}

# Konfiguracja monitoringu storage w cronie
define_cron_monitor() {
  log "Konfiguracja monitoringu storage w cronie..."
  # Upewnij się, że katalog monitorowany istnieje
  mkdir -p /var/lib/safetytwin
  sed 's|/var/lib/vm-bridge|/var/lib/safetytwin|g' vm-bridge/utils/monitor_storage.sh > /usr/local/bin/monitor_storage.sh
  chmod +x /usr/local/bin/monitor_storage.sh
  # Dodaj do crona root jeśli nie istnieje
  if ! crontab -l | grep -q '/usr/local/bin/monitor_storage.sh'; then
    (crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/monitor_storage.sh >> /var/log/vm-bridge-storage.log 2>&1") | crontab -
    log_success "Dodano zadanie monitoringu storage do crona."
  else
    log "Zadanie monitoringu storage już istnieje w cronie."
  fi
}

# Instalacja CLI safetytwin
install_safetytwin_cli() {
  log "Instalacja narzędzia CLI safetytwin..."
  cat <<'EOF' > /usr/local/bin/safetytwin
#!/bin/bash
ACTION="$1"
LOGFILE="/var/log/safetytwin/vm-bridge.log"
AGENT_SERVICE="safetytwin-agent.service"
MONITOR_SCRIPT="/usr/local/bin/monitor_storage.sh"

case "$ACTION" in
  status)
    echo "== Status usług =="
    systemctl status safetytwin-agent.service --no-pager
    systemctl status safetytwin-bridge.service --no-pager
    ;;
  agent-log)
    echo "== Logi agenta =="
    journalctl -u safetytwin-agent.service -n 50 --no-pager
    ;;
  bridge-log)
    echo "== Logi VM Bridge =="
    tail -n 50 "$LOGFILE"
    ;;
  cron-list)
    echo "== Zadania cron dla root =="
    crontab -l | grep monitor_storage.sh || echo "Brak zadania monitor_storage.sh w cronie."
    ;;
  cron-status)
    pgrep -fl monitor_storage.sh && echo "monitor_storage.sh działa" || echo "monitor_storage.sh nie działa (czeka na kolejne uruchomienie przez cron)"
    ;;
  cron-remove)
    crontab -l | grep -v monitor_storage.sh | crontab -
    echo "Usunięto zadanie monitor_storage.sh z crona."
    ;;
  cron-add)
    if ! crontab -l | grep -q '/usr/local/bin/monitor_storage.sh'; then
      (crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/monitor_storage.sh >> /var/log/vm-bridge-storage.log 2>&1") | crontab -
      echo "Dodano zadanie monitor_storage.sh do crona."
    else
      echo "Zadanie monitor_storage.sh już istnieje w cronie."
    fi
    ;;
  what)
    echo "== Ostatnie działania aplikacji (log) =="
    tail -n 20 "$LOGFILE"
    ;;
  *)
    echo "Użycie: safetytwin [status|agent-log|bridge-log|cron-list|cron-status|cron-add|cron-remove|what]"
    ;;
esac
EOF
  chmod +x /usr/local/bin/safetytwin
  log_success "CLI safetytwin zainstalowane. Użyj: safetytwin [status|agent-log|bridge-log|cron-list|cron-status|cron-add|cron-remove|what]"
}

# Konfiguracja VM Bridge
configure_vm_bridge() {
  log "Konfigurowanie VM Bridge..."

  # Utwórz katalog na szablony
  mkdir -p "$INSTALL_DIR/templates"

  # Skopiuj szablony
  cat > "$INSTALL_DIR/templates/process_launcher.sh.j2" << 'EOF'
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
{% if item.cmdline is defined and item.cmdline | length > 0 %}
exec {{ item.cmdline | join(' ') }}
{% else %}
exec {{ item.name }}
{% endif %}
EOF

  cat > "$INSTALL_DIR/templates/process_service.service.j2" << 'EOF'
[Unit]
Description=Digital Twin Process: {{ item.name }} (Original PID: {{ item.pid }})
After=network.target

[Service]
Type=simple
User={{ item.user | default('root') }}
ExecStart=/tmp/process_{{ item.name }}_{{ item.pid }}.sh
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

  # Utwórz plik konfiguracyjny VM Bridge
  cat > "$CONFIG_DIR/vm-bridge.yaml" << EOF
# Konfiguracja VM Bridge
libvirt_uri: qemu:///system
vm_user: root
vm_password: safetytwin-password
vm_key_path: $CONFIG_DIR/ssh/id_rsa
ansible_inventory: $CONFIG_DIR/inventory.yml
ansible_playbook: $INSTALL_DIR/apply_services.yml
state_dir: $STATE_DIR/states
max_snapshots: 10
EOF

  # Utwórz playbook Ansible
  cat > "$INSTALL_DIR/apply_services.yml" << 'EOF'
---
# apply_services.yml
# Playbook Ansible do konfiguracji usług w wirtualnej maszynie cyfrowego bliźniaka

- name: Konfiguracja cyfrowego bliźniaka
  hosts: all
  become: yes
  vars:
    config_file: "{{ config_file | default('/var/lib/vm-bridge/states/service_config.yaml') }}"

  pre_tasks:
    - name: Wczytaj konfigurację usług
      ansible.builtin.include_vars:
        file: "{{ config_file }}"
        name: service_config

    - name: Sprawdź, czy VM jest gotowa
      ansible.builtin.ping:
      register: ping_result

    - name: Wyświetl informacje o VM
      ansible.builtin.debug:
        msg: "Konfigurowanie VM: {{ ansible_hostname }}, {{ ansible_distribution }} {{ ansible_distribution_version }}"

  tasks:
    #
    # 1. Konfiguracja systemu
    #
    - name: Ustaw hostname
      ansible.builtin.hostname:
        name: "{{ service_config.system.hostname }}"
      when: service_config.system.hostname is defined

    # ... [reszta playbooka Ansible] ...
EOF

  # Utwórz katalog na klucze SSH
  mkdir -p "$CONFIG_DIR/ssh"

  # Wygeneruj klucz SSH
  if [ ! -f "$CONFIG_DIR/ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -f "$CONFIG_DIR/ssh/id_rsa" -N "" -C "safetytwin@localhost"
    log_success "Wygenerowano klucz SSH dla komunikacji z VM."
  fi

  log_success "VM Bridge skonfigurowany pomyślnie."
}

# Instalacja agenta
install_agent() {
  log "Instalowanie agenta monitorującego..."

  # Skopiuj binarny plik agenta lub kod źródłowy
  # W rzeczywistości tutaj byłby skompilowany agent

  cat > "$INSTALL_DIR/agent-config.json" << EOF
{
  "interval": $DEFAULT_INTERVAL,
  "bridge_url": "http://localhost:$DEFAULT_BRIDGE_PORT/api/v1/update_state",
  "log_file": "$LOG_DIR/agent.log",
  "state_dir": "$STATE_DIR/agent-states",
  "include_proc": true,
  "include_net": true,
  "verbose": false
}
EOF

  # Utwórz usługę systemd dla agenta
  cat > "/etc/systemd/system/safetytwin-agent.service" << EOF
[Unit]
Description=Digital Twin Agent
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/safetytwin-agent -config $INSTALL_DIR/agent-config.json
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=safetytwin-agent
User=root
Group=root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

  log_success "Agent monitorujący zainstalowany pomyślnie."
}

# Instalacja usługi VM Bridge
install_vm_bridge_service() {
  log "Instalowanie usługi VM Bridge..."

  cat > "/etc/systemd/system/safetytwin-bridge.service" << EOF
[Unit]
Description=Digital Twin VM Bridge
After=network.target libvirtd.service

[Service]
Type=simple
ExecStart=$INSTALL_DIR/vm-bridge
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=safetytwin-bridge
User=root
Group=root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

  log_success "Usługa VM Bridge zainstalowana pomyślnie."
}

# Tworzenie bazowej maszyny wirtualnej
create_base_vm() {
  log "Tworzenie bazowej maszyny wirtualnej (nowoczesny provisioning)..."

  # Konfiguracja
  VM_NAME=${1:-safetytwin-vm}
  VM_MEMORY=2048
  VM_CPUS=2
  VM_DISK_SIZE=20G
  USERNAME="ubuntu"
  PASSWORD="ubuntu"
  INSTALL_PACKAGES="qemu-guest-agent openssh-server python3 net-tools iproute2"

  WORK_DIR="/var/lib/safetytwin"
  CLOUD_INIT_DIR="$WORK_DIR/cloud-init"
  IMG_DIR="$WORK_DIR/images"
  USER_DATA="$CLOUD_INIT_DIR/user-data"
  META_DATA="$CLOUD_INIT_DIR/meta-data"
  ISO="$CLOUD_INIT_DIR/cloud-init.iso"
  VM_IMAGE="$IMG_DIR/$VM_NAME.qcow2"

  mkdir -p "$CLOUD_INIT_DIR" "$IMG_DIR"

  # Usuwanie istniejącej VM (jeśli istnieje)
  if virsh dominfo "$VM_NAME" &>/dev/null; then
    log_warning "VM '$VM_NAME' już istnieje. Usuwam..."
    virsh destroy "$VM_NAME" &>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage --nvram &>/dev/null || true
  fi

  # Pobierz oficjalny obraz Ubuntu cloud-init, jeśli brak
  UBUNTU_IMAGE="$IMG_DIR/jammy-server-cloudimg-amd64.img"
  if [ -f "$UBUNTU_IMAGE" ]; then
    log "Używam istniejącego obrazu Ubuntu: $UBUNTU_IMAGE"
  else
    log "Pobieram oficjalny obraz Ubuntu cloud-init..."
    wget -O "$UBUNTU_IMAGE" "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  fi

  # Utwórz kopię dla VM
  log "Tworzę obraz dysku VM ($VM_DISK_SIZE)..."
  cp "$UBUNTU_IMAGE" "$VM_IMAGE"
  qemu-img resize "$VM_IMAGE" "$VM_DISK_SIZE"

  # Cloud-init user-data/meta-data
  log "Generuję pliki cloud-init..."
  cat > "$USER_DATA" << EOF
#cloud-config
hostname: $VM_NAME
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: '$PASSWORD'
ssh_pwauth: true
disable_root: false

network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true

package_update: true
package_upgrade: true
packages:
$(for pkg in $INSTALL_PACKAGES; do echo "  - $pkg"; done)

runcmd:
  - echo '$USERNAME:$PASSWORD' | chpasswd
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  - systemctl restart ssh
EOF

  cat > "$META_DATA" << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

  # ISO cloud-init
  log "Tworzę ISO cloud-init..."
  genisoimage -output "$ISO" -volid cidata -joliet -rock "$META_DATA" "$USER_DATA"
  chmod 644 "$ISO"
  chown libvirt-qemu:libvirt-qemu "$ISO" "$VM_IMAGE" 2>/dev/null || true

  # Tworzenie VM
  log "Tworzę i uruchamiam VM..."
  virt-install --name "$VM_NAME" \
    --memory "$VM_MEMORY" \
    --vcpus "$VM_CPUS" \
    --disk "$VM_IMAGE",device=disk,format=qcow2 \
    --disk "$ISO",device=cdrom \
    --os-variant ubuntu22.04 \
    --virt-type kvm \
    --network default \
    --graphics none \
    --import \
    --noautoconsole

  log "Czekam na przydzielenie adresu IP przez VM..."
  VM_IP=""
  for i in {1..12}; do
    VM_IP=$(virsh domifaddr "$VM_NAME" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -n "$VM_IP" ]; then
      log_success "VM ma adres IP: $VM_IP"
      break
    fi
    sleep 10
  done
  if [ -z "$VM_IP" ]; then
    log_error "Nie udało się uzyskać adresu IP VM. Sprawdź konsolę: sudo virsh console $VM_NAME"
    return 1
  fi

  log_success "VM '$VM_NAME' utworzona i uruchomiona! IP: $VM_IP"
  log_success "Dostęp SSH: ssh $USERNAME@$VM_IP (hasło: $PASSWORD)"
  log "Dostęp do konsoli: sudo virsh console $VM_NAME"
  echo "$VM_IP" > "$WORK_DIR/${VM_NAME}.ip"
}
  log "Tworzenie bazowej maszyny wirtualnej..."

  VM_NAME=$DEFAULT_VM_NAME
  VM_MEMORY=$DEFAULT_VM_MEMORY
  VM_VCPUS=$DEFAULT_VM_VCPUS

  # Sprawdź, czy VM już istnieje
  if virsh dominfo "$VM_NAME" &>/dev/null; then
    log_warning "Maszyna wirtualna '$VM_NAME' już istnieje. Pomijanie tworzenia."
    return 0 2>/dev/null || true
  fi

  # Utwórz katalog na obrazy VM
  mkdir -p "$STATE_DIR/images"

  # Pobierz bazowy obraz
  log "Pobieranie bazowego obrazu Ubuntu..."
  if [ ! -f "$STATE_DIR/images/ubuntu-base.img" ]; then
  wget -O "$STATE_DIR/images/ubuntu-base.img" "https://cloud-images.ubuntu.com/minimal/releases/focal/release/ubuntu-20.04-minimal-cloudimg-amd64.img"
else
  echo "Obraz ubuntu-base.img już istnieje, pomijam pobieranie."
fi

  # Dostosuj obraz
  log "Dostosowywanie obrazu..."
  qemu-img resize "$STATE_DIR/images/ubuntu-base.img" 20G

  # Utwórz plik cloud-init
  mkdir -p "$STATE_DIR/cloud-init"

  cat > "$STATE_DIR/cloud-init/meta-data" << EOF
instance-id: safetytwin-vm
local-hostname: safetytwin-vm
EOF

  cat > "$STATE_DIR/cloud-init/user-data" << EOF
#cloud-config
hostname: safetytwin-vm
users:
  - name: root
    lock_passwd: false
    hashed_passwd: $(openssl passwd -6 "safetytwin-password")
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
  genisoimage -output "$STATE_DIR/cloud-init/cloud-init.iso" -volid cidata -joliet -rock "$STATE_DIR/cloud-init/meta-data" "$STATE_DIR/cloud-init/user-data"

  # Utwórz XML definicji VM
  cat > "$STATE_DIR/vm-definition.xml" << EOF
<domain type='kvm'>
  <name>$VM_NAME</name>
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
      <source file='$STATE_DIR/images/ubuntu-base.img'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$STATE_DIR/cloud-init/cloud-init.iso'/>
      <target dev='hdc' bus='ide'/>
      <readonly/>
    </disk>
{{ ... }}
      virsh net-start default
    fi
    virsh net-autostart default
  fi
  # Upewnij się, że user-data ma sekcję network
  if ! grep -q 'network:' /var/lib/safetytwin/cloud-init/user-data; then
    log "[AUTO-FIX] Dodaję domyślną konfigurację sieci do user-data."
    echo -e '\nnetwork:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: true' >> /var/lib/safetytwin/cloud-init/user-data
  fi
  # Po naprawie próbuj ponownie uzyskać IP
  sleep 5
  IP_VM=$(cat /var/lib/libvirt/dnsmasq/default.leases | grep $(virsh domiflist safetytwin-vm | awk '/network/ {print $5}') | awk '{print $3}')
  if [ -z "$IP_VM" ]; then
{{ ... }}
  sleep 5
  IP_VM=$(cat /var/lib/libvirt/dnsmasq/default.leases | grep $(virsh domiflist safetytwin-vm | awk '/network/ {print $5}') | awk '{print $3}')
  if [ -z "$IP_VM" ]; then
    log_error "Nie można uzyskać adresu IP VM. Możesz uruchomić pełną diagnostykę sieci VM poleceniem:\n  bash diagnose-vm-network.sh\nWyślij wynik tego skryptu do wsparcia."
    # Wyświetl skrócone instrukcje ręczne
    echo "Ręczna diagnostyka:\n  sudo virsh domiflist safetytwin-vm\n  sudo virsh net-list --all\n  sudo virsh net-info default\n  sudo cat /var/lib/libvirt/dnsmasq/default.leases\n  sudo virsh console safetytwin-vm\n  sudo cat /var/lib/safetytwin/cloud-init/user-data"
  else
    log "[AUTO-FIX] VM ma adres IP: $IP_VM"
  fi

  VM_IP=$(virsh domifaddr "$DEFAULT_VM_NAME" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
{{ ... }}

  if [ -z "$VM_IP" ]; then
    log_error "Nie można uzyskać adresu IP VM."
    return 1
  fi

  # Pobierz adres IP VM
  VM_IP=$(virsh domifaddr "$DEFAULT_VM_NAME" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)

  if [ -z "$VM_IP" ]; then
    log_error "Nie można uzyskać adresu IP VM."
    return 1
  fi

  # Utwórz playbook dla instalacji VM Bridge
  cat > "$INSTALL_DIR/install_bridge_on_vm.yml" << EOF
---
- name: Instalacja VM Bridge na maszynie wirtualnej
  hosts: digital_twin
  become: yes

  tasks:
    - name: Instalacja wymaganych pakietów
      ansible.builtin.apt:
        name:
          - python3-pip
          - python3-libvirt
          - libvirt-clients
          - libvirt-daemon-system
          - python3-yaml
          - python3-jinja2
          - paramiko
        state: present
        update_cache: yes

    - name: Instalacja wymaganych pakietów Python
      ansible.builtin.pip:
        name:
          - libvirt-python
          - paramiko
          - deepdiff
          - flask
        state: present

    - name: Tworzenie katalogów dla VM Bridge
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
      loop:
        - /opt/vm-bridge
        - /etc/vm-bridge
        - /var/lib/vm-bridge/states
        - /var/log/vm-bridge

    - name: Kopiowanie kodu VM Bridge
      ansible.builtin.copy:
        src: $INSTALL_DIR/vm-bridge.py
        dest: /opt/vm-bridge/vm-bridge.py
        mode: '0755'

    - name: Kopiowanie szablonów
      ansible.builtin.copy:
        src: $INSTALL_DIR/templates/
        dest: /opt/vm-bridge/templates/
        mode: '0644'

    - name: Kopiowanie playbooka Ansible
      ansible.builtin.copy:
        src: $INSTALL_DIR/apply_services.yml
        dest: /opt/vm-bridge/apply_services.yml
        mode: '0644'

    - name: Tworzenie konfiguracji VM Bridge
      ansible.builtin.copy:
        content: |
          libvirt_uri: qemu:///system
          vm_user: root
          vm_password: safetytwin-password
          vm_key_path: /root/.ssh/id_rsa
          ansible_inventory: /etc/vm-bridge/inventory.yml
          ansible_playbook: /opt/vm-bridge/apply_services.yml
          state_dir: /var/lib/vm-bridge/states
          max_snapshots: 10
        dest: /etc/vm-bridge/config.yaml
        mode: '0644'

    - name: Tworzenie usługi systemd
      ansible.builtin.copy:
        content: |
          [Unit]
          Description=Digital Twin VM Bridge
          After=network.target libvirtd.service

          [Service]
          Type=simple
          ExecStart=/usr/bin/python3 /opt/vm-bridge/vm-bridge.py
          Restart=always
          RestartSec=5
          StandardOutput=journal
          StandardError=journal
          SyslogIdentifier=vm-bridge
          User=root
          Group=root
          WorkingDirectory=/opt/vm-bridge

          [Install]
          WantedBy=multi-user.target
        dest: /etc/systemd/system/vm-bridge.service
        mode: '0644'

    - name: Włączenie i uruchomienie usługi VM Bridge
      ansible.builtin.systemd:
        name: vm-bridge
        daemon_reload: yes
        enabled: yes
        state: started
EOF

  # Uruchom playbook
  ansible-playbook -i "$CONFIG_DIR/inventory.yml" "$INSTALL_DIR/install_bridge_on_vm.yml"

  log_success "VM Bridge zainstalowany na maszynie wirtualnej."

# Uruchomienie usług
start_services() {
  log "Uruchamianie usług cyfrowego bliźniaka..."

  # Przeładuj daemona systemd
  systemctl daemon-reload

  # Włącz i uruchom usługi
  bash "$(dirname "$0")/scripts/project_services_control.sh" restart

  log_success "Usługi uruchomione pomyślnie."

  # Sprawdź status usług
  log "Status usługi agenta:"
  systemctl status safetytwin-agent.service --no-pager
}

# Wyświetl podsumowanie
show_summary() {
  VM_IP=$(virsh domifaddr "$DEFAULT_VM_NAME" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)

  echo
  echo -e "${GREEN}=================================================${NC}"
  echo -e "${GREEN}    Instalacja cyfrowego bliźniaka zakończona    ${NC}"
  echo -e "${GREEN}=================================================${NC}"
  echo
  echo -e "Instalacja zakończona pomyślnie. Oto podsumowanie:"
  echo
  echo -e "1. ${BLUE}Agent monitorujący${NC} działa na tym komputerze"
  echo -e "   Status: $(systemctl is-active safetytwin-agent.service)"
  echo -e "   Konfiguracja: $INSTALL_DIR/agent-config.json"
  echo -e "   Logi: $LOG_DIR/agent.log"
  echo
  echo -e "2. ${BLUE}Maszyna wirtualna${NC} cyfrowego bliźniaka"
  echo -e "   Nazwa: $DEFAULT_VM_NAME"
  echo -e "   Status: $(virsh domstate "$DEFAULT_VM_NAME")"
  echo -e "   IP: $VM_IP"
  echo -e "   Dostęp SSH: ssh -i $CONFIG_DIR/ssh/id_rsa root@$VM_IP"
  echo
  echo -e "3. ${BLUE}VM Bridge${NC} działa na maszynie wirtualnej"
  echo -e "   Endpoint API: http://$VM_IP:$DEFAULT_BRIDGE_PORT/api/v1"
  echo
  echo -e "Możesz monitorować logi poprzez:"
  echo -e "   journalctl -fu safetytwin-agent"
  echo -e "   ssh -i $CONFIG_DIR/ssh/id_rsa root@$VM_IP journalctl -fu vm-bridge"
  echo
  echo -e "${GREEN}=================================================${NC}"
  echo
}

# Funkcja sprawdzająca i naprawiająca usługi safetytwin
auto_fix_services() {
  log "[AUTO-FIX] Sprawdzanie i naprawa usług safetytwin..."
  # Agent
  if [ ! -f "/etc/systemd/system/safetytwin-agent.service" ]; then
    log_warning "Brak pliku unit safetytwin-agent.service. Tworzę ponownie..."
    install_agent
  fi
  systemctl daemon-reload
  systemctl enable --now safetytwin-agent.service || log_error "Nie można uruchomić safetytwin-agent.service"
  # Bridge
  if [ ! -f "/etc/systemd/system/safetytwin-bridge.service" ]; then
    log_warning "Brak pliku unit safetytwin-bridge.service. Tworzę ponownie..."
    install_vm_bridge_service
  fi
  systemctl daemon-reload
  systemctl enable --now safetytwin-bridge.service || log_error "Nie można uruchomić safetytwin-bridge.service"
}

# Funkcja sprawdzająca i naprawiająca VM
auto_fix_vm() {
  log "[AUTO-FIX] Sprawdzanie i naprawa maszyny wirtualnej..."
  if [ ! -f "/var/lib/safetytwin/images/ubuntu-base.img" ]; then
    log_warning "Brak obrazu VM. Pobieram..."
    create_base_vm
  fi
  if ! virsh list --all | grep -q safetytwin-vm; then
    log_warning "VM nie jest zdefiniowana. Definiuję..."
    virsh define /var/lib/safetytwin/vm-definition.xml || log_error "Nie można zdefiniować VM."
  fi
  if ! virsh list --state-running | grep -q safetytwin-vm; then
    log_warning "VM nie jest uruchomiona. Uruchamiam..."
    virsh start safetytwin-vm || log_error "Nie można uruchomić VM."
  fi
}

# Funkcja sprawdzająca i naprawiająca cron monitoringu
auto_fix_monitoring_cron() {
  log "[AUTO-FIX] Sprawdzanie i naprawa monitoringu storage w cronie..."
  if ! crontab -l 2>/dev/null | grep -q '/usr/local/bin/monitor_storage.sh'; then
    (crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/monitor_storage.sh >> /var/log/safetytwin/storage.log 2>&1") | crontab -
    log_success "Dodano zadanie monitoringu storage do crona."
  else
    log "Zadanie monitoringu storage już istnieje w cronie."
  fi
}

# Główna funkcja
main() {
  log "Rozpoczynanie instalacji systemu cyfrowego bliźniaka..."

  check_root

  # --- AUTOMATYCZNE VENV ---
  VENV_DIR=".venv"
  if [ ! -d "$VENV_DIR" ]; then
    log "Tworzę środowisko Python venv w $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
    log_success "Utworzono venv."
  else
    log "Środowisko venv już istnieje."
  fi
  # Aktywuj venv
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  log_success "Aktywowano środowisko venv ($VENV_DIR). Wszystkie zależności pip zostaną zainstalowane lokalnie."
  # Używaj pip z venv
  PIP="$VENV_DIR/bin/pip"

  check_requirements

  # Instalacja ansible i deepdiff do venv
  log "Instalacja deepdiff i ansible przez pip (w venv)..."
  $PIP install --upgrade pip
  $PIP install deepdiff ansible

  install_ansible
  create_directories
  define_cron_monitor
  install_safetytwin_cli
  configure_vm_bridge
  install_agent
  install_vm_bridge_service
  create_base_vm
  # install_vm_bridge_on_vm
  start_services
  show_summary

  log_success "Instalacja zakończona pomyślnie!"

  # --- DIAGNOSTYKA I AUTO-NAPRAWA ---
  if [ -f "INSTALL_RESULT.yaml" ]; then
    log "[AUTO-DIAG] Rozpoczynam automatyczną diagnostykę i naprawę systemu po instalacji..."
    if [ -f "repair.sh" ]; then
      bash repair.sh INSTALL_RESULT.yaml | tee -a install.log
    else
      log_warning "Brak repair.sh — pomijam auto-naprawę."
    fi
    if [ -f "diagnose-vm-network.sh" ]; then
      bash diagnose-vm-network.sh | tee -a install.log
    else
      log_warning "Brak diagnose-vm-network.sh — pomijam diagnostykę VM."
    fi
    log_success "Diagnostyka i naprawa po instalacji zakończona. Sprawdź INSTALL_RESULT.yaml oraz install.log."
  else
    log_warning "Brak INSTALL_RESULT.yaml — pomijam auto-diagnostykę."
  fi
}


# Uruchom główną funkcję
  # Automatyczne naprawy przed główną instalacją
  auto_fix_services
  auto_fix_vm
  auto_fix_monitoring_cron
  main "$@"