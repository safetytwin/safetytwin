# Makefile dla Projektu Cyfrowego Bliźniaka
# Autor: Tom Sapletta

# Zmienne
SHELL := /bin/bash
INSTALL_DIR = /opt/digital-twin
CONFIG_DIR = /etc/digital-twin
STATE_DIR = /var/lib/digital-twin
LOG_DIR = /var/log/digital-twin

VM_NAME = digital-twin-vm
VM_MEMORY = 4096
VM_VCPUS = 2
BRIDGE_PORT = 5678
AGENT_INTERVAL = 10

GO_VERSION = 1.20
PYTHON_VERSION = 3.9

# Upewnij się, że sudo jest dostępne
SUDO = sudo

# Sprawdź, czy użytkownik jest rootem
ifeq ($(shell id -u),0)
  SUDO =
endif

# Cele
.PHONY: all install uninstall agent vm-bridge vm dependencies clean help test

all: help

help:
	@echo "Projekt Cyfrowego Bliźniaka - System Wdrożeniowy"
	@echo ""
	@echo "Dostępne cele:"
	@echo "  install       - Zainstaluj cały system (wymaga uprawnień roota)"
	@echo "  uninstall     - Usuń cały system (wymaga uprawnień roota)"
	@echo "  agent         - Zbuduj tylko agenta"
	@echo "  vm-bridge     - Zbuduj tylko VM Bridge"
	@echo "  vm            - Utwórz tylko maszynę wirtualną"
	@echo "  dependencies  - Zainstaluj zależności"
	@echo "  clean         - Wyczyść pliki tymczasowe"
	@echo "  test          - Uruchom testy"
	@echo ""
	@echo "Przykład użycia:"
	@echo "  make install VM_MEMORY=8192 VM_VCPUS=4"
	@echo ""

install: dependencies agent vm-bridge vm
	@echo "Instalowanie systemu cyfrowego bliźniaka..."
	
	# Utwórz katalogi
	$(SUDO) mkdir -p $(INSTALL_DIR)
	$(SUDO) mkdir -p $(CONFIG_DIR)
	$(SUDO) mkdir -p $(STATE_DIR)
	$(SUDO) mkdir -p $(LOG_DIR)
	
	# Skopiuj pliki
	$(SUDO) cp -r agent/bin/digital-twin-agent $(INSTALL_DIR)/
	$(SUDO) cp -r vm-bridge/vm_bridge.py $(INSTALL_DIR)/
	$(SUDO) cp -r vm-bridge/utils $(INSTALL_DIR)/utils
	$(SUDO) cp -r vm-bridge/templates $(CONFIG_DIR)/templates
	$(SUDO) cp -r ansible/apply_services.yml $(INSTALL_DIR)/
	
	# Utwórz konfigurację
	$(SUDO) cp configs/agent-config.json $(CONFIG_DIR)/
	$(SUDO) cp configs/vm-bridge.yaml $(CONFIG_DIR)/
	
	# Ustaw uprawnienia
	$(SUDO) chmod +x $(INSTALL_DIR)/digital-twin-agent
	$(SUDO) chmod +x $(INSTALL_DIR)/vm_bridge.py
	
	# Utwórz usługi systemd
	$(SUDO) cp systemd/digital-twin-agent.service /etc/systemd/system/
	$(SUDO) cp systemd/digital-twin-bridge.service /etc/systemd/system/
	$(SUDO) systemctl daemon-reload
	
	@echo "Instalacja zakończona pomyślnie."
	@echo "Aby uruchomić usługi, wykonaj:"
	@echo "  sudo systemctl enable --now digital-twin-agent.service"
	@echo "  sudo systemctl enable --now digital-twin-bridge.service"

uninstall:
	@echo "Odinstalowywanie systemu cyfrowego bliźniaka..."
	
	# Zatrzymaj usługi
	-$(SUDO) systemctl stop digital-twin-agent.service || true
	-$(SUDO) systemctl stop digital-twin-bridge.service || true
	-$(SUDO) systemctl disable digital-twin-agent.service || true
	-$(SUDO) systemctl disable digital-twin-bridge.service || true
	
	# Usuń usługi systemd
	-$(SUDO) rm -f /etc/systemd/system/digital-twin-agent.service || true
	-$(SUDO) rm -f /etc/systemd/system/digital-twin-bridge.service || true
	-$(SUDO) systemctl daemon-reload
	
	# Zatrzymaj VM
	-$(SUDO) virsh destroy $(VM_NAME) || true
	-$(SUDO) virsh undefine $(VM_NAME) --remove-all-storage || true
	
	# Usuń katalogi
	-$(SUDO) rm -rf $(INSTALL_DIR) || true
	-$(SUDO) rm -rf $(CONFIG_DIR) || true
	-$(SUDO) rm -rf $(STATE_DIR) || true
	-$(SUDO) rm -rf $(LOG_DIR) || true
	
	@echo "Odinstalowanie zakończone pomyślnie."

dependencies:
	@echo "Instalowanie zależności..."
	
	# Wykryj system
	if command -v apt-get &> /dev/null; then \
		$(SUDO) apt-get update; \
		$(SUDO) apt-get install -y git curl wget python3 python3-pip libvirt-clients libvirt-daemon-system qemu-kvm qemu-utils python3-libvirt ansible genisoimage golang-$(GO_VERSION); \
	elif command -v dnf &> /dev/null; then \
		$(SUDO) dnf install -y git curl wget python3 python3-pip libvirt-client libvirt-daemon-system qemu-kvm qemu-img python3-libvirt ansible genisoimage golang; \
	elif command -v yum &> /dev/null; then \
		$(SUDO) yum install -y git curl wget python3 python3-pip libvirt-client libvirt-daemon-system qemu-kvm qemu-img python3-libvirt ansible genisoimage golang; \
	else \
		echo "Nieobsługiwany menedżer pakietów. Zainstaluj ręcznie:"; \
		echo "git curl wget python3 python3-pip libvirt qemu ansible genisoimage golang"; \
		exit 1; \
	fi
	
	# Instalacja zależności Python
	$(SUDO) pip3 install pyyaml jinja2 flask deepdiff paramiko libvirt-python docker
	
	# Zależności Go
	cd agent && go mod download
	
	@echo "Zależności zainstalowane pomyślnie."

agent:
	@echo "Budowanie agenta..."
	
	# Utwórz katalogi dla agenta
	mkdir -p agent/bin
	
	# Zbuduj agenta
	cd agent && go build -o bin/digital-twin-agent main.go
	
	@echo "Agent zbudowany pomyślnie."

vm-bridge:
	@echo "Przygotowanie VM Bridge..."
	
	# Utwórz szablony
	mkdir -p vm-bridge/templates
	
	# Utwórz konfigurację VM Bridge
	mkdir -p configs
	cat > configs/vm-bridge.yaml << EOF
vm_name: $(VM_NAME)
libvirt_uri: qemu:///system
vm_user: root
vm_password: digital-twin-password
vm_key_path: $(CONFIG_DIR)/ssh/id_rsa
ansible_inventory: $(CONFIG_DIR)/inventory.yml
ansible_playbook: $(INSTALL_DIR)/apply_services.yml
state_dir: $(STATE_DIR)/states
templates_dir: $(CONFIG_DIR)/templates
max_snapshots: 10
EOF
	
	# Utwórz konfigurację agenta
	cat > configs/agent-config.json << EOF
{
  "interval": $(AGENT_INTERVAL),
  "bridge_url": "http://localhost:$(BRIDGE_PORT)/api/v1/update_state",
  "log_file": "$(LOG_DIR)/agent.log",
  "state_dir": "$(STATE_DIR)/agent-states",
  "include_processes": true,
  "include_network": true,
  "verbose": false
}
EOF
	
	# Utwórz usługi systemd
	mkdir -p systemd
	cat > systemd/digital-twin-agent.service << EOF
[Unit]
Description=Digital Twin Agent
After=network.target

[Service]
Type=simple
ExecStart=$(INSTALL_DIR)/digital-twin-agent -config $(CONFIG_DIR)/agent-config.json
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=digital-twin-agent
User=root
Group=root
WorkingDirectory=$(INSTALL_DIR)

[Install]
WantedBy=multi-user.target
EOF

	cat > systemd/digital-twin-bridge.service << EOF
[Unit]
Description=Digital Twin VM Bridge
After=network.target libvirtd.service

[Service]
Type=simple
ExecStart=$(INSTALL_DIR)/vm_bridge.py --config $(CONFIG_DIR)/vm-bridge.yaml --port $(BRIDGE_PORT)
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=digital-twin-bridge
User=root
Group=root
WorkingDirectory=$(INSTALL_DIR)

[Install]
WantedBy=multi-user.target
EOF

	@echo "VM Bridge przygotowany pomyślnie."

vm:
	@echo "Tworzenie maszyny wirtualnej..."
	
	# Utwórz katalogi dla VM
	$(SUDO) mkdir -p $(STATE_DIR)/images
	$(SUDO) mkdir -p $(STATE_DIR)/cloud-init
	
	# Pobierz bazowy obraz Ubuntu
	if [ ! -f $(STATE_DIR)/images/ubuntu-base.img ]; then \
		$(SUDO) wget -O $(STATE_DIR)/images/ubuntu-base.img "https://cloud-images.ubuntu.com/minimal/releases/focal/release/ubuntu-20.04-minimal-cloudimg-amd64.img"; \
	fi
	
	# Dostosuj obraz
	$(SUDO) qemu-img resize $(STATE_DIR)/images/ubuntu-base.img 20G
	$(SUDO) cp $(STATE_DIR)/images/ubuntu-base.img $(STATE_DIR)/images/vm.qcow2
	
	# Utwórz katalog na klucze SSH
	$(SUDO) mkdir -p $(CONFIG_DIR)/ssh
	
	# Wygeneruj klucz SSH
	if [ ! -f $(CONFIG_DIR)/ssh/id_rsa ]; then \
		$(SUDO) ssh-keygen -t rsa -b 4096 -f $(CONFIG_DIR)/ssh/id_rsa -N "" -C "digital-twin@localhost"; \
	fi
	
	# Utwórz plik cloud-init meta-data
	cat > $(STATE_DIR)/cloud-init/meta-data << EOF
instance-id: digital-twin-vm
local-hostname: digital-twin-vm
EOF

	# Utwórz plik cloud-init user-data
	cat > $(STATE_DIR)/cloud-init/user-data << EOF
#cloud-config
hostname: digital-twin-vm
users:
  - name: root
    lock_passwd: false
    hashed_passwd: $(shell mkpasswd -m sha-512 -S $(shell head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8) "digital-twin-password" 2>/dev/null || echo '$6$randomsalt$yboGI5eoKkxLrUw0QRuGRTMExQDSIJQ.frd9S.9I15jgnEzvxTLbXbKmpEHzXHZiwBzEApLM8msk8s3YV.byt.')
    ssh_authorized_keys:
      - $(shell cat $(CONFIG_DIR)/ssh/id_rsa.pub)
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
	genisoimage -output $(STATE_DIR)/cloud-init/seed.iso -volid cidata -joliet -rock $(STATE_DIR)/cloud-init/meta-data $(STATE_DIR)/cloud-init/user-data
	
	# Utwórz XML definicji VM
	cat > $(STATE_DIR)/vm-definition.xml << EOF
<domain type='kvm'>
  <n>$(VM_NAME)</n>
  <memory unit='KiB'>$(shell echo $(VM_MEMORY) "*" 1024 | bc)</memory>
  <vcpu placement='static'>$(VM_VCPUS)</vcpu>
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
      <source file='$(STATE_DIR)/images/vm.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$(STATE_DIR)/cloud-init/seed.iso'/>
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
	-$(SUDO) virsh define $(STATE_DIR)/vm-definition.xml
	-$(SUDO) virsh start $(VM_NAME)
	
	@echo "Czekanie na uruchomienie VM i konfigurację cloud-init..."
	sleep 60  # Daj VM czas na uruchomienie i skonfigurowanie
	
	# Pobierz adres IP VM
	IP=$($(SUDO) virsh domifaddr $(VM_NAME) | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1); \
	if [ -n "$IP" ]; then \
		echo "VM uruchomiona pod adresem: $IP"; \
		# Utwórz plik inwentarza Ansible; \
		$(SUDO) mkdir -p $(dirname $(CONFIG_DIR)/inventory.yml); \
		cat > $(CONFIG_DIR)/inventory.yml << EOF_INVENTORY; \
all: \
  hosts: \
    digital_twin: \
      ansible_host: $IP \
      ansible_user: root \
      ansible_ssh_private_key_file: $(CONFIG_DIR)/ssh/id_rsa \
      ansible_become: yes \
EOF_INVENTORY \
	else \
		echo "Nie można uzyskać adresu IP VM. Sprawdź stan VM przy użyciu 'virsh console $(VM_NAME)'"; \
	fi
	
	@echo "Maszyna wirtualna utworzona pomyślnie."

clean:
	@echo "Czyszczenie plików tymczasowych..."
	
	# Wyczyść pliki agenta
	rm -rf agent/bin
	
	# Wyczyść pliki konfiguracyjne
	rm -rf configs
	rm -rf systemd
	
	@echo "Czyszczenie zakończone pomyślnie."

test:
	@echo "Uruchamianie testów..."
	
	# Testy agenta
	cd agent && go test ./...
	
	# Testy VM Bridge
	cd vm-bridge && python3 -m unittest discover -s tests
	
	@echo "Testy zakończone pomyślnie."
