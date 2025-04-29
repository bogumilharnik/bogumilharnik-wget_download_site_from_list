#!/bin/bash

# Plik z listą domen (jedna domena na linię)
PLIK_LISTA="domeny.txt"

# Katalog bazowy w $HOME
KATALOG_GLOWNY="$HOME/Kopia_Stron_WGET"

# Nazwa backupu z datą
DATA=$(date +%Y-%m-%d)
KATALOG_BACKUPU="${KATALOG_GLOWNY}/Backup_${DATA}"
mkdir -p "$KATALOG_BACKUPU"

# Logi
GLOBALNY_LOG="${KATALOG_BACKUPU}/backup_log.txt"
NIEUDANE="${KATALOG_BACKUPU}/nieudane_pobrania.txt"
> "$GLOBALNY_LOG"
> "$NIEUDANE"

# Parametry pobierania
MAX_PROCESSES=4  # liczba równoległych procesów

# Eksport zmiennych do parallel
export KATALOG_BACKUPU GLOBALNY_LOG NIEUDANE

# Sprawdzanie wymaganych narzędzi
command -v wget >/dev/null 2>&1 || { echo "❌ wget nie jest zainstalowany."; exit 1; }
command -v parallel >/dev/null 2>&1 || { echo "❌ parallel nie jest zainstalowany."; exit 1; }

# Czyszczenie domen
oczysc_domena() {
    local domena="$1"
    domena="${domena#https://}"
    domena="${domena#http://}"
    domena="${domena%/}"
    echo "$domena"
}

# Czytanie listy
DOMENY=()
while IFS= read -r linia; do
    [ -z "$linia" ] && continue
    DOMENY+=("$(oczysc_domena "$linia")")
done < "$PLIK_LISTA"

# Pobieranie
printf "%s\n" "${DOMENY[@]}" | parallel --env KATALOG_BACKUPU --env GLOBALNY_LOG --env NIEUDANE -j "$MAX_PROCESSES" '
    domena={};
    if [[ -z "$domena" || ! "$domena" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo "⚠️ Pominięto: '$domena'" | tee -a "$GLOBALNY_LOG"
        exit 0
    fi

    echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"
    echo "Pobieranie: $domena" | tee -a "$GLOBALNY_LOG"
    echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"

    FOLDER="Strona_${domena//./_}"
    KATALOG="${KATALOG_BACKUPU}/${FOLDER}"
    LOG="${KATALOG}.log"
    mkdir -p "$KATALOG"

    {
        wget \
            --mirror \
            --convert-links \
            --adjust-extension \
            --page-requisites \
            --no-parent \
            --timeout=5 \
            --tries=2 \
            --wait=0.5 \
            --limit-rate=2m \
            --directory-prefix="$KATALOG" \
            "https://${domena}"
    } 2>&1 | tee "$LOG"

    EXIT_CODE=${PIPESTATUS[0]}

    if [ "$EXIT_CODE" -eq 0 ]; then
        echo "✅ OK: $domena" | tee -a "$GLOBALNY_LOG"
    else
        echo "❌ Błąd: $domena" | tee -a "$GLOBALNY_LOG"
        echo "$domena" >> "$NIEUDANE"
    fi
'

# Tworzenie archiwum
echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"
echo "Tworzenie archiwum..." | tee -a "$GLOBALNY_LOG"
cd "$KATALOG_GLOWNY" || exit 1
TAR_FILE="Backup_${DATA}_$(date +%H%M%S).tar.gz"
tar -czf "$TAR_FILE" "$(basename "$KATALOG_BACKUPU")"
echo "📦 Utworzono: $PWD/$TAR_FILE" | tee -a "$GLOBALNY_LOG"

# Podsumowanie
if [ -s "$NIEUDANE" ]; then
    echo "❗ Problemy z domenami:" | tee -a "$GLOBALNY_LOG"
    cat "$NIEUDANE" | tee -a "$GLOBALNY_LOG"
else
    echo "🎉 Wszystkie domeny pobrane poprawnie!" | tee -a "$GLOBALNY_LOG"
fi
