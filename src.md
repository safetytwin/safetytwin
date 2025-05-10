```
digital-twin-system/
├── install.sh                          # Główny skrypt instalacyjny
│
├── agent/                              # Agent zbierania danych (Go)
│   ├── main.go                         # Punkt wejściowy agenta
│   ├── collectors/                     # Moduły zbierające różne typy danych
│   │   ├── hardware.go                 # Kolektor informacji o sprzęcie
│   │   ├── process.go                  # Kolektor informacji o procesach
│   │   ├── service.go                  # Kolektor informacji o usługach
│   │   └── docker.go                   # Kolektor informacji o kontenerach Docker
│   ├── models/                         # Struktury danych
│   │   ├── system_state.go             # Model stanu systemu
│   │   ├── hardware.go                 # Model informacji o sprzęcie
│   │   ├── process.go                  # Model informacji o procesach
│   │   └── service.go                  # Model informacji o usługach
│   ├── utils/                          # Narzędzia pomocnicze
│   │   ├── config.go                   # Zarządzanie konfiguracją
│   │   ├── logging.go                  # Konfiguracja logowania
│   │   └── sender.go                   # Wysyłanie danych do VM Bridge
│   ├── go.mod                          # Zależności Go
│   └── go.sum                          # Sumy kontrolne zależności
│
├── vm-bridge/                          # Bridge między agentem a VM (Python)
│   ├── vm_bridge.py                    # Główny skrypt VM Bridge
│   ├── templates/                      # Szablony dla Ansible
│   │   ├── process_launcher.sh.j2      # Szablon skryptu uruchamiającego proces
│   │   └── process_service.service.j2  # Szablon usługi systemd dla procesu
│   ├── utils/                          # Moduły pomocnicze
│   │   ├── config.py                   # Zarządzanie konfiguracją
│   │   ├── state_store.py              # Przechowywanie i zarządzanie stanem
│   │   ├── vm_manager.py               # Zarządzanie maszyną wirtualną
│   │   └── service_generator.py        # Generowanie konfiguracji usług
│   ├── api/                            # Moduły API
│   │   ├── app.py                      # Aplikacja Flask do odbierania danych
│   │   ├── routes.py                   # Trasy API
│   │   └── models.py                   # Modele danych API
│   └── requirements.txt                # Zależności Python
│
├── ansible/                            # Pliki Ansible do konfiguracji VM
│   ├── apply_services.yml              # Główny playbook do konfiguracji usług
│   ├── roles/                          # Role Ansible
│   │   ├── common/                     # Wspólne zadania
│   │   │   ├── tasks/                  
│   │   │   │   └── main.yml            # Podstawowa konfiguracja systemu
│   │   │   └── templates/              
│   │   │       └── system_profile.j2   # Szablon profilu systemu
│   │   ├── services/                   # Zarządzanie usługami
│   │   │   ├── tasks/                  
│   │   │   │   └── main.yml            # Zadania konfiguracji usług
│   │   │   └── templates/              
│   │   │       └── service.conf.j2     # Szablony konfiguracji usług
│   │   ├── docker/                     # Zarządzanie kontenerami Docker
│   │   │   ├── tasks/                  
│   │   │   │   └── main.yml            # Zadania konfiguracji Docker
│   │   │   └── templates/              
│   │   │       └── docker-compose.j2   # Szablon docker-compose.yml
│   │   └── processes/                  # Zarządzanie procesami
│   │       └── tasks/                  
│   │           └── main.yml            # Zadania konfiguracji procesów
│   └── inventory.yml                   # Przykładowy plik inwentarza
│
├── vm-templates/                       # Szablony dla maszyny wirtualnej
│   ├── cloud-init/                     # Konfiguracja cloud-init dla VM
│   │   ├── user-data                   # Konfiguracja użytkownika
│   │   └── meta-data                   # Metadane VM
│   └── vm-definition.xml               # Szablon definicji libvirt VM
│
├── configs/                            # Przykładowe pliki konfiguracyjne
│   ├── agent-config.json               # Konfiguracja agenta
│   ├── vm-bridge.yaml                  # Konfiguracja VM Bridge
│   └── services/                       # Przykładowe konfiguracje usług
│       ├── nginx.yaml                  # Przykład konfiguracji nginx
│       └── postgres.yaml               # Przykład konfiguracji PostgreSQL
│
├── scripts/                            # Skrypty pomocnicze
│   ├── install-agent.sh                # Instalacja agenta
│   ├── install-vm-bridge.sh            # Instalacja VM Bridge
│   ├── create-vm.sh                    # Tworzenie maszyny wirtualnej
│   └── build-agent.sh                  # Kompilacja agenta z kodu źródłowego
│
├── docs/                               # Dokumentacja
│   ├── overview.md                     # Przegląd systemu
│   ├── agent.md                        # Dokumentacja agenta
│   ├── vm-bridge.md                    # Dokumentacja VM Bridge
│   ├── vm-setup.md                     # Konfiguracja maszyny wirtualnej
│   ├── ansible.md                      # Dokumentacja Ansible
│   └── api.md                          # Dokumentacja API
│
└── examples/                           # Przykłady użycia
    ├── llm-infrastructure/             # Przykład dla infrastruktury LLM
    │   ├── agent-config.json           # Konfiguracja agenta dla LLM
    │   └── services/                   # Przykładowe usługi LLM
    └── web-server/                     # Przykład dla serwera WWW
        ├── agent-config.json           # Konfiguracja agenta dla serwera WWW
        └── services/                   # Przykładowe usługi serwera WWW
```