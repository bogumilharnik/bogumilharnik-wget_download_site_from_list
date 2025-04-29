#!/bin/bash

# Odczytanie parametrów wywołania
LISTA_DOMEN="$1"
KATALOG_GLOWNY="$2"
NAZWA_BACKUPU="$3"

# Sprawdzenie poprawności parametrów
if [ -z "$LISTA_DOMEN" ] || [ -z "$KATALOG_GLOWNY" ] || [ -z "$NAZWA_BACKUPU" ]; then
    echo "❌ Użycie: $0 <lista_domen.txt> <katalog_glowny> <nazwa_backupu>"
    exit 1
fi

# Sprawdzanie czy plik domen istnieje
if [ ! -f "$LISTA_DOMEN" ]; then
    echo "❌ Plik listy domen nie istnieje: $LISTA_DOMEN"
    exit 1
fi

# Tworzenie katalogu backupu z datą
DATA=$(date +%Y-%m-%d)
KATALOG_BACKUPU="${KATALOG_GLOWNY}/${NAZWA_BACKUPU}_${DATA}"
mkdir -p "$KATALOG_BACKUPU"

# Maksymalna liczba równoległych pobrań
MAX_PROCESSES=2

# Pliki logów
GLOBALNY_LOG="${KATALOG_BACKUPU}/backup_log.txt"
NIEUDANE="${KATALOG_BACKUPU}/nieudane_pobrania.txt"

> "$GLOBALNY_LOG"
> "$NIEUDANE"

# Eksport zmiennych, aby były widoczne w parallel
export KATALOG_BACKUPU
export GLOBALNY_LOG
export NIEUDANE

# Sprawdzenie czy wymagane narzędzia są zainstalowane
command -v wget >/dev/null 2>&1 || { echo "❌ wget nie jest zainstalowany."; exit 1; }
command -v parallel >/dev/null 2>&1 || { echo "❌ parallel nie jest zainstalowany."; exit 1; }

# Funkcja czyszcząca wpis domeny (usuwa https://, http://, końcowe /)
oczysc_domena() {
    local domena="$1"
    domena="${domena#https://}"
    domena="${domena#http://}"
    domena="${domena%/}"
    echo "$domena"
}

# Czytanie listy domen i oczyszczanie
DOMENY=()
while IFS= read -r linia; do
    # Usuwanie ukrytych znaków np. \r (Windows), spacji z początku/końca
    linia=$(echo "$linia" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Pominięcie pustych lub nieprawidłowych linii
    if [[ -z "$linia" || ! "$linia" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        continue
    fi

    # Oczyszczenie domeny
    domena=$(oczysc_domena "$linia")
    DOMENY+=("$domena")
done < "$LISTA_DOMEN"

# Pobieranie stron równolegle
printf "%s\n" "${DOMENY[@]}" | parallel --env KATALOG_BACKUPU --env GLOBALNY_LOG --env NIEUDANE -j "$MAX_PROCESSES" --colsep ' ' '
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
TAR_FILE="${NAZWA_BACKUPU}_${DATA}_$(date +%H%M%S).tar.gz"
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
