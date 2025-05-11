#!/bin/bash

# Skrypt do przeszukiwania i identyfikowania potencjalnie zbędnych plików
# w projektach związanych z LLM i innymi projektami

# Kolory do wyróżniania tekstu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Domyślne lokalizacje do przeszukiwania
DEFAULT_LOCATIONS=(
    # Katalogi użytkownika
    "$HOME/Downloads"
    "$HOME/Documents"
    "$HOME/Desktop"
    "$HOME/Pictures"
    "$HOME/Videos"
    "$HOME/Music"

    # Projekty
    "$HOME/projekty"
    "$HOME/Projects"
    "$HOME/Projekty"
    "$HOME/repos"
    "$HOME/git"
    "$HOME/workspace"

    # Typowe lokalizacje dla projektów LLM
    "$HOME/.cache/huggingface"
    "$HOME/.cache/torch"
    "$HOME/.cache/pip"
    "$HOME/.local/share/virtualenvs"

    # Lokalizacje systemowe, gdzie użytkownik mógł instalować oprogramowanie
    "$HOME/.local/lib"
    "$HOME/.local/share"
    "/opt"
    "/usr/local/lib"
    "/usr/local/share"
    "/var/lib/docker"
)

# Funkcja wyświetlająca pomoc
function show_help {
    echo -e "${GREEN}Skrypt do przeszukiwania i usuwania zbędnych plików${NC}"
    echo ""
    echo "Użycie: $0 [opcje] [ścieżka]"
    echo ""
    echo "Opcje:"
    echo "  -h, --help            Wyświetla tę pomoc"
    echo "  -s, --size SIZE       Pokaż pliki większe niż SIZE (np. 100M)"
    echo "  -d, --duplicates      Znajdź duplikaty plików"
    echo "  -o, --old DAYS        Znajdź pliki starsze niż DAYS dni"
    echo "  -t, --type TYPE       Szukaj plików określonego typu (np. 'model', 'checkpoint', 'cache', 'log')"
    echo "  -r, --remove          Usuń znalezione pliki (z potwierdzeniem)"
    echo "  -l, --list-only       Tylko wyświetl pliki bez pytania o usunięcie"
    echo "  -a, --all-locations   Przeszukaj wszystkie domyślne lokalizacje"
    echo ""
    echo "Przykłady:"
    echo "  $0 ~/projekty/llm -s 500M -t model        # Znajdź modele LLM większe niż 500MB"
    echo "  $0 ~/Downloads -d -t checkpoint -o 30     # Znajdź duplikaty checkpointów starsze niż 30 dni"
    echo "  $0 ~/projekty -s 1G -l                    # Wyświetl wszystkie pliki większe niż 1GB"
    echo "  $0 -a -s 1G -t model                      # Przeszukaj wszystkie domyślne lokalizacje dla modeli większych niż 1GB"
    exit 0
}

# Wyświetl domyślne lokalizacje
function show_default_locations {
    echo -e "${GREEN}Domyślne lokalizacje do przeszukiwania:${NC}"
    for loc in "${DEFAULT_LOCATIONS[@]}"; do
        if [ -d "$loc" ]; then
            echo -e "  ${BLUE}$loc${NC} ${GREEN}(istnieje)${NC}"
        else
            echo -e "  ${BLUE}$loc${NC} ${RED}(nie istnieje)${NC}"
        fi
    done
    exit 0
}

# Domyślne wartości
SEARCH_PATH="."
SEARCH_ALL_LOCATIONS=false
SIZE_FILTER=""
FIND_DUPLICATES=false
AGE_FILTER=""
TYPE_FILTER=""
REMOVE_FILES=false
LIST_ONLY=false
SEARCH_ALL_LOCATIONS=false

# Parsowanie argumentów
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -s|--size)
            SIZE_FILTER=$2
            shift 2
            ;;
        -d|--duplicates)
            FIND_DUPLICATES=true
            shift
            ;;
        -o|--old)
            AGE_FILTER=$2
            shift 2
            ;;
        -t|--type)
            TYPE_FILTER=$2
            shift 2
            ;;
        -r|--remove)
            REMOVE_FILES=true
            shift
            ;;
        -l|--list-only)
            LIST_ONLY=true
            shift
            ;;
        -a|--all-locations)
            SEARCH_ALL_LOCATIONS=true
            shift
            ;;
        --show-locations)
            show_default_locations
            ;;
        *)
            SEARCH_PATH=$1
            shift
            ;;
    esac
done

# Tworzymy listę lokalizacji do przeszukania
LOCATIONS_TO_SEARCH=()

if [ "$SEARCH_ALL_LOCATIONS" = true ]; then
    echo -e "${BLUE}Przeszukiwanie wszystkich domyślnych lokalizacji...${NC}"
    # Dodaj wszystkie dostępne domyślne lokalizacje
    for loc in "${DEFAULT_LOCATIONS[@]}"; do
        if [ -d "$loc" ]; then
            LOCATIONS_TO_SEARCH+=("$loc")
            echo -e "  Dodano: ${GREEN}$loc${NC}"
        fi
    done
else
    # Sprawdzenie czy ścieżka istnieje
    if [ ! -d "$SEARCH_PATH" ]; then
        echo -e "${RED}Błąd: Ścieżka '$SEARCH_PATH' nie istnieje lub nie jest katalogiem${NC}"
        echo -e "Użyj ${YELLOW}--show-locations${NC} aby zobaczyć domyślne lokalizacje"
        echo -e "lub ${YELLOW}-a${NC} aby przeszukać wszystkie domyślne lokalizacje"
        exit 1
    fi
    LOCATIONS_TO_SEARCH+=("$SEARCH_PATH")
    echo -e "${GREEN}Przeszukiwanie katalogu: ${BLUE}$SEARCH_PATH${NC}"
fi

# Funkcja do konwersji rozmiaru do bajtów
function convert_size_to_bytes {
    local size=$1
    if [[ $size =~ ^([0-9]+)(K|M|G|T)$ ]]; then
        local num=${BASH_REMATCH[1]}
        local unit=${BASH_REMATCH[2]}
        case $unit in
            K) echo $((num * 1024)) ;;
            M) echo $((num * 1024 * 1024)) ;;
            G) echo $((num * 1024 * 1024 * 1024)) ;;
            T) echo $((num * 1024 * 1024 * 1024 * 1024)) ;;
        esac
    else
        echo $size
    fi
}

# Tworzenie tymczasowego katalogu na wyniki
TEMP_DIR=$(mktemp -d)
RESULTS_FILE="$TEMP_DIR/results.txt"
DUPLICATES_FILE="$TEMP_DIR/duplicates.txt"

# Tworzenie bazowego polecenia find bez ścieżki
BASE_FIND_CMD="-type f"

# Dodanie filtra rozmiaru
if [ ! -z "$SIZE_FILTER" ]; then
    echo -e "Szukam plików większych niż ${YELLOW}$SIZE_FILTER${NC}"
    BASE_FIND_CMD="$BASE_FIND_CMD -size +$SIZE_FILTER"
fi

# Dodanie filtra wieku
if [ ! -z "$AGE_FILTER" ]; then
    echo -e "Szukam plików starszych niż ${YELLOW}$AGE_FILTER dni${NC}"
    BASE_FIND_CMD="$BASE_FIND_CMD -mtime +$AGE_FILTER"
fi

# Dodanie filtra typu
if [ ! -z "$TYPE_FILTER" ]; then
    echo -e "Szukam plików typu: ${YELLOW}$TYPE_FILTER${NC}"

    case $TYPE_FILTER in
        model)
            # Typowe rozszerzenia plików modeli
            TYPE_FIND="\( -name \"*.bin\" -o -name \"*.pt\" -o -name \"*.pth\" -o -name \"*.ckpt\" -o -name \"*.safetensors\" -o -name \"*.onnx\" -o -name \"*.pb\" \)"
            ;;
        checkpoint)
            # Typowe rozszerzenia plików checkpointów
            TYPE_FIND="\( -name \"*.ckpt\" -o -name \"*.pt\" -o -name \"*.pth\" -o -path \"*/checkpoints/*\" \)"
            ;;
        cache)
            # Typowe katalogi cache
            TYPE_FIND="\( -path \"*/.cache/*\" -o -path \"*/__pycache__/*\" -o -name \"*.cache\" -o -name \"cache\" \)"
            ;;
        log)
            # Pliki logów
            TYPE_FIND="\( -name \"*.log\" -o -name \"*.out\" -o -path \"*/logs/*\" \)"
            ;;
        *)
            # Ogólne wyszukiwanie po nazwie
            TYPE_FIND="-name \"*$TYPE_FILTER*\""
            ;;
    esac

    BASE_FIND_CMD="$BASE_FIND_CMD $TYPE_FIND"
fi

echo -e "${BLUE}Wyszukiwanie plików...${NC}"

# Przeszukiwanie wszystkich lokalizacji
for loc in "${LOCATIONS_TO_SEARCH[@]}"; do
    echo -e "Przeszukiwanie: ${YELLOW}$loc${NC}"
    FIND_CMD="find \"$loc\" $BASE_FIND_CMD"
    eval $FIND_CMD >> "$RESULTS_FILE" 2>/dev/null
done

# Liczenie znalezionych plików
FOUND_FILES=$(wc -l < "$RESULTS_FILE")
echo -e "Znaleziono ${GREEN}$FOUND_FILES${NC} plików spełniających kryteria."

# Znajdowanie duplikatów
if [ "$FIND_DUPLICATES" = true ]; then
    echo -e "${BLUE}Wyszukiwanie duplikatów (może potrwać)...${NC}"

    # Używamy md5sum do identyfikacji duplikatów
    while read -r file; do
        if [ -f "$file" ]; then
            md5sum "$file" >> "$TEMP_DIR/checksums.txt"
        fi
    done < "$RESULTS_FILE"

    # Sortowanie i wyszukiwanie duplikatów
    sort "$TEMP_DIR/checksums.txt" | awk '{print $1}' | uniq -d > "$TEMP_DIR/dup_hashes.txt"

    # Tworzenie listy plików-duplikatów
    while read -r hash; do
        grep "$hash" "$TEMP_DIR/checksums.txt" >> "$DUPLICATES_FILE"
    done < "$TEMP_DIR/dup_hashes.txt"

    DUP_COUNT=$(awk '{print $1}' "$DUPLICATES_FILE" | sort | uniq | wc -l)
    echo -e "Znaleziono ${YELLOW}$DUP_COUNT${NC} unikalnych duplikatów."

    # Wyświetlanie duplikatów
    if [ $DUP_COUNT -gt 0 ]; then
        echo -e "${YELLOW}Lista duplikatów:${NC}"

        current_hash=""
        while read -r line; do
            hash=$(echo $line | awk '{print $1}')
            file=$(echo $line | cut -d ' ' -f 3-)

            # Nowa grupa duplikatów
            if [ "$hash" != "$current_hash" ]; then
                echo -e "\n${GREEN}Grupa duplikatów ${BLUE}$hash${NC}:"
                current_hash=$hash
            fi

            size=$(du -h "$file" | cut -f1)
            echo -e "  ${YELLOW}$size${NC} - $file"
        done < "$DUPLICATES_FILE"

        echo ""
    fi
fi

# Wyświetlanie największych znalezionych plików
if [ $FOUND_FILES -gt 0 ]; then
    echo -e "${BLUE}10 największych znalezionych plików:${NC}"
    du -h $(cat "$RESULTS_FILE") 2>/dev/null | sort -hr | head -n 10

    total_size=$(du -ch $(cat "$RESULTS_FILE") 2>/dev/null | tail -n 1 | cut -f1)
    echo -e "\nŁączny rozmiar znalezionych plików: ${GREEN}$total_size${NC}"

    # Dodatkowe informacje o typowych zbędnych plikach
    echo -e "\n${BLUE}Typowe zbędne pliki, które warto rozważyć do usunięcia:${NC}"
    echo -e "  ${YELLOW}*.ckpt${NC} - Checkpointy modeli (często duże, wiele GB)"
    echo -e "  ${YELLOW}*.safetensors${NC} - Modele w formacie safetensors (często duże, wiele GB)"
    echo -e "  ${YELLOW}*.bin${NC} - Skompilowane pliki binarne"
    echo -e "  ${YELLOW}*.log${NC} - Pliki logów, zwykle bezpiecznie usuwalne"
    echo -e "  ${YELLOW}*/__pycache__/*${NC} - Cache Pythona, bezpiecznie usuwalne"
    echo -e "  ${YELLOW}*/node_modules/*${NC} - Moduły Node.js, można usunąć i ponownie zainstalować"
    echo -e "  ${YELLOW}$HOME/.cache/pip${NC} - Cache instalacji pakietów pip"
    echo -e "  ${YELLOW}$HOME/.cache/huggingface${NC} - Cache modeli Hugging Face"

    # Usuwanie plików
    if [ "$LIST_ONLY" = false ] && [ "$REMOVE_FILES" = true ]; then
        echo -e "\n${RED}UWAGA: Zamierzasz usunąć wszystkie znalezione pliki!${NC}"
        echo -e "${RED}Łączny rozmiar do usunięcia: $total_size${NC}"
        read -p "Czy na pewno chcesz kontynuować? (t/N) " confirm

        if [[ $confirm =~ ^[tT]$ ]]; then
            echo "Usuwanie plików..."
            while read -r file; do
                echo "Usuwanie: $file"
                rm -f "$file"
            done < "$RESULTS_FILE"
            echo -e "${GREEN}Usunięto wszystkie pliki.${NC}"
        else
            echo "Anulowano usuwanie plików."
        fi
    elif [ "$LIST_ONLY" = false ]; then
        echo -e "\nAby usunąć znalezione pliki, użyj opcji ${YELLOW}-r${NC} lub ${YELLOW}--remove${NC}"
    fi
fi

# Sprzątanie
rm -rf "$TEMP_DIR"

echo -e "\n${GREEN}Zakończono przeszukiwanie.${NC}"