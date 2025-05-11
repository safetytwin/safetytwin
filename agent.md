# Agent Zbierania Danych

Lekki, wydajny agent napisany w Go do zbierania danych o infrastrukturze systemu w czasie rzeczywistym. Zbiera informacje o sprzęcie, usługach, procesach i kontenerach Docker, a następnie wysyła je do VM Bridge co 10 sekund.

## Funkcje

- Zbieranie danych o sprzęcie (CPU, pamięć, dyski, sieć)
- Zbieranie danych o usługach systemowych (systemd)
- Zbieranie danych o kontenerach Docker
- Zbieranie danych o procesach, ze szczególnym uwzględnieniem procesów LLM
- Minimalne obciążenie systemu (< 50MB RAM)
- Wysoka wydajność dzięki implementacji w Go
- Konfigurowalny interwał zbierania danych

## Wymagania

- System operacyjny Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- Go 1.18+ (tylko do kompilacji)
- Uprawnienia roota (dla dostępu do niektórych metryk systemowych)

## Kompilacja

```bash
cd agent
go build -o bin/safetytwin-agent main.go
```

## Instalacja

### Ręczna

```bash
# Utwórz katalogi
sudo mkdir -p /opt/safetytwin
sudo mkdir -p /etc/safetytwin
sudo mkdir -p /var/lib/safetytwin/agent-states
sudo mkdir -p /var/log/safetytwin

# Skopiuj plik binarny
sudo cp bin/safetytwin-agent /opt/safetytwin/

# Utwórz konfigurację
sudo cat > /etc/safetytwin/agent-config.json << EOF
{
  "interval": 10,
  "bridge_url": "http://localhost:5678/api/v1/update_state",
  "log_file": "/var/log/safetytwin/agent.log",
  "state_dir": "/var/lib/safetytwin/agent-states",
  "include_processes": true,
  "include_network": true,
  "verbose": false
}
EOF

# Utwórz usługę systemd
sudo cat > /etc/systemd/system/safetytwin-agent.service << EOF
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
EOF

# Załaduj i uruchom usługę
sudo systemctl daemon-reload
sudo systemctl enable --now safetytwin-agent.service
```

### Z Makefile

```bash
# W głównym katalogu projektu
sudo make agent
sudo make install
```

## Konfiguracja

Agent jest konfigurowany przez plik JSON. Domyślna lokalizacja to `/etc/safetytwin/agent-config.json`.

```json
{
  "interval": 10,            // Interwał zbierania danych w sekundach
  "bridge_url": "http://localhost:5678/api/v1/update_state",  // URL do VM Bridge
  "log_file": "/var/log/safetytwin/agent.log",  // Plik dziennika
  "state_dir": "/var/lib/safetytwin/agent-states",  // Katalog na dane stanu
  "include_processes": true,  // Czy zbierać dane o procesach
  "include_network": true,    // Czy zbierać dane o sieci
  "verbose": false            // Tryb szczegółowego logowania
}
```

## Uruchamianie

```bash
# Uruchom bezpośrednio
sudo /opt/safetytwin/safetytwin-agent -config /etc/safetytwin/agent-config.json

# Lub przez systemd
sudo systemctl start safetytwin-agent
```

## Monitorowanie

```bash
# Sprawdź status usługi
sudo systemctl status safetytwin-agent

# Sprawdź logi
sudo journalctl -fu safetytwin-agent

# Sprawdź bezpośrednio plik dziennika
tail -f /var/log/safetytwin/agent.log
```

## Architektura

Agent składa się z następujących głównych modułów:

1. **main.go** - Punkt wejściowy programu, zarządza cyklem życia agenta
2. **collectors/** - Moduły zbierające różne typy danych
   - **hardware.go** - Zbiera informacje o sprzęcie
   - **process.go** - Zbiera informacje o procesach
   - **service.go** - Zbiera informacje o usługach
   - **docker.go** - Zbiera informacje o kontenerach Docker
3. **models/** - Struktury danych
   - **system_state.go** - Model stanu systemu
   - **hardware.go** - Model informacji o sprzęcie
   - **process.go** - Model informacji o procesach
   - **service.go** - Model informacji o usługach
4. **utils/** - Narzędzia pomocnicze
   - **config.go** - Zarządzanie konfiguracją
   - **logging.go** - Konfiguracja logowania
   - **sender.go** - Wysyłanie danych do VM Bridge

## Format Danych

Agent wysyła dane w formacie JSON, zgodnie z modelami zdefiniowanymi w **models/**. Przykładowy format danych:

```json
{
  "timestamp": "2025-05-10T12:34:56Z",
  "hardware": {
    "hostname": "example-host",
    "platform": "linux",
    "platform_version": "Ubuntu 20.04.1 LTS",
    "kernel_version": "5.4.0-42-generic",
    "cpu": {
      "model": "Intel(R) Core(TM) i7-10700K CPU @ 3.80GHz",
      "cores_physical": 8,
      "count_logical": 16,
      "usage_percent": 12.5
    },
    "memory": {
      "total_gb": 32.0,
      "available_gb": 24.5,
      "used_gb": 7.5,
      "percent": 23.4
    }
  },
  "services": [
    {
      "name": "sshd.service",
      "type": "systemd",
      "status": "active",
      "pid": 1234
    },
    {
      "name": "nginx",
      "type": "docker",
      "status": "running",
      "image": "nginx:latest"
    }
  ],
  "processes": [
    {
      "pid": 1234,
      "name": "python3",
      "username": "user",
      "cpu_percent": 5.2,
      "memory_percent": 2.3,
      "is_llm_related": true
    }
  ]
}
```

## Rozwiązywanie Problemów

### Agent nie uruchamia się

1. Sprawdź logi: `sudo journalctl -fu safetytwin-agent`
2. Upewnij się, że katalogi istnieją: `/opt/safetytwin`, `/etc/safetytwin`, `/var/lib/safetytwin/agent-states`, `/var/log/safetytwin`
3. Sprawdź uprawnienia: `ls -la /opt/safetytwin/safetytwin-agent`

### Agent nie wysyła danych

1. Sprawdź, czy VM Bridge działa: `curl http://localhost:5678/api/v1/status`
2. Sprawdź konfigurację URL Bridge: `/etc/safetytwin/agent-config.json`
3. Sprawdź połączenie sieciowe: `ping localhost`

### Wysokie zużycie zasobów

1. Zmniejsz częstotliwość zbierania danych w konfiguracji
2. Wyłącz zbieranie danych o procesach: `"include_processes": false`
3. Wyłącz zbieranie danych o sieci: `"include_network": false`

## Licencja

Ten projekt jest udostępniany na licencji . Zobacz plik [LICENSE](../LICENSE).