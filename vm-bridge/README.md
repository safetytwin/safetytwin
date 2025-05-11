# VM Bridge

VM Bridge to komponent systemu SafetyTwin, który zarządza komunikacją między systemem monitorowania a maszyną wirtualną (VM). Umożliwia tworzenie i zarządzanie snapshotami VM oraz aplikowanie konfiguracji usług.

## Funkcje

- Zarządzanie snapshotami maszyny wirtualnej
- Sprawdzanie połączenia SSH z maszyną wirtualną
- Aplikowanie konfiguracji usług za pomocą Ansible
- Zarządzanie stanem maszyny wirtualnej
- API REST do interakcji z VM Bridge
- Modularne narzędzia: konfiguracja, logowanie, wysyłanie stanu (utils)
- Testy jednostkowe i integracyjne
- Dokumentacja API

## Struktura projektu

```
vm-bridge/
├── main.py                # Główny serwer Flask (API REST)
├── utils/                 # Narzędzia pomocnicze (config, sender, logging, state_store)
│   ├── config.py
│   ├── sender.py
│   ├── logging.py
│   └── state_store.py
├── ansible/               # Pliki Ansible do konfiguracji VM
│   ├── apply_services.yml # Główny playbook Ansible
│   └── templates/         # Szablony Jinja2 dla Ansible
├── requirements.txt       # Zależności projektu
├── setup.py               # Instalator pakietu Python
├── README.md              # Dokumentacja komponentu VM Bridge
└── tests/                 # Testy jednostkowe i integracyjne
```

## Instalacja

1. Zainstaluj wymagane zależności:

```bash
pip install .
```
lub
```bash
pip install -r requirements.txt
```

2. Utwórz plik konfiguracyjny `/etc/digital-twin/vm-bridge.yaml` z przykładową zawartością:

```yaml
libvirt_uri: "qemu:///system"
vm_user: "user"
vm_key_path: "/path/to/ssh/key"
ansible_inventory: "/etc/vm-bridge/inventory.yml"
ansible_playbook: "/etc/vm-bridge/apply_services.yml"
state_dir: "/var/lib/vm-bridge/states"
max_snapshots: 10
bridge_url: "http://localhost:5678/api/v1/update_state"
```

## Uruchamianie API

Aby uruchomić API VM Bridge, wykonaj:

```bash
python main.py --config /etc/digital-twin/vm-bridge.yaml --port 5678 --log /tmp/vm-bridge.log --verbose
```

Parametry:
- `--config`: Ścieżka do pliku konfiguracyjnego (domyślnie: `/etc/digital-twin/vm-bridge.yaml`)
- `--port`: Port nasłuchiwania (domyślnie: 5678)
- `--log`: Ścieżka do pliku logów (domyślnie: `/var/log/digital-twin/vm-bridge.log`)
- `--verbose`: Szczegółowe logowanie

- `--host`: Host do nasłuchiwania (domyślnie: 0.0.0.0)
- `--port`: Port do nasłuchiwania (domyślnie: 5678)
- `--vm-name`: Nazwa maszyny wirtualnej (domyślnie: digital-twin)
- `--config`: Ścieżka do pliku konfiguracyjnego (domyślnie: /etc/vm-bridge.yaml)
- `--debug`: Uruchom w trybie debug
- `--log-level`: Poziom logowania (debug, info, warning, error, critical)
- `--log-file`: Ścieżka do pliku logów (domyślnie: /var/log/vm-bridge.log)

## Endpointy API

### Aktualizacja stanu

```
POST /api/v1/update_state
```

Przykładowe dane:
```json
{
  "services": [
    {
      "name": "nginx",
      "type": "systemd",
      "status": "active",
      "pid": 1234
    },
    {
      "name": "mysql",
      "type": "docker",
      "status": "running",
      "image": "mysql:8.0",
      "ports": [
        {
          "container_port": 3306,
          "host_port": 3306,
          "host_ip": "0.0.0.0"
        }
      ]
    }
  ],
  "processes": [
    {
      "name": "nginx",
      "pid": 1234,
      "cmdline": ["/usr/sbin/nginx", "-g", "daemon off;"],
      "username": "www-data",
      "cpu_percent": 0.5,
      "memory_percent": 1.2
    }
  ],
  "hardware": {
    "hostname": "server1",
    "cpu": {
      "count_logical": 4,
      "model": "Intel(R) Core(TM) i7"
    },
    "memory": {
      "total_gb": 8
    },
    "platform": "linux"
  }
}
```

### Listowanie snapshotów

```
GET /api/v1/snapshots
```

Przykładowa odpowiedź:
```json
{
  "current": "state_20230501_120000",
  "history": ["base_state", "state_20230501_120000"]
}
```

### Przywracanie snapshotu

```
POST /api/v1/snapshots/<name>
```

Przykładowa odpowiedź:
```json
{
  "status": "reverted",
  "snapshot": "state_20230501_120000"
}
```

### Usuwanie snapshotu

```
DELETE /api/v1/snapshots/<name>
```

### Status VM Bridge

```
GET /api/v1/status
```

Przykładowa odpowiedź:
```json
{
  "status": "ok",
  "vm_name": "digital-twin",
  "vm_ip": "192.168.122.100",
  "vm_running": true,
  "current_snapshot": "state_20230501_120000",
  "snapshot_count": 2
}
```

## Przykłady użycia

### Aktualizacja stanu

```bash
curl -X POST -H "Content-Type: application/json" -d '{"services":[{"name":"nginx","type":"systemd","status":"active"}],"processes":[],"hardware":{"hostname":"server1"}}' http://localhost:5678/api/v1/update_state
```

### Listowanie snapshotów

```bash
curl http://localhost:5678/api/v1/snapshots
```

### Przywracanie snapshotu

```bash
curl -X POST http://localhost:5678/api/v1/snapshots/state_20230501_120000
```

### Sprawdzanie statusu

```bash
curl http://localhost:5678/api/v1/status
```

## Konfiguracja Ansible

VM Bridge używa Ansible do aplikowania konfiguracji usług do maszyny wirtualnej. Proces ten jest automatycznie wykonywany po wykryciu zmian w stanie monitorowanego systemu.

### Playbook Ansible

Główny playbook Ansible (`ansible/apply_services.yml`) wykonuje następujące zadania:

1. **Konfiguracja systemu** - ustawia hostname i zmienne środowiskowe
2. **Zarządzanie usługami systemd** - uruchamia, zatrzymuje i konfiguruje usługi systemd
3. **Zarządzanie kontenerami Docker** - tworzy, aktualizuje i usuwa kontenery Docker
4. **Zarządzanie procesami** - tworzy usługi systemd dla niezależnych procesów

### Szablony

Playbook wykorzystuje dwa główne szablony:

- **process_launcher.sh.j2** - generuje skrypty uruchamiające dla procesów
- **process_service.service.j2** - tworzy pliki usług systemd dla procesów

### Uruchamianie ręczne

W razie potrzeby możesz ręcznie uruchomić playbook Ansible:

```bash
ansible-playbook -i /path/to/inventory.yml /path/to/apply_services.yml -e "config_file=/path/to/service_config.yaml"
```

Zwykle jednak VM Bridge automatycznie wywołuje playbook podczas aktualizacji stanu.
