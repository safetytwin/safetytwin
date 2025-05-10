# Główny skrypt instalacyjny
#!/bin/bash
# Skrypt instalacyjny systemu cyfrowego bliźniaka
# Autor: Tom Sapletta
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
DEFAULT_BRIDGE_PORT=5678
DEFAULT_INTERVAL=10
DEFAULT_VM_NAME="digital-twin-vm"
DEFAULT_VM_MEMORY=4096  # MB
DEFAULT_VM_VCPUS=2

# Funkcja logująca
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
}

# Sprawdzenie uprawnień
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "Ten skrypt musi być uruchomiony jako root."
    exit 1
  fi
}

# Sprawdzenie wymagań systemowych
check_requirements() {
  log "Sprawdzanie wymagań systemowych..."

  # Sprawdź libvirt i qemu-kvm
  if ! command -v virsh &> /dev/null; then
    log_error "Libvirt nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
    exit 1
  fi

  if ! command -v qemu-img &> /dev/null; then
    log_error "QEMU nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
    exit 1
  fi

  # Sprawdź Ansible
  if ! command -v ansible &> /dev/null; then
    log_warning "Ansible nie jest zainstalowany. Instalowanie..."
    install_ansible
  fi

  # Sprawdź Python
  if ! command -v python3 &> /dev/null; then
    log_error "Python 3 nie jest zainstalowany. Zainstaluj go przy użyciu menedżera pakietów."
    exit 1
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
    exit 1
  fi

  log_success "Ansible zainstalowany pomyślnie."
}

# Tworzenie katalogów
create_directories() {
  log "Tworzenie katalogów instalacyjnych..."

  mkdir -p "$INSTALL_DIR"
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$STATE_DIR"
  mkdir -p "$LOG_DIR"

  log_success "Katalogi utworzone pomyślnie."
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
vm_password: digital-twin-password
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
    ssh-keygen -t rsa -b 4096 -f "$CONFIG_DIR/ssh/id_rsa" -N "" -C "digital-twin@localhost"
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
  cat > "/etc/systemd/system/digital-twin-agent.service" << EOF
[Unit]
Description=Digital Twin Agent
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/digital-twin-agent -config $INSTALL_DIR/agent-config.json
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

  log_success "Agent monitorujący zainstalowany pomyślnie."
}

# Instalacja usługi VM Bridge
install_vm_bridge_service() {
  log "Instalowanie usługi VM Bridge..."

  cat > "/etc/systemd/system/digital-twin-bridge.service" << EOF
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
SyslogIdentifier=digital-twin-bridge
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
  log "Tworzenie bazowej maszyny wirtualnej..."

  VM_NAME=$DEFAULT_VM_NAME
  VM_MEMORY=$DEFAULT_VM_MEMORY
  VM_VCPUS=$DEFAULT_VM_VCPUS

  # Sprawdź, czy VM już istnieje
  if virsh dominfo "$VM_NAME" &>/dev/null; then
    log_warning "Maszyna wirtualna '$VM_NAME' już istnieje. Pomijanie tworzenia."
    return
  fi

  # Utwórz katalog na obrazy VM
  mkdir -p "$STATE_DIR/images"

  # Pobierz bazowy obraz
  log "Pobieranie bazowego obrazu Ubuntu..."
  wget -O "$STATE_DIR/images/ubuntu-base.img" "https://cloud-images.ubuntu.com/minimal/releases/focal/release/ubuntu-20.04-minimal-cloudimg-amd64.img"

  # Dostosuj obraz
  log "Dostosowywanie obrazu..."
  qemu-img resize "$STATE_DIR/images/ubuntu-base.img" 20G

  # Utwórz plik cloud-init
  mkdir -p "$STATE_DIR/cloud-init"

  cat > "$STATE_DIR/cloud-init/meta-data" << EOF
instance-id: digital-twin-vm
local-hostname: digital-twin-vm
EOF

  cat > "$STATE_DIR/cloud-init/user-data" << EOF
#cloud-config
hostname: digital-twin-vm
users:
  - name: root
    lock_passwd: false
    hashed_passwd: $(openssl passwd -6 "digital-twin-password")
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
      sed -i "s/bridge_url:.*/bridge_url: http:\/\/$VM_IP:$DEFAULT_BRIDGE_PORT\/api\/v1\/update_state/" "$INSTALL_DIR/agent-config.json"

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
    log_error "Sprawdź stan VM przy użyciu 'virsh console $VM_NAME'."
    return 1
  fi

  log_success "Bazowa maszyna wirtualna utworzona pomyślnie."
}

# Instalacja VM Bridge na VM
install_vm_bridge_on_vm() {
  log "Instalowanie VM Bridge na maszynie wirtualnej..."

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
          vm_password: digital-twin-password
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
}

# Uruchomienie usług
start_services() {
  log "Uruchamianie usług cyfrowego bliźniaka..."

  # Przeładuj daemona systemd
  systemctl daemon-reload

  # Włącz i uruchom usługi
  systemctl enable digital-twin-agent.service
  systemctl start digital-twin-agent.service

  log_success "Usługi uruchomione pomyślnie."

  # Sprawdź status usług
  log "Status usługi agenta:"
  systemctl status digital-twin-agent.service --no-pager
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
  echo -e "   Status: $(systemctl is-active digital-twin-agent.service)"
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
  echo -e "   journalctl -fu digital-twin-agent"
  echo -e "   ssh -i $CONFIG_DIR/ssh/id_rsa root@$VM_IP journalctl -fu vm-bridge"
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
  configure_vm_bridge
  install_agent
  install_vm_bridge_service
  create_base_vm
  install_vm_bridge_on_vm
  start_services
  show_summary

  log_success "Instalacja zakończona pomyślnie!"
}

# Uruchom główną funkcję
main "$@"