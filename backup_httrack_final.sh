#!/bin/bash

# Przyjmowanie parametrów - plik z domenami, katalog w HOME, nazwa backupu
PLIK_LISTA="$1"
KATALOG_USER="$2"
NAZWA_BACKUP="$3"

# Sprawdzanie czy podano wszystkie wymagane parametry
if [ -z "$PLIK_LISTA" ] || [ -z "$KATALOG_USER" ] || [ -z "$NAZWA_BACKUP" ]; then
    echo "❌ Użycie: $0 [plik_lista_domen] [katalog_w_HOME] [nazwa_backupu]"
    echo "Przykład: $0 lista.txt Kopia_Stron Backup"
    exit 1
fi

# Sprawdzanie czy plik istnieje
if [ ! -f "$PLIK_LISTA" ]; then
    echo "❌ Podany plik '$PLIK_LISTA' nie istnieje!"
    exit 1
fi

# Sprawdzanie poprawności zawartości pliku
while IFS= read -r linia; do
    [ -z "$linia" ] && continue
    if [[ ! "$linia" =~ ^(https?://)?[a-zA-Z0-9.-]+\.[a-z]{2,}$ ]]; then
        echo "❌ Nieprawidłowy wpis w pliku: '$linia'"
        exit 1
    fi
done < "$PLIK_LISTA"

# Bazowy katalog backupu w $HOME
KATALOG_GLOWNY="$HOME/$KATALOG_USER"

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

# Tworzenie katalogu backupu z datą
DATA=$(date +%Y-%m-%d)
KATALOG_BACKUPU="${KATALOG_GLOWNY}/${NAZWA_BACKUP}_${DATA}"
mkdir -p "$KATALOG_BACKUPU"

# Maksymalna liczba równoległych pobrań
MAX_PROCESSES=1  # Mały, by widzieć postępy

# Pliki do zapisywania błędów i logów
GLOBALNY_LOG="${KATALOG_BACKUPU}/backup_log.txt"
NIEUDANE="${KATALOG_BACKUPU}/nieudane_pobrania.txt"

# Czyścimy pliki
> "$GLOBALNY_LOG"
> "$NIEUDANE"

# Eksport zmiennych dla parallel
export KATALOG_BACKUPU
export KATALOG_GLOWNY
export GLOBALNY_LOG
export NIEUDANE

# Sprawdzanie wymaganych narzędzi
command -v httrack >/dev/null 2>&1 || { echo >&2 "❌ httrack nie jest zainstalowany. Przerwano."; exit 1; }
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
done < "$PLIK_LISTA"

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
        httrack "https://${domena}" \
            -O "$FOLDER_STRONY" \
            --mirror \
            -L1 \
            --stay-on-same-domain "$domena" \
            --timeout=5 \
            --retries=1 \
            -vv \
            -w \
            -f0 \
            -r9999 \
            -c16 \
            --connection-per-second=10 \
            --disable-security-limits \
            -K \
            -N1 \
            -s0 \
            -z
    } 2>&1 | tee "$LOGFILE"

    HTTRACK_EXIT_CODE=${PIPESTATUS[0]}

    if [ "$HTTRACK_EXIT_CODE" -eq 0 ]; then
        echo "✅ Sukces: $domena" | tee -a "$GLOBALNY_LOG"
    else
        echo "❌ Błąd: $domena" | tee -a "$GLOBALNY_LOG"
        echo "$domena" >> "$NIEUDANE"
    fi
'

# Tworzenie archiwum tar.gz
echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"
echo "Tworzenie archiwum tar.gz..." | tee -a "$GLOBALNY_LOG"
cd "$KATALOG_GLOWNY" || exit 1
TAR_FILE="${NAZWA_BACKUP}_${DATA}_$(date +%H%M%S).tar.gz"
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
