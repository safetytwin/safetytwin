---

## 📚 Menu nawigacyjne

- [README (Start)](../README.md)
- [Instrukcja instalacji](../INSTALL.md)
- [Stan instalatora](../INSTALL_STATE.md)
- [Wynik instalacji](../INSTALL_RESULT.yaml)
- [FAQ](faq.md)
- [Rozwiązywanie problemów](troubleshooting.md)
- [Przegląd architektury](overview.md)
- [Agent](agent.md)
- [VM Bridge](vm-bridge.md)
- [Ansible](ansible.md)
- [API](api.md)
- [Strategia](../STRATEGIA.md)

---

# Szczegółowa instrukcja instalacji

Ten dokument zawiera szczegółowe informacje na temat instalacji i konfiguracji systemu cyfrowego bliźniaka.

## Spis treści

1. [Wymagania systemowe](#wymagania-systemowe)
2. [Szybka instalacja](#szybka-instalacja)
3. [Instalacja ręczna](#instalacja-ręczna)
   - [Instalacja agenta](#instalacja-agenta)
   - [Instalacja VM Bridge](#instalacja-vm-bridge)
   - [Tworzenie maszyny wirtualnej](#tworzenie-maszyny-wirtualnej)
4. [Konfiguracja](#konfiguracja)
   - [Konfiguracja agenta](#konfiguracja-agenta)
   - [Konfiguracja VM Bridge](#konfiguracja-vm-bridge)
   - [Konfiguracja VM](#konfiguracja-vm)
5. [Uruchamianie systemu](#uruchamianie-systemu)
6. [Weryfikacja instalacji](#weryfikacja-instalacji)
7. [Rozwiązywanie problemów](#rozwiązywanie-problemów)

## Wymagania systemowe

### Dla systemu hosta

- System operacyjny Linux (testowany na Ubuntu 20.04+, Debian 11+, CentOS 8+)
- CPU z obsługą wirtualizacji (VT-x/AMD-V)
- Minimum 8GB RAM (4GB dla VM + 4GB dla systemu)
- Minimum 50GB wolnego miejsca na dysku
- Następujące pakiety:
  - libvirt, QEMU/KVM
  - Python 3.7+
  - Ansible 2.9+
  - Docker (opcjonalnie)
  - Go 1.18+ (opcjonalnie, tylko do kompilacji agenta)

### Dla maszyny wirtualnej

- Minimum 4GB RAM
- Minimum 20GB wolnego miejsca na dysku
- System operacyjny Linux (Ubuntu 20.04 zalecany)
- Python 3.7+
- Ansible 2.9+

---

## Wybór obrazu bazowego i użytkownika VM

Podczas pierwszego uruchomienia skryptu `create-vm.sh` możesz wybrać obraz bazowy, użytkownika i hasło. Wybrane ustawienia zostaną zapisane w pliku `.env` i będą używane domyślnie przy kolejnych uruchomieniach.

| Nr | System/Obraz                                    | Domyślny użytkownik | Hasło   | Link                                                                 |
|----|-------------------------------------------------|---------------------|---------|----------------------------------------------------------------------|
| 1  | Ubuntu 22.04 Server Cloud Image                 | ubuntu              | ubuntu  | https://cloud-images.ubuntu.com/releases/jammy/release/20250508/ubuntu-22.04-server-cloudimg-amd64.img |
| 2  | Ubuntu 22.04 Minimal Cloud Image                | ubuntu              | ubuntu  | https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img |
| 3  | Debian 12 (Bookworm) Cloud Image                | debian              | debian  | https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2              |
| 4  | CentOS 9 Stream Cloud Image                     | centos              | centos  | https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|
| 5  | Rocky Linux 9 Cloud Image                       | rocky               | rocky   | https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2           |

**Instrukcja:**
- Po uruchomieniu `create-vm.sh` wybierz numer obrazu z listy.
- Skrypt automatycznie pobierze obraz, ustawi użytkownika/hasło i zaktualizuje `.env`.
- Przy kolejnych uruchomieniach te ustawienia będą używane domyślnie (możesz je zmienić edytując `.env` lub usuwając odpowiednie zmienne).
- Docker (opcjonalnie)

## Szybka instalacja

Po instalacji lub w razie problemów z siecią VM uruchom `sudo bash repair.sh`.
Skrypt automatycznie:
- Zamyka aktywną sesję konsoli VM (jeśli istnieje),
- Diagnozuje i naprawia najczęstsze problemy z siecią oraz cloud-init,
- Zbiera logi i konfiguracje z VM do pliku `/var/lib/safetytwin/TWIN.yaml`.
- W przypadku błędów generuje instrukcje ręczne dla użytkownika.

Najszybszym sposobem na instalację systemu jest użycie dostarczonego skryptu instalacyjnego:

```bash
# Pobierz repozytorium
git clone https://github.com/safetytwin/safetytwin.git
cd safetytwin

# Uruchom skrypt instalacyjny
sudo bash scripts/install.sh
```

---

## Rozwiązywanie problemów z cloud-init i logowaniem do VM

- **Cloud-init ISO MUSI być podpięte jako CD-ROM na szynie IDE (bus=ide, device=cdrom, np. /dev/hdc lub /dev/cdrom).**
  Jeśli ISO jest podpięte inaczej (np. jako sda/sata), cloud-init NIE przetworzy user-data i nie utworzy użytkownika ani nie ustawi hasła.
- Przykład poprawnej komendy:
  ```bash
  sudo virt-install --name safetytwin-vm \
    --memory 2048 \
    --vcpus 2 \
    --disk /var/lib/safetytwin/images/ubuntu-base.img,device=disk,bus=virtio \
    --disk /var/lib/safetytwin/cloud-init/cloud-init.iso,device=cdrom,bus=ide \
    --os-variant ubuntu20.04 \
    --virt-type kvm \
    --graphics none \
    --network network=default,model=virtio \
    --import \
    --noautoconsole \
    --check path_in_use=off
  ```
- **Zawsze niszcz i usuwaj VM przed ponowną instalacją:**
  ```bash
  sudo virsh destroy safetytwin-vm || true
  sudo virsh undefine --nvram safetytwin-vm || true
  ```
- Jeśli nie możesz się zalogować na `ubuntu`/`safetytwin` i użytkownik nie istnieje w VM – oznacza to, że cloud-init nie przetworzył user-data (najczęściej z powodu złego podpięcia ISO).
- Sprawdź obecność `/dev/cdrom` lub `/dev/hdc` w VM oraz logi cloud-init (`/var/log/cloud-init.log`).
- Szczegóły i przykłady znajdziesz w `restart.sh` oraz `install.sh`.
```

Skrypt automatycznie zainstaluje wszystkie wymagane komponenty i uruchomi system.

### Opcje instalacji

Skrypt instalacyjny można dostosować za pomocą różnych opcji:

```bash
sudo bash scripts/install.sh --vm-memory 8192 --vm-vcpus 4 --bridge-port 6789
```

Dostępne opcje:

- `--vm-name NAZWA` - Nazwa maszyny wirtualnej (domyślnie: safetytwin-vm)
- `--vm-memory PAMIĘĆ` - Ilość pamięci dla VM w MB (domyślnie: 4096)
- `--vm-vcpus VCPUS` - Liczba vCPU dla VM (domyślnie: 2)
- `--bridge-port PORT` - Port dla VM Bridge (domyślnie: 5678)
- `--agent-interval SECS` - Interwał agenta w sekundach (domyślnie: 10)
- `--install-dir KATALOG` - Katalog instalacyjny (domyślnie: /opt/safetytwin)
- `--config-dir KATALOG` - Katalog konfiguracyjny (domyślnie: /etc/safetytwin)
- `--state-dir KATALOG` - Katalog stanów (domyślnie: /var/lib/safetytwin)
- `--log-dir KATALOG` - Katalog logów (domyślnie: /var/log/safetytwin)

## Instalacja ręczna

Jeśli wolisz zainstalować system ręcznie, poniżej znajdują się szczegółowe instrukcje dla każdego komponentu.

### Instalacja agenta

1. Zainstaluj wymagane pakiety:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y git golang-go build-essential

# CentOS/RHEL
sudo yum install -y git golang gcc make
```

2. Skompiluj agenta:

```bash
# Klonuj repozytorium
git clone https://github.com/safetytwin/safetytwin.git
cd safetytwin/agent

# Kompilacja
go build -o safetytwin-agent main.go
```

3. Zainstaluj agenta:

```bash
# Utwórz katalogi
sudo mkdir -p /opt/safetytwin
sudo mkdir -p /etc/safetytwin
sudo mkdir -p /var/lib/safetytwin/agent-states
sudo mkdir -p /var/log/safetytwin

# Skopiuj plik binarny
sudo cp safetytwin-agent /opt/safetytwin/

# Utwórz konfigurację
sudo bash -c 'cat > /etc/safetytwin/agent-config.json << EOF
{
  "interval": 10,
  "bridge_url": "http://localhost:5678/api/v1/update_state",
  "log_file": "/var/log/safetytwin/agent.log",
  "state_dir": "/var/lib/safetytwin/agent-states",
  "include_processes": true,
  "include_network": true,
  "verbose": false
}
EOF'

# Utwórz usługę systemd
sudo bash -c 'cat > /etc/systemd/system/safetytwin-agent.service << EOF
[Unit]
Description=Digital Twin Agent
After=network.target

[Service]
Type=simple
ExecStart=/opt/safetytwin/safetytwin-agent -config /etc/safetytwin/agent-config.json
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=safetytwin-agent
User=root
Group=root
WorkingDirectory=/opt/safetytwin

[Install]
WantedBy=multi-user.target
EOF'

# Przeładuj usługi systemd
sudo systemctl daemon-reload
```

### Instalacja VM Bridge

1. Zainstaluj wymagane pakiety:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y python3 python3-pip libvirt-clients libvirt-daemon-system python3-libvirt ansible

# CentOS/RHEL
sudo yum install -y python3 python3-pip libvirt-client libvirt-daemon-system python3-libvirt ansible
```

2. Zainstaluj zależności Python:

```bash
sudo pip3 install pyyaml jinja2 flask deepdiff paramiko libvirt-python docker
```

3. Przygotuj katalogi i pliki:

```bash
# Utwórz katalogi
sudo mkdir -p /opt/safetytwin/vm-bridge
sudo mkdir -p /etc/safetytwin/templates
sudo mkdir -p /var/lib/safetytwin/states

# Skopiuj kod
sudo cp -r vm-bridge/* /opt/safetytwin/vm-bridge/
sudo cp vm_bridge.py /opt/safetytwin/
sudo chmod +x /opt/safetytwin/vm_bridge.py

# Skopiuj szablony
sudo cp -r ansible/templates/* /etc/safetytwin/templates/
sudo cp ansible/apply_services.yml /opt/safetytwin/

# Utwórz konfigurację
sudo bash -c 'cat > /etc/safetytwin/vm-bridge.yaml << EOF
vm_name: safetytwin-vm
libvirt_uri: qemu:///system
vm_user: root
vm_password: safetytwin-password
vm_key_path: /etc/safetytwin/ssh/id_rsa
ansible_inventory: /etc/safetytwin/inventory.yml
ansible_playbook: /opt/safetytwin/apply_services.yml
state_dir: /var/lib/safetytwin/states
templates_dir: /etc/safetytwin/templates
max_snapshots: 10
EOF'

# Utwórz usługę systemd
sudo bash -c 'cat > /etc/systemd/system/safetytwin-bridge.service << EOF
[Unit]
Description=Digital Twin VM Bridge
After=network.target libvirtd.service

[Service]
Type=simple
ExecStart=/opt/safetytwin/vm_bridge.py --config /etc/safetytwin/vm-bridge.yaml --port 5678
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=safetytwin-bridge
User=root
Group=root
WorkingDirectory=/opt/safetytwin

[Install]
WantedBy=multi-user.target
EOF'

# Przeładuj usługi systemd
sudo systemctl daemon-reload
```

### Tworzenie maszyny wirtualnej

1. Przygotuj katalogi:

```bash
sudo mkdir -p /var/lib/safetytwin/images
sudo mkdir -p /var/lib/safetytwin/cloud-init
sudo mkdir -p /etc/safetytwin/ssh
```

2. Wygeneruj klucz SSH:

```bash
sudo ssh-keygen -t rsa -b 4096 -f /etc/safetytwin/ssh/id_rsa -N "" -C "safetytwin@localhost"
```

3. Pobierz i przygotuj obraz bazowy:

```bash
sudo wget -O /var/lib/safetytwin/images/ubuntu-base.img "https://cloud-images.ubuntu.com/releases/jammy/release-20250508/ubuntu-22.04-server-cloudimg-amd64.img"

# Od wersji 2025-05-11 używamy oficjalnego Ubuntu 22.04 cloud image (Jammy Jellyfish) z https://cloud-images.ubuntu.com/releases/jammy/release-20250508/
# Cloud-init automatycznie wypisuje stan sieci i dmesg na konsolę szeregowa (ttyS0) do diagnostyki VM.
sudo qemu-img resize /var/lib/safetytwin/images/ubuntu-base.img 20G
sudo cp /var/lib/safetytwin/images/ubuntu-base.img /var/lib/safetytwin/images/vm.qcow2
```

4. Przygotuj pliki cloud-init:

```bash
# Meta-data
sudo bash -c 'cat > /var/lib/safetytwin/cloud-init/meta-data << EOF
instance-id: safetytwin-vm
local-hostname: safetytwin-vm
EOF'

# User-data
sudo bash -c 'cat > /var/lib/safetytwin/cloud-init/user-data << EOF
#cloud-config
hostname: safetytwin-vm
users:
  - name: root
    lock_passwd: false
    hashed_passwd: $(openssl passwd -6 "safetytwin-password")
    ssh_authorized_keys:
      - $(cat /etc/safetytwin/ssh/id_rsa.pub)
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
EOF'

# Generuj ISO z cloud-init
sudo genisoimage -output /var/lib/safetytwin/cloud-init/seed.iso -volid cidata -joliet -rock /var/lib/safetytwin/cloud-init/meta-data /var/lib/safetytwin/cloud-init/user-data
```

5. Zdefiniuj i uruchom maszynę wirtualną:

```bash
# Utwórz definicję VM
sudo bash -c 'cat > /var/lib/safetytwin/vm-definition.xml << EOF
<domain type="kvm">
  <n>safetytwin-vm</n>
  <memory unit="KiB">4194304</memory>
  <vcpu placement="static">2</vcpu>
  <os>
    <type arch="x86_64" machine="pc-q35-4.2">hvm</type>
    <boot dev="hd"/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode="host-model"/>
  <clock offset="utc"/>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2"/>
      <source file="/var/lib/safetytwin/images/vm.qcow2"/>
      <target dev="vda" bus="virtio"/>
    </disk>
    <disk type="file" device="cdrom">
      <driver name="qemu" type="raw"/>
      <source file="/var/lib/safetytwin/cloud-init/seed.iso"/>
      <target dev="sda" bus="sata"/>
      <readonly/>
    </disk>
    <interface type="network">
      <source network="default"/>
      <model type="virtio"/>
    </interface>
    <console type="pty"/>
    <graphics type="vnc" port="-1" autoport="yes" listen="127.0.0.1">
      <listen type="address" address="127.0.0.1"/>
    </graphics>
  </devices>
</domain>
EOF'

# Zdefiniuj i uruchom VM
sudo virsh define /var/lib/safetytwin/vm-definition.xml
sudo virsh start safetytwin-vm
```

6. Przygotuj plik inwentarza Ansible:

```bash
# Poczekaj, aż VM się uruchomi
sleep 60

# Pobierz adres IP VM
VM_IP=$(sudo virsh domifaddr safetytwin-vm | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)

# Utwórz plik inwentarza
sudo bash -c "cat > /etc/safetytwin/inventory.yml << EOF
all:
  hosts:
    digital_twin:
      ansible_host: $VM_IP
      ansible_user: root
      ansible_ssh_private_key_file: /etc/safetytwin/ssh/id_rsa
      ansible_become: yes
EOF"

# Zaktualizuj adres IP w konfiguracji agenta
sudo sed -i "s|bridge_url:.*|bridge_url: http://$VM_IP:5678/api/v1/update_state|" /etc/safetytwin/agent-config.json
```

## Konfiguracja

### Konfiguracja agenta

Agent jest konfigurowany za pomocą pliku JSON, domyślnie w `/etc/safetytwin/agent-config.json`:

```json
{
  "interval": 10,               // Interwał zbierania danych w sekundach
  "bridge_url": "http://VM_IP:5678/api/v1/update_state",  // URL do VM Bridge
  "log_file": "/var/log/safetytwin/agent.log",          // Plik dziennika
  "state_dir": "/var/lib/safetytwin/agent-states",      // Katalog na dane stanu
  "include_processes": true,    // Czy zbierać dane o procesach
  "include_network": true,      // Czy zbierać dane o sieci
  "verbose": false              // Tryb szczegółowego logowania
}
```

### Konfiguracja VM Bridge

VM Bridge jest konfigurowany za pomocą pliku YAML, domyślnie w `/etc/safetytwin/vm-bridge.yaml`:

```yaml
vm_name: safetytwin-vm          # Nazwa maszyny wirtualnej
libvirt_uri: qemu:///system       # URI do libvirt
vm_user: root                     # Użytkownik VM
vm_password: safetytwin-password # Hasło (opcjonalnie, lepiej użyć klucza)
vm_key_path: /etc/safetytwin/ssh/id_rsa # Ścieżka do klucza SSH
ansible_inventory: /etc/safetytwin/inventory.yml # Plik inwentarza Ansible
ansible_playbook: /opt/safetytwin/apply_services.yml # Playbook Ansible
state_dir: /var/lib/safetytwin/states # Katalog na dane stanu
templates_dir: /etc/safetytwin/templates # Katalog szablonów
max_snapshots: 10                 # Maksymalna liczba przechowywanych snapshotów
```

### Konfiguracja VM

Maszyna wirtualna jest domyślnie skonfigurowana z następującymi parametrami:

- Nazwa: safetytwin-vm
- Pamięć: 4GB RAM
- vCPU: 2
- Dysk: 20GB
- System: Ubuntu 20.04
- Użytkownik: root
- Hasło: safetytwin-password
- Klucz SSH: /etc/safetytwin/ssh/id_rsa

Aby zmienić te parametry, należy edytować plik definicji VM i ponownie uruchomić VM.

## Uruchamianie systemu

Aby uruchomić system:

```bash
# Uruchom usługi
sudo systemctl enable --now safetytwin-agent.service
sudo systemctl enable --now safetytwin-bridge.service

# Sprawdź status
sudo systemctl status safetytwin-agent.service
sudo systemctl status safetytwin-bridge.service
```

## Weryfikacja instalacji

Aby sprawdzić, czy system działa poprawnie:

1. Sprawdź, czy VM jest uruchomiona:

```bash
sudo virsh list --all
```

2. Sprawdź, czy agent wysyła dane:

```bash
sudo tail -f /var/log/safetytwin/agent.log
```

3. Sprawdź, czy VM Bridge odbiera dane:

```bash
sudo journalctl -fu safetytwin-bridge
```

4. Sprawdź, czy API jest dostępne:

```bash
VM_IP=$(sudo virsh domifaddr safetytwin-vm | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -n 1)
curl http://$VM_IP:5678/api/v1/status
```

## Rozwiązywanie problemów

Jeśli napotkasz problemy podczas instalacji lub działania systemu, sprawdź [Rozwiązywanie problemów](TROUBLESHOOTING.md).