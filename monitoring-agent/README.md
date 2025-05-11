# Monitoring Agent dla SafetyTwin

Agent monitorujący do zbierania danych o stanie systemu i przekazywania ich do VM Bridge. Agent jest napisany w języku Go i wykorzystuje bibliotekę gopsutil do zbierania informacji o systemie.

## Funkcje

- Zbieranie informacji o sprzęcie (CPU, pamięć, dyski, sieć)
- Monitorowanie usług systemd
- Monitorowanie kontenerów Docker
- Wykrywanie procesów związanych z LLM (Large Language Models)
- Zapisywanie stanu systemu do plików JSON
- Wysyłanie stanu systemu do VM Bridge przez API REST

## Wymagania

- Go 1.16 lub nowszy
- Dostęp do komend systemowych (systemctl, docker)
- Uprawnienia do odczytu informacji o systemie

## Zależności

```
github.com/shirou/gopsutil/v3
```

## Instalacja

1. Zainstaluj Go (jeśli nie jest zainstalowane):
   ```bash
   sudo apt-get update
   sudo apt-get install golang-go
   ```

2. Sklonuj repozytorium:
   ```bash
   git clone https://github.com/safetytwin/safetytwin.git
   cd safetytwin/monitoring-agent
   ```

3. Pobierz zależności:
   ```bash
   go mod init github.com/safetytwin/monitoring-agent
   go mod tidy
   ```

4. Zbuduj agenta:
   ```bash
   go build -o monitoring-agent agent.go
   ```

## Użycie

```bash
./monitoring-agent [opcje]
```

### Opcje

- `-interval int`: Interwał odczytu w sekundach (domyślnie: 10)
- `-bridge string`: URL do VM Bridge (domyślnie: "http://localhost:5678/api/v1/update_state")
- `-log string`: Plik dziennika (domyślnie: "/var/log/safetytwin-agent.log")
- `-state-dir string`: Katalog na dane stanu (domyślnie: "/var/lib/safetytwin/states")
- `-proc`: Czy zbierać dane o procesach (domyślnie: true)
- `-net`: Czy zbierać dane o sieci (domyślnie: true)
- `-verbose`: Tryb szczegółowego logowania (domyślnie: false)

### Przykład

```bash
./monitoring-agent -interval 5 -bridge "http://10.0.0.1:5678/api/v1/update_state" -verbose
```

## Format danych

Agent zbiera dane w formacie JSON o następującej strukturze:

```json
{
  "timestamp": "2023-05-10T12:34:56Z",
  "hardware": {
    "hostname": "server1",
    "platform": "linux",
    "cpu": { ... },
    "memory": { ... },
    "disks": [ ... ],
    "network": { ... }
  },
  "services": [
    {
      "name": "nginx.service",
      "type": "systemd",
      "status": "active",
      "timestamp": "2023-05-10T12:34:56Z"
    },
    {
      "name": "web-app",
      "type": "docker",
      "image": "nginx:latest",
      "status": "running",
      "ports": [ ... ],
      "volumes": [ ... ]
    }
  ],
  "processes": [
    {
      "pid": 1234,
      "name": "python3",
      "cmdline": ["python3", "app.py"],
      "is_llm_related": true,
      "cpu_percent": 25.5,
      "memory_percent": 15.2,
      "cwd": "/home/user/app"
    }
  ]
}
```

## Integracja z VM Bridge

Agent wysyła zebrane dane do VM Bridge za pomocą żądania HTTP POST. VM Bridge używa tych danych do aktualizacji stanu maszyny wirtualnej, tworząc cyfrowego bliźniaka monitorowanego systemu.

## Licencja

Ten projekt jest objęty licencją MIT.
