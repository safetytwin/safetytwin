# Dokumentacja API
# Dokumentacja API

VM Bridge udostępnia REST API, które umożliwia interakcję z systemem cyfrowego bliźniaka. Ten dokument zawiera szczegółowy opis dostępnych endpointów, metod i parametrów.

## Informacje ogólne

- **Bazowy URL**: `http://VM_IP:5678`
- **Format danych**: JSON
- **Metody**: GET, POST
- **Uwierzytelnianie**: Brak (zalecane jest zabezpieczenie API przez ograniczenie dostępu sieciowego)

## Endpointy API

### Status systemu

Pobiera aktualny status systemu cyfrowego bliźniaka.

**Endpoint:** `/api/v1/status`  
**Metoda:** GET  
**Parametry:** Brak

**Przykładowa odpowiedź:**
```json
{
  "status": "running",
  "vm_status": "running",
  "current_snapshot": "state_1620123456",
  "api_version": "1.0",
  "uptime": 3600
}
```

**Możliwe statusy:**
- `running` - system działa poprawnie
- `error` - wystąpił błąd w systemie

### Lista snapshotów

Pobiera listę dostępnych snapshotów maszyny wirtualnej.

**Endpoint:** `/api/v1/snapshots`  
**Metoda:** GET  
**Parametry:** Brak

**Przykładowa odpowiedź:**
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

### Przywracanie snapshotu

Przywraca stan maszyny wirtualnej do wskazanego snapshotu.

**Endpoint:** `/api/v1/snapshots/{name}`  
**Metoda:** POST  
**Parametry:** Brak

**Przykładowa odpowiedź (sukces):**
```json
{
  "status": "success",
  "message": "Przywrócono snapshot state_1620123123"
}
```

**Przykładowa odpowiedź (błąd):**
```json
{
  "status": "error",
  "message": "Nie udało się przywrócić snapshotu state_1620123123"
}
```

### Historia stanów

Pobiera historię stanów systemu.

**Endpoint:** `/api/v1/history`  
**Metoda:** GET  
**Parametry:**
- `limit` (opcjonalny) - liczba stanów do pobrania (domyślnie: 10)

**Przykładowa odpowiedź:**
```json
{
  "status": "success",
  "history": [
    {
      "id": "a1b2c3d4e5f6",
      "file": "state_20250510_123456.json",
      "timestamp": "2025-05-10T12:34:56+00:00",
      "current": true
    },
    {
      "id": "b2c3d4e5f6a1",
      "file": "state_20250510_123123.json",
      "timestamp": "2025-05-10T12:31:23+00:00",
      "current": false
    }
  ]
}
```

### Aktualizacja stanu

Aktualizuje stan systemu. Ten endpoint jest używany przez agenta.

**Endpoint:** `/api/v1/update_state`  
**Metoda:** POST  
**Dane wejściowe:** Obiekt JSON zawierający stan systemu

**Przykładowe dane wejściowe:**
```json
{
  "timestamp": "2025-05-10T12:34:56Z",
  "hardware": { ... },
  "services": [ ... ],
  "processes": [ ... ]
}
```

**Przykładowa odpowiedź (stan zmieniony):**
```json
{
  "status": "updated",
  "state_id": "a1b2c3d4e5f6",
  "snapshot": "state_1620123456",
  "changes": { ... }
}
```

**Przykładowa odpowiedź (brak zmian):**
```json
{
  "status": "no_changes",
  "state_id": "a1b2c3d4e5f6"
}
```

### Informacje o VM

Pobiera szczegółowe informacje o maszynie wirtualnej.

**Endpoint:** `/api/v1/vm/info`  
**Metoda:** GET  
**Parametry:** Brak

**Przykładowa odpowiedź:**
```json
{
  "status": "success",
  "vm": {
    "name": "safetytwin-vm",
    "status": "running",
    "current_snapshot": "state_1620123456",
    "ip_address": "192.168.122.100",
    "vcpus": 2,
    "memory_kb": 4194304,
    "memory_gb": 4.0,
    "disks": [
      {
        "source": "/var/lib/safetytwin/images/vm.qcow2",
        "target": "vda"
      }
    ],
    "interfaces": [
      {
        "network": "default",
        "model": "virtio",
        "mac": "52:54:00:9c:94:7b"
      }
    ]
  }
}
```

### Zarządzanie VM

#### Uruchamianie VM

**Endpoint:** `/api/v1/vm/start`  
**Metoda:** POST  
**Parametry:** Brak

**Przykładowa odpowiedź:**
```json
{
  "status": "success",
  "message": "VM uruchomiona"
}
```

#### Zatrzymywanie VM

**Endpoint:** `/api/v1/vm/stop`  
**Metoda:** POST  
**Parametry:** Brak

**Przykładowa odpowiedź:**
```json
{
  "status": "success",
  "message": "VM zatrzymana"
}
```

#### Restart VM

**Endpoint:** `/api/v1/vm/restart`  
**Metoda:** POST  
**Parametry:** Brak

**Przykładowa odpowiedź:**
```json
{
  "status": "success",
  "message": "VM zrestartowana"
}
```

## Format danych

### Stan systemu

Stan systemu jest reprezentowany jako obiekt JSON zawierający następujące pola:

- `timestamp` - czas utworzenia stanu (ISO 8601)
- `hardware` - informacje o sprzęcie
  - `hostname` - nazwa hosta
  - `platform` - platforma (np. Linux)
  - `platform_version` - wersja platformy (np. Ubuntu 20.04)
  - `kernel_version` - wersja jądra
  - `cpu` - informacje o procesorze
    - `model` - model procesora
    - `cores_physical` - liczba fizycznych rdzeni
    - `count_logical` - liczba logicznych rdzeni
    - `usage_percent` - wykorzystanie CPU w procentach
    - `per_cpu` - wykorzystanie poszczególnych rdzeni
  - `memory` - informacje o pamięci
    - `total_gb` - całkowita ilość pamięci w GB
    - `available_gb` - dostępna pamięć w GB
    - `used_gb` - wykorzystana pamięć w GB
    - `free_gb` - wolna pamięć w GB
    - `percent` - wykorzystanie pamięci w procentach
  - `disks` - informacje o dyskach
    - `device` - urządzenie
    - `mountpoint` - punkt montowania
    - `fstype` - typ systemu plików
    - `total_gb` - całkowita pojemność w GB
    - `used_gb` - wykorzystana pojemność w GB
    - `free_gb` - wolna pojemność w GB
    - `percent` - wykorzystanie w procentach
  - `network` - informacje o interfejsach sieciowych
- `services` - lista usług
  - `name` - nazwa usługi
  - `type` - typ usługi (systemd, docker)
  - `status` - status usługi (active, running, stopped)
  - `pid` - PID procesu (opcjonalne)
  - `image` - obraz Docker (dla usług Docker)
  - `ports` - porty (dla usług Docker)
  - `volumes` - wolumeny (dla usług Docker)
  - `environment` - zmienne środowiskowe (dla usług Docker)
  - `is_llm_related` - czy usługa jest związana z LLM
- `processes` - lista procesów
  - `pid` - PID procesu
  - `name` - nazwa procesu
  - `username` - nazwa użytkownika
  - `cpu_percent` - wykorzystanie CPU w procentach
  - `memory_percent` - wykorzystanie pamięci w procentach
  - `cmdline` - linia poleceń
  - `cwd` - katalog roboczy
  - `environment` - zmienne środowiskowe
  - `is_llm_related` - czy proces jest związany z LLM

## Kody odpowiedzi HTTP

- `200 OK` - żądanie zostało przetworzone pomyślnie
- `400 Bad Request` - nieprawidłowe żądanie (np. brak wymaganych parametrów)
- `404 Not Found` - zasób nie został znaleziony (np. snapshot)
- `500 Internal Server Error` - wewnętrzny błąd serwera

## Przykłady użycia

### Curl

#### Pobieranie statusu systemu

```bash
curl -X GET http://VM_IP:5678/api/v1/status
```

#### Pobieranie listy snapshotów

```bash
curl -X GET http://VM_IP:5678/api/v1/snapshots
```

#### Przywracanie snapshotu

```bash
curl -X POST http://VM_IP:5678/api/v1/snapshots/state_1620123123
```

#### Pobieranie historii stanów

```bash
curl -X GET http://VM_IP:5678/api/v1/history?limit=5
```

#### Uruchamianie VM

```bash
curl -X POST http://VM_IP:5678/api/v1/vm/start
```

### Python

#### Pobieranie statusu systemu

```python
import requests

response = requests.get("http://VM_IP:5678/api/v1/status")
data = response.json()
print(data)
```

#### Przywracanie snapshotu

```python
import requests

response = requests.post("http://VM_IP:5678/api/v1/snapshots/state_1620123123")
data = response.json()
print(data)
```

#### Aktualizacja stanu (używane przez agenta)

```python
import requests
import json

state = {
    "timestamp": "2025-05-10T12:34:56Z",
    "hardware": { ... },
    "services": [ ... ],
    "processes": [ ... ]
}

response = requests.post("http://VM_IP:5678/api/v1/update_state", json=state)
data = response.json()
print(data)
```

## Bezpieczeństwo

API VM Bridge nie ma wbudowanej autoryzacji ani uwierzytelniania. W środowisku produkcyjnym zalecane jest:

1. Ograniczenie dostępu do API za pomocą zapory sieciowej:
```bash
# Ograniczenie dostępu do API tylko z lokalnej sieci
sudo ufw allow from 192.168.0.0/24 to any port 5678
```

2. Używanie bezpiecznego kanału komunikacji (np. VPN) jeśli system jest używany w środowisku produkcyjnym.

3. Ustawienie reverse proxy z SSL:
```bash
# Przykładowa konfiguracja Nginx
server {
    listen 443 ssl;
    server_name safetytwin.example.com;

    ssl_certificate /etc/letsencrypt/live/safetytwin.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/safetytwin.example.com/privkey.pem;

    location / {
        proxy_pass http://VM_IP:5678;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Obsługa błędów

W przypadku błędu, API zwraca odpowiedź z kodem HTTP innym niż 200 i obiektem JSON zawierającym pola:

- `status` - zawsze "error"
- `message` - opis błędu

Przykład:
```json
{
  "status": "error",
  "message": "Nie udało się przywrócić snapshotu state_1620123123: snapshot nie istnieje"
}
```

## Ograniczenia

- API nie ma paginacji dla dużych zbiorów danych
- API nie obsługuje równoległych żądań aktualizacji stanu
- API nie ma mechanizmu cache'owania

## Zmiany w API

### Wersja 1.0

- Pierwsza publiczna wersja API

## Zasoby dodatkowe

- [Dokumentacja libvirt](https://libvirt.org/docs.html)
- [Dokumentacja QEMU/KVM](https://www.qemu.org/docs/master/)
- [Dokumentacja Ansible](https://docs.ansible.com/)