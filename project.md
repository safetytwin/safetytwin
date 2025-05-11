# System Cyfrowego Bliźniaka w Czasie Rzeczywistym

![Wersja](https://img.shields.io/badge/wersja-1.0.0-blue)
![Licencja](https://img.shields.io/badge/licencja-MIT-green)

System do tworzenia i aktualizacji cyfrowego bliźniaka infrastruktury komputerowej w czasie rzeczywistym, z częstotliwością co 10 sekund. System koncentruje się na usługach działających w tle i umożliwia natychmiastowe odtworzenie stanu systemu w wirtualnym środowisku.

## Przegląd

System Cyfrowego Bliźniaka tworzy pełną, działającą wirtualną kopię monitorowanego systemu, z aktualizacją w czasie rzeczywistym. W odróżnieniu od tradycyjnych narzędzi monitorujących, które tylko pokazują stan, SafetyTwin **tworzy działającą replikę infrastruktury**, która może być używana do testowania, debugowania i innych celów.

### Główne Cechy

- **Aktualizacja co 10 sekund** - zbieranie danych i aktualizacja cyfrowego bliźniaka z wysoką częstotliwością
- **Śledzenie usług i procesów** - monitorowanie wszystkich usług systemowych, kontenerów Docker i procesów
- **Snapshoty VM** - szybkie przełączanie między stanami systemu
- **Wykorzystanie libvirt/KVM** - pełna wirtualizacja dla lepszego odwzorowania rzeczywistego systemu
- **Lekki agent** - minimalne obciążenie monitorowanego systemu
- **Zarządzanie przez API REST** - łatwe sterowanie systemem przez REST API

## Komponenty Systemu

System składa się z następujących głównych komponentów:

1. **Agent Zbierania Danych** (Go) - działa na monitorowanym systemie i zbiera dane o sprzęcie, usługach i procesach
2. **VM Bridge** (Python) - zarządza maszyną wirtualną i stosuje zmiany konfiguracji
3. **Maszyna Wirtualna** (libvirt/KVM) - faktyczny cyfrowy bliźniak, odwzorowujący monitorowany system
4. **Playbook Ansible** - konfiguruje usługi w maszynie wirtualnej
5. **API REST** - umożliwia zarządzanie systemem i dostęp do danych

## Wymagania Systemowe

### Dla Systemu Monitorowanego
- System operacyjny Linux (przetestowany na Ubuntu 20.04+, Debian 11+, CentOS 8+)
- Minimum 100MB wolnej pamięci RAM dla agenta
- Minimum 200MB wolnego miejsca na dysku
- Uprawnienia roota dla instalacji agenta

### Dla Systemu Zarządzającego (VM Manager)
- System operacyjny Linux z obsługą wirtualizacji (KVM)
- CPU z obsługą wirtualizacji (VT-x/AMD-V)
- Minimum 8GB RAM (4GB dla VM + 4GB dla systemu)
- Minimum 50GB wolnego miejsca na dysku
- libvirt, QEMU/KVM, Python 3.7+, Ansible

## Instalacja

### Szybka Instalacja

```bash
# Klonowanie repozytorium
git clone https://github.com/safetytwin/digital-twin.git
cd digital-twin

# Instalacja systemu
sudo make install

# Uruchomienie usług
sudo systemctl enable --now digital-twin-agent.service
sudo systemctl enable --now digital-twin-bridge.service
```

### Instalacja z Dostosowaniem

```bash
# Instalacja z niestandardowymi parametrami
sudo make install VM_MEMORY=8192 VM_VCPUS=4 BRIDGE_PORT=6789 AGENT_INTERVAL=5
```

### Instalacja Ręczna

Szczegółowe instrukcje znajdują się w pliku [INSTALLATION.md](docs/INSTALLATION.md).

## Użycie

### Uruchomienie Monitoringu

```bash
# Sprawdź stan agenta
sudo systemctl status digital-twin-agent

# Sprawdź stan VM Bridge
sudo systemctl status digital-twin-bridge

# Sprawdź logi agenta
sudo journalctl -fu digital-twin-agent

# Sprawdź logi VM Bridge
sudo journalctl -fu digital-twin-bridge
```

### Zarządzanie przez API REST

```bash
# Przykłady zapytań API
# Lista snapshotów
curl http://localhost:5678/api/v1/snapshots

# Przywrócenie snapshotu
curl -X POST http://localhost:5678/api/v1/snapshots/state_1620123456
```

Pełna dokumentacja API znajduje się w pliku [API.md](docs/API.md).

## Przykłady Użycia

### Monitorowanie LLM

System może być używany do monitorowania i replikowania środowiska uruchomieniowego dla modeli LLM:

```bash
# Konfiguracja specjalna dla LLM
cp configs/examples/llm-config.json /etc/digital-twin/agent-config.json
systemctl restart digital-twin-agent
```

### Analiza Awarii

```bash
# Przywróć stan przed awarią
curl -X POST http://localhost:5678/api/v1/snapshots/state_before_crash

# Podłącz się do konsoli VM
virsh console digital-twin-vm
```

Więcej przykładów można znaleźć w katalogu [examples](examples/).

## Struktura Projektu

```
safetytwin/
├── agent/                  # Agent zbierania danych (Go)
├── vm-bridge/              # Bridge między agentem a VM (Python)
├── ansible/                # Pliki Ansible do konfiguracji VM
├── vm-templates/           # Szablony dla maszyny wirtualnej
├── configs/                # Przykładowe pliki konfiguracyjne
├── scripts/                # Skrypty pomocnicze
├── docs/                   # Dokumentacja
└── examples/               # Przykłady użycia
```

## Rozwiązywanie Problemów

Patrz [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## FAQ

Patrz [FAQ.md](docs/FAQ.md).

## Rozwój Projektu

Wskazówki dla deweloperów znajdują się w [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencja

Ten projekt jest udostępniany na licencji MIT. Zobacz plik [LICENSE](LICENSE).

## Autorzy

- Tom Sapletta - Główny deweloper

## Kontakt

W razie pytań lub problemów, prosimy o kontakt przez:
- GitHub Issues: [https://github.com/safetytwin/digital-twin/issues](https://github.com/safetytwin/digital-twin/issues)