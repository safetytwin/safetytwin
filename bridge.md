# VM Bridge

Most między systemem monitorującym a wirtualną maszyną cyfrowego bliźniaka. Zarządza procesem tworzenia, aktualizacji i przełączania między snapshotami VM.

## Funkcje

- Odbieranie danych o stanie systemu z agenta
- Zarządzanie snapshotami maszyny wirtualnej (tworzenie, przełączanie)
- Generowanie konfiguracji usług na podstawie zebranych danych
- Stosowanie konfiguracji do VM za pomocą Ansible
- Udostępnianie API REST do zarządzania systemem

## Wymagania

- Python 3.7+
- libvirt z obsługą Python
- Ansible 2.9+
- QEMU/KVM
- Następujące biblioteki Python:
  - pyyaml
  - jinja2
  - flask
  - deepdiff
  - paramiko
  - libvirt-python
  - docker

## Instalacja

### Ręczna

```bash
# Utwórz katalogi
sudo mkdir -p /opt/safetytwin
sudo mkdir -p /etc/safetytwin/templates
sudo mkdir -p /var/lib/safetytwin/states
sudo mkdir -p /var/log/safetytwin

# Skopiuj pliki
sudo cp -r vm_bridge.py /opt/safetytwin/
sudo cp -r utils/ /opt/safetytwin/
sudo cp -r templates/ /etc/safetytwin/

# Utwórz konfigurację
sudo cat > /etc/safetytwin/vm-bridge.yaml << EOF
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
EOF

# Utwórz usługę systemd
sudo cat > /etc/systemd/system/safetytwin-bridge.service << EOF
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
EOF

# Załaduj i uruchom usługę
sudo systemctl daemon-reload
sudo systemctl enable --now safetytwin-bridge.service
```

### Z Makefile

```bash
# W głównym katalogu projektu
sudo make vm-bridge
sudo make install
```

## Konfiguracja

VM Bridge jest konfigurowany przez plik YAML. Domyślna lokalizacja to `/etc/safetytwin/vm-bridge.yaml`.

```yaml
vm_name: safetytwin-vm          # Nazwa maszyny wirtualnej
libvirt_uri: qemu:///system       # URI do libvirt
vm_user: root                     # Użytkownik VM
vm_password: safetytwin-password # Hasło (opcjonalne, lepiej użyć klucza)
vm_key_path: /etc/safetytwin/ssh/id_rsa # Ścieżka do klucza SSH
ansible_inventory: /etc/safetytwin/inventory.yml # Plik inwentarza Ansible
ansible_playbook: /opt/safetytwin/apply_services.yml # Playbook Ansible
state_dir: /var/lib/safetytwin/states # Katalog na dane stanu
templates_dir: /etc/safetytwin/templates # Katalog szablonów
max_snapshots: 10                 # Maksymalna liczba przechowywanych snapshotów
```

## Uruchamianie

```bash
# Uruchom bezpośrednio
sudo /opt/safetytwin/vm_bridge.py --config /etc/safetytwin/vm-bridge.yaml --port 5678

# Lub przez systemd
sudo systemctl start safetytwin-bridge
```

## Monitorowanie

```bash
# Sprawdź status usługi
sudo systemctl status safetytwin-bridge

# Sprawdź logi
sudo journalctl -fu safetytwin-bridge

# Sprawdź bezpośrednio plik dziennika
tail -f /var/log/safetytwin/vm-bridge.log
```

## API REST

VM Bridge udostępnia API REST do zarządzania systemem.

### Endpoints

#### `POST /api/v1/update_state`

Aktualizuje stan systemu na podstawie danych przesłanych przez agenta.

**Wejście:**
```json
{
  "timestamp": "2025-05-10T12:34:56Z",
  "hardware": { ... },
  "services": [ ... ],
  "processes": [ ... ]
}
```

**Wyjście (zmieniony stan):**
```json
{
  "status": "updated",
  "state_id": "a1b2c3d4e5f6",
  "snapshot": "state_1620123456",
  "changes": { ... }
}
```

**Wyjście (brak zmian):**
```json
{
  "status": "no_changes",
  "state_id": "a1b2c3d4e5f6"
}
```

#### `GET /api/v1/snapshots`

Zwraca listę dostępnych snapshotów.

**Wyjście:**
```json
{
  "status": "success",
  "snapshots": {
    "current": "state_1620123456",
    "history": [
      "state_1620123456",
      "state_1620123123",
      "state_1620122789"
    ]
  }
}
```

#### `POST /api/v1/snapshots/{name}`

Przywraca stan VM do wskazanego snapshotu.

**Wyjście (sukces):**
```json
{
  "status": "success",
  "message": "Przywrócono snapshot state_1620123123"
}
```

**Wyjście (błąd):**
```json
{
  "status": "error",
  "message": "Nie udało się przywrócić snapshotu state_1620123123"
}
```

#### `GET /api/v1/status`

Zwraca aktualny status VM Bridge.

**Wyjście:**
```json
{
  "status": "running",
  "vm_status": "running",
  "current_snapshot": "state_1620123456",
  "api_version": "1.0",
  "uptime": 3600
}
```

## Architektura

VM Bridge składa się z następujących głównych modułów:

1. **vm_bridge.py** - Główny skrypt, zarządza cyklem życia VM Bridge i udostępnia API REST
2. **utils/** - Moduły pomocnicze
   - **config.py** - Zarządzanie konfiguracją
   - **state_store.py** - Przechowywanie i zarządzanie stanem
   - **vm_manager.py** - Zarządzanie maszyną wirtualną (libvirt)
   - **service_generator.py** - Generowanie konfiguracji usług

## Szablony

VM Bridge używa szablonów Jinja2 do generowania konfiguracji dla VM. Szablony znajdują się w katalogu `/etc/safetytwin/templates/`.

### process_launcher.sh.j2

Szablon skryptu uruchamiającego proces w VM.

```bash
#!/bin/bash
# Skrypt wygenerowany automatycznie przez system cyfrowego bliźniaka
# Proces: {{ item.name }} (PID: {{ item.pid }})

# Ustaw zmienne środowiskowe
{% if item.environment is defined %}
{% for env in item.environment %}
export {{ env }}
{% endfor %}
{% endif %}

# Uruchom proces
{% if item.cmdline is defined and item.cmdline|length > 0 %}
exec {{ item.cmdline|join(' ') }}
{% else %}
exec {{ item.name }}
{% endif %}
```

### process_service.service.j2

Szablon usługi systemd dla procesu.

```ini
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

# Limitowanie zasobów
{% if item.cpu_percent is defined %}
CPUQuota={{ (item.cpu_percent * 1.5) | int }}%
{% endif %}
{% if item.memory_percent is defined and item.memory_limit_mb is defined %}
MemoryLimit={{ item.memory_limit_mb }}M
{% endif %}

[Install]
WantedBy=multi-user.target
```

## Interakcja z Ansible

VM Bridge używa Ansible do konfiguracji VM. Playbook Ansible jest wywoływany za każdym razem, gdy wykryte zostaną zmiany w stanie systemu.

### Przykładowe użycie:

```python
# Generowanie konfiguracji usług
service_config = service_generator.generate_service_config(state_data)

# Zastosowanie konfiguracji do VM
success = vm_manager.apply_service_config(service_config)
```

## Interakcja z libvirt

VM Bridge używa libvirt do zarządzania maszyną wirtualną (tworzenie, uruchamianie, snapshooting).

### Przykładowe użycie:

```python
# Tworzenie snapshotu
snapshot_name = vm_manager.create_snapshot("state_" + str(int(time.time())))

# Przywracanie snapshotu
success = vm_manager.revert_to_snapshot(snapshot_name)
```

## Rozwiązywanie Problemów

### VM Bridge nie uruchamia się

1. Sprawdź logi: `sudo journalctl -fu safetytwin-bridge`
2. Upewnij się, że libvirt działa: `sudo systemctl status libvirtd`
3. Sprawdź, czy maszyna wirtualna istnieje: `sudo virsh list --all`

### Problemy z połączeniem z VM

1. Sprawdź status VM: `sudo virsh domstate safetytwin-vm`
2. Sprawdź adres IP VM: `sudo virsh domifaddr safetytwin-vm`
3. Sprawdź, czy SSH działa: `ssh -i /etc/safetytwin/ssh/id_rsa root@<IP-VM>`

### Problemy z aplikowaniem konfiguracji

1. Sprawdź logi Ansible: `/var/log/safetytwin/ansible.log`
2. Uruchom Ansible ręcznie: `ansible-playbook -i /etc/safetytwin/inventory.yml /opt/safetytwin/apply_services.yml -v`
3. Sprawdź, czy usługi na VM działają: `ssh -i /etc/safetytwin/ssh/id_rsa root@<IP-VM> "systemctl status"`

## Licencja

Ten projekt jest udostępniany na licencji. Zobacz plik [LICENSE](../LICENSE).