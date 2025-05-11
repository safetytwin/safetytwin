# SafetyTwin Agent

Agent monitorujący do zbierania informacji o systemie w czasie rzeczywistym dla projektu SafetyTwin.

## Opis

Agent SafetyTwin to lekki program napisany w Go, który zbiera szczegółowe informacje o stanie systemu, w tym:

- Informacje o sprzęcie (CPU, pamięć, dyski, sieć, GPU)
- Procesy uruchomione w systemie
- Usługi systemowe
- Kontenery Docker (jeśli dostępne)

Agent został zaprojektowany z myślą o minimalnym wpływie na wydajność monitorowanego systemu i może być uruchamiany w regularnych odstępach czasu (np. co 10 sekund) w celu śledzenia zmian stanu systemu.

## Struktura projektu

```
agent/
├── collectors/           # Kolektory danych dla różnych komponentów systemu
│   ├── docker.go         # Kolektor dla kontenerów Docker
│   ├── hardware.go       # Kolektor dla informacji o sprzęcie
│   ├── process.go        # Kolektor dla procesów
│   ├── service.go        # Kolektor dla usług systemowych
│   └── system_collector.go # Główny kolektor koordynujący wszystkie pozostałe
├── models/               # Modele danych
│   ├── hardware.go       # Struktury dla informacji o sprzęcie
│   ├── process.go        # Struktury dla procesów
│   ├── service.go        # Struktury dla usług
│   └── system_state.go   # Główna struktura stanu systemu
├── utils/                # Narzędzia pomocnicze
├── main.go               # Punkt wejściowy programu
└── README.md             # Dokumentacja
```

## Modele danych

### SystemState

Główna struktura reprezentująca pełny stan monitorowanego systemu:

```go
type SystemState struct {
    Timestamp string     `json:"timestamp"`
    Hardware  *Hardware  `json:"hardware"`
    Services  []Service  `json:"services"`
    Processes []Process  `json:"processes"`
}
```

### Hardware

Informacje o sprzęcie systemu:

```go
type Hardware struct {
    Hostname        string                      `json:"hostname"`
    Platform        string                      `json:"platform"`
    PlatformVersion string                      `json:"platform_version"`
    KernelVersion   string                      `json:"kernel_version"`
    OS              string                      `json:"os"`
    Uptime          uint64                      `json:"uptime"`
    CPU             *CPU                        `json:"cpu"`
    Memory          *Memory                     `json:"memory"`
    Disks           []Disk                      `json:"disks"`
    Network         map[string]NetworkInterface `json:"network"`
    GPU             map[string][]GPUDevice      `json:"gpu,omitempty"`
}
```

### Process

Informacje o procesach:

```go
type Process struct {
    PID           int32                  `json:"pid"`
    PPID          int32                  `json:"ppid,omitempty"`
    Name          string                 `json:"name"`
    Username      string                 `json:"username"`
    Status        string                 `json:"status"`
    CreateTime    string                 `json:"create_time"`
    CPUPercent    float64                `json:"cpu_percent"`
    MemoryPercent float32                `json:"memory_percent"`
    MemoryInfo    *MemoryInfo            `json:"memory_info"`
    Cmdline       []string               `json:"cmdline"`
    // ... i więcej pól
    IsLLMRelated  bool                   `json:"is_llm_related"`
    Extra         map[string]interface{} `json:"extra,omitempty"`
}
```

### Service

Informacje o usługach:

```go
type Service struct {
    Name          string                 `json:"name"`
    Type          string                 `json:"type"`
    ID            string                 `json:"id,omitempty"`
    Hostname      string                 `json:"hostname"`
    Timestamp     string                 `json:"timestamp"`
    Status        string                 `json:"status"`
    // ... i więcej pól
    IsLLMRelated  bool                   `json:"is_llm_related"`
    Extra         map[string]interface{} `json:"extra,omitempty"`
}
```

## Kolektory

### HardwareCollector

Zbiera informacje o sprzęcie systemu, w tym:
- Podstawowe informacje o hoście (hostname, platforma, wersja kernela)
- Informacje o CPU (model, liczba rdzeni, użycie)
- Informacje o pamięci (całkowita, dostępna, używana)
- Informacje o dyskach (urządzenia, punkty montowania, użycie)
- Informacje o interfejsach sieciowych (adresy, statystyki)
- Informacje o GPU NVIDIA (jeśli dostępne)

### ProcessCollector

Zbiera informacje o procesach uruchomionych w systemie:
- Podstawowe informacje o procesie (PID, nazwa, użytkownik)
- Użycie zasobów (CPU, pamięć)
- Otwarte pliki i połączenia sieciowe
- Wykrywanie procesów związanych z LLM (na podstawie wzorców)

### ServiceCollector

Zbiera informacje o usługach systemowych:
- Usługi systemowe (status, użycie zasobów)
- Kontenery Docker (jeśli Docker jest dostępny)
- Wykrywanie usług związanych z LLM

### DockerCollector

Zbiera informacje o kontenerach Docker:
- Szczegóły kontenera (ID, nazwa, status)
- Mapowania portów
- Montowania wolumenów
- Zmienne środowiskowe

### SystemCollector

Koordynuje wszystkie kolektory w celu zbudowania pełnego stanu systemu.

## Użycie

### Instalacja zależności

```bash
go get -u github.com/shirou/gopsutil/v3
go get -u github.com/NVIDIA/go-nvml/pkg/nvml
go get -u github.com/docker/docker/client
```

### Kompilacja

```bash
cd /path/to/safetytwin/agent
go build -o agent main.go
```

### Uruchomienie

```bash
# Uruchom agenta i wyświetl podstawowe informacje o systemie
./agent

# Zapisz pełny stan systemu do pliku JSON
./agent --output system_state.json --pretty
```

## Opcje wiersza poleceń

- `--output <plik>` - Zapisz dane wyjściowe do pliku JSON
- `--pretty` - Formatuj JSON w sposób czytelny dla człowieka

## Wykrywanie komponentów związanych z LLM

Agent ma wbudowane mechanizmy wykrywania procesów i usług związanych z modelami językowymi (LLM):

- Wykrywa procesy używające popularnych bibliotek ML/AI (PyTorch, TensorFlow, Transformers)
- Identyfikuje procesy i usługi związane z popularnymi modelami (LLAMA, GPT, BERT)
- Monitoruje pliki modeli (rozszerzenia .bin, .gguf, .ggml, .pt, .safetensors)

Ta funkcjonalność jest szczególnie przydatna do monitorowania i zarządzania obciążeniami AI w systemie.

## Integracja z SafetyTwin

Agent jest zaprojektowany do współpracy z systemem SafetyTwin:

1. Agent zbiera dane o stanie systemu co 10 sekund
2. Dane są przekazywane do komponentu VM Bridge
3. VM Bridge używa tych danych do aktualizacji cyfrowego bliźniaka w czasie rzeczywistym

## Rozszerzanie

Aby dodać nowy kolektor:

1. Utwórz nowy plik w katalogu `collectors/`
2. Zaimplementuj interfejs kolektora
3. Zintegruj nowy kolektor z `SystemCollector`

## Licencja

[Informacje o licencji]
