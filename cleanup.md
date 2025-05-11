# Dokumentacja narzędzia cleanup.sh

## Opis

`cleanup.sh` to zaawansowane narzędzie wiersza poleceń dla systemów Linux, zaprojektowane do wyszukiwania i zarządzania zbędnymi plikami, szczególnie w projektach związanych z uczeniem maszynowym (np. LLM) i innych przestrzeniach roboczych użytkownika.

Skrypt umożliwia efektywne znajdowanie:
- Dużych plików zajmujących miejsce na dysku
- Duplikatów plików (na podstawie sum kontrolnych)
- Starych, nieużywanych plików
- Plików określonego typu (modele, checkpointy, cache, logi)

## Instalacja

```bash
# Pobierz skrypt
curl -O https://ścieżka-do-skryptu/cleanup.sh

# Nadaj uprawnienia do wykonania
chmod +x cleanup.sh

# Opcjonalnie: przenieś do katalogu w PATH
sudo mv cleanup.sh /usr/local/bin/cleanup
```

## Użycie

Podstawowa składnia:

```bash
./cleanup.sh [opcje] [ścieżka]
```
Jeśli nie podasz ścieżki, skrypt użyje bieżącego katalogu.

```aiignore
Znaleziono 156 plików spełniających kryteria.

Analiza struktury plików:
Liczba plików    | Katalog                                           (Rozmiar)
----------------|------------------------
42              | /home/user/.cache/pip                             (156M)
37              | /home/user/projekty/llm-project/checkpoints       (1.2G)
28              | /home/user/.cache/huggingface                     (3.5G)
...

Podsumowanie struktury:
- Znalezione pliki są w 35 różnych katalogach
- Pokazano 20 katalogów z największą liczbą plików

Analiza typów plików:
Liczba plików    | Rozszerzenie  | Łączny rozmiar
----------------|--------------|------------------
85              | .pt          | 4.2G
64              | .bin         | 2.1G
42              | .log         | 156M
...

10 największych znalezionych plików:
1.5G    /home/user/projekty/llm-project/model-final.pt
950M    /home/user/.cache/huggingface/model-v1.bin
...

Łączny rozmiar znalezionych plików: 8.7G
```


### Opcje

| Opcja | Opis |
|-------|------|
| `-h, --help` | Wyświetla pomoc |
| `-s, --size SIZE` | Pokaż pliki większe niż SIZE (np. 100M, 2G) |
| `-d, --duplicates` | Znajdź duplikaty plików |
| `-o, --old DAYS` | Znajdź pliki starsze niż DAYS dni |
| `-t, --type TYPE` | Szukaj plików określonego typu (np. 'model', 'checkpoint', 'cache', 'log') |
| `-r, --remove` | Usuń znalezione pliki (z potwierdzeniem) |
| `-l, --list-only` | Tylko wyświetl pliki bez pytania o usunięcie |
| `-a, --all-locations` | Przeszukaj wszystkie domyślne lokalizacje |
| `--show-locations` | Wyświetl wszystkie domyślne lokalizacje i ich status |

### Predefiniowane typy plików

Skrypt obsługuje następujące predefiniowane typy plików:

| Typ | Opis | Szukane pliki |
|-----|------|---------------|
| `model` | Pliki modeli ML | *.bin, *.pt, *.pth, *.ckpt, *.safetensors, *.onnx, *.pb |
| `checkpoint` | Checkpointy | *.ckpt, *.pt, *.pth, */checkpoints/* |
| `cache` | Pliki cache | */.cache/*, */__pycache__/*, *.cache, */cache/* |
| `log` | Pliki logów | *.log, *.out, */logs/* |

Dla innych typów, skrypt wyszukuje pliki zawierające podaną nazwę.

## Analiza plików

`cleanup.sh` oferuje szczegółową analizę znalezionych plików:

### Analiza struktury katalogów

Skrypt pokazuje, ile plików znajduje się w każdym katalogu, sortując wyniki według liczby plików:

```
Analiza struktury plików:
Liczba plików    | Katalog                                           (Rozmiar)
----------------|------------------------
42              | /home/user/.cache/pip                             (156M)
37              | /home/user/projekty/llm-project/checkpoints       (1.2G)
28              | /home/user/.cache/huggingface                     (3.5G)
...
```

### Analiza typów plików

Skrypt podsumowuje znalezione typy plików według rozszerzeń:

```
Analiza typów plików:
Liczba plików    | Rozszerzenie  | Łączny rozmiar
----------------|--------------|------------------
85              | .pt          | 4.2G
64              | .bin         | 2.1G
42              | .log         | 156M
...
```

### Wyszukiwanie w wielu lokalizacjach

```bash
# Przeszukaj wszystkie domyślne lokalizacje dla plików większych niż 500MB
./cleanup.sh -a -s 500M

# Znajdź duplikaty modeli większe niż 100MB
./cleanup.sh -a -d -t model -s 100M
```

### Zarządzanie plikami

```bash
# Znajdź i wyświetl wszystkie pliki cache, które można usunąć
./cleanup.sh -a -t cache -l

# Znajdź i usuń wszystkie pliki logów starsze niż 60 dni
./cleanup.sh ~/logs -t log -o 60 -r
```

## Domyślne lokalizacje

Skrypt przeszukuje następujące domyślne lokalizacje przy użyciu opcji `-a`:

### Katalogi użytkownika
- $HOME/Downloads
- $HOME/Documents
- $HOME/Desktop
- $HOME/Pictures
- $HOME/Videos
- $HOME/Music

### Projekty
- $HOME/projekty
- $HOME/Projects
- $HOME/Projekty
- $HOME/repos
- $HOME/git
- $HOME/workspace

### Lokalizacje związane z LLM
- $HOME/.cache/huggingface
- $HOME/.cache/torch
- $HOME/.cache/pip
- $HOME/.local/share/virtualenvs

### Lokalizacje systemowe
- $HOME/.local/lib
- $HOME/.local/share
- /opt
- /usr/local/lib
- /usr/local/share
- /var/lib/docker

## Typowe pliki do usunięcia

Skrypt podpowiada następujące typy plików jako typowe kandydaty do usunięcia:

| Typ pliku | Opis |
|-----------|------|
| *.ckpt | Checkpointy modeli (często duże, wiele GB) |
| *.safetensors | Modele w formacie safetensors (często duże, wiele GB) |
| *.bin | Skompilowane pliki binarne |
| *.log | Pliki logów, zwykle bezpiecznie usuwalne |
| */__pycache__/* | Cache Pythona, bezpiecznie usuwalne |
| */node_modules/* | Moduły Node.js, można usunąć i ponownie zainstalować |
| $HOME/.cache/pip | Cache instalacji pakietów pip |
| $HOME/.cache/huggingface | Cache modeli Hugging Face |

## Dobre praktyki

1. **Zawsze używaj opcji `-l` (list-only) przy pierwszym uruchomieniu** w nowym miejscu, aby zobaczyć, co zostanie znalezione przed usunięciem.

2. **Regularnie czyść katalogi cache** (biblioteki Pythona, modele LLM, etc.), które często zajmują znaczną ilość miejsca.

3. **Zwróć uwagę na duplikaty** - często są to te same pliki skopiowane do różnych lokalizacji.

4. **Wykonuj regularne czyszczenie** - np. tygodniowo lub miesięcznie, aby zapobiec gromadzeniu się śmieci.

## Bezpieczeństwo

- Skrypt **zawsze prosi o potwierdzenie** przed usunięciem plików
- Przed usunięciem wyświetla łączny rozmiar plików do usunięcia
- Nie usuwa plików systemowych ani kluczowych plików konfiguracyjnych
- Nie ma uprawnień root, więc nie może usuwać plików spoza przestrzeni użytkownika (chyba że uruchomiony jako root)

## Rozwiązywanie problemów

- **Problem z uprawnieniami**: Upewnij się, że masz odpowiednie uprawnienia do przeszukiwanych katalogów
- **Brak wyników**: Sprawdź, czy filtry (rozmiar, typ) nie są zbyt restrykcyjne
- **Błędy podczas szukania duplikatów**: Może to oznaczać, że na dysku jest zbyt mało miejsca na pliki tymczasowe

## Ograniczenia

- Wyszukiwanie duplikatów dla bardzo dużych plików może być czasochłonne
- Skrypt nie rozpoznaje kontekstu plików - zawsze sprawdzaj, zanim usuniesz

## Autor

Tom Sapletta - Główny deweloper
