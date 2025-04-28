#!/bin/bash

# Sprawdzanie czy podano plik z listą domen
if [ -z "$1" ]; then
    echo "❌ Musisz podać plik z listą domen jako pierwszy argument! - zalecany format: /katalog/nazwa pliku.txt"
    echo "Przykład: $0 /home/user/domeny.txt"
    exit 1
fi

LISTA_DOMEN="$1"

# Sprawdzenie czy katalog główny istnieje
if [ ! -d "$KATALOG_GLOWNY" ]; then
    echo "❗ Katalog $KATALOG_GLOWNY nie istnieje."
    read -p "Czy chcesz go utworzyć? (t/n): " decyzja
    if [[ "$decyzja" =~ ^[Tt]$ ]]; then
        mkdir -p "$KATALOG_GLOWNY"
        echo "✅ Utworzono katalog $KATALOG_GLOWNY."
    else
        echo "❌ Przerwano działanie skryptu."
        exit 1
    fi
fi

# Tworzenie katalogu backupu na dzisiejszą datę
mkdir -p "$KATALOG_BACKUPU"
# Tworzenie katalogu backupu z dzisiejszą datą i godziną
DATA=$(date +%Y-%m-%d)
KATALOG_BACKUPU="${KATALOG_GLOWNY}/Backup_${DATA}"

# Tworzenie katalogu głównego backupu
mkdir -p "$KATALOG_BACKUPU"

# Maksymalna liczba równoległych pobrań
MAX_PROCESSES=1  # Zmniejszamy, żeby czytelnie widzieć postępy na terminalu

# Pliki do zapisywania błędów i logów
GLOBALNY_LOG="${KATALOG_BACKUPU}/backup_log.txt"
NIEUDANE="${KATALOG_BACKUPU}/nieudane_pobrania.txt"

# Czyścimy pliki
> "$GLOBALNY_LOG"
> "$NIEUDANE"

# Eksport zmiennych, aby były dostępne dla parallel
export KATALOG_BACKUPU
export KATALOG_GLOWNY
export GLOBALNY_LOG
export NIEUDANE

# Sprawdzanie wymaganych narzędzi
command -v wget >/dev/null 2>&1 || { echo >&2 "❌ wget nie jest zainstalowany. Przerwano."; exit 1; }
command -v parallel >/dev/null 2>&1 || { echo >&2 "❌ parallel nie jest zainstalowany. Proszę zainstaluj: sudo apt install parallel"; exit 1; }

# Funkcja czyszcząca wpis domeny (usuwa https://, http://, końcowe /)
oczysc_domena() {
    local domena="$1"
    domena="${domena#https://}"
    domena="${domena#http://}"
    domena="${domena%/}"
    echo "$domena"
}

# Czytanie i czyszczenie listy domen
DOMENY=()
while IFS= read -r linia; do
    [ -z "$linia" ] && continue
    domena=$(oczysc_domena "$linia")
    DOMENY+=("$domena")
done < "$LISTA_DOMEN"

# Pobieranie stron równolegle
printf "%s\n" "${DOMENY[@]}" | parallel --env KATALOG_BACKUPU --env NIEUDANE --env GLOBALNY_LOG --env KATALOG_GLOWNY -j "$MAX_PROCESSES" --colsep ' ' '
    domena={};
    if [[ -z "$domena" || ! "$domena" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo "⚠️ Pominięto nieprawidłowy wpis: $domena" | tee -a "$GLOBALNY_LOG"
        exit 0
    fi

    echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"
    echo "Pobieranie strony: $domena" | tee -a "$GLOBALNY_LOG"
    echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"

    NAZWA_FOLDERU="Strona_${domena//./_}"
    FOLDER_STRONY="${KATALOG_BACKUPU}/${NAZWA_FOLDERU}"
    LOGFILE="${FOLDER_STRONY}.log"

    mkdir -p "$FOLDER_STRONY"

    {
        wget \
            --continue \
            --progress=bar \
			--no-clobber \
            --show-progress \
            --timeout=30 \
            --directory-prefix="$FOLDER_STRONY" \
            --adjust-extension \
            --convert-links \
            --mirror \
            --no-parent \
            --page-requisites \
            --restrict-file-names=windows \
            --trust-server-names \
            "https://${domena}"
    } 2>&1 | tee "$LOGFILE"

    WGET_EXIT_CODE=${PIPESTATUS[0]}

    if [ "$WGET_EXIT_CODE" -eq 0 ]; then
        echo "✅ Sukces: $domena" | tee -a "$GLOBALNY_LOG"
    else  
        echo "❌ Błąd: $domena" | tee -a "$GLOBALNY_LOG"
        echo "$domena" >> "$NIEUDANE"
    fi
'

# Tworzenie archiwum z pobranych stron
echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"
echo "Tworzenie archiwum tar.gz..." | tee -a "$GLOBALNY_LOG"
cd "$KATALOG_GLOWNY" || exit 1
TAR_FILE="Backup_${DATA}_$(date +%H%M%S).tar.gz"
tar -czf "$TAR_FILE" "$(basename "$KATALOG_BACKUPU")"

echo "📦 Utworzono archiwum: $PWD/$TAR_FILE" | tee -a "$GLOBALNY_LOG"
echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"

# Podsumowanie
if [ -s "$NIEUDANE" ]; then
    echo "❗ Wystąpiły błędy podczas pobierania następujących stron:" | tee -a "$GLOBALNY_LOG"
    cat "$NIEUDANE" | tee -a "$GLOBALNY_LOG"
else
    echo "🎉 Wszystkie strony zostały pobrane pomyślnie!" | tee -a "$GLOBALNY_LOG"
fi
