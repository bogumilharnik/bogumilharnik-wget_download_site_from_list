#!/bin/bash

# Plik z listą domen (jedna domena na linię, np. api.urk.edu.pl)
PLIK_LISTA="$1"
KATALOG_USER="$2"
NAZWA_BACKUP="$3"

# Sprawdzenie czy podano wszystkie wymagane parametry
if [ -z "$PLIK_LISTA" ] || [ -z "$KATALOG_USER" ] || [ -z "$NAZWA_BACKUP" ]; then
    echo "❌ Użycie: $0 [plik_lista_domen] [katalog_w_HOME] [nazwa_backupu]"
    echo "Przykład: $0 domeny.txt Kopia_Stron Backup_test"
    exit 1
fi

# Bazowy katalog backupu w $HOME
KATALOG_GLOWNY="$HOME/$KATALOG_USER"

# Tworzenie katalogu jeśli nie istnieje
mkdir -p "$KATALOG_GLOWNY"

# Tworzenie katalogu backupu z datą
DATA=$(date +%Y-%m-%d)
KATALOG_BACKUPU="${KATALOG_GLOWNY}/${NAZWA_BACKUP}_${DATA}"
mkdir -p "$KATALOG_BACKUPU"

# Logi
GLOBALNY_LOG="${KATALOG_BACKUPU}/backup_log.txt"
NIEUDANE="${KATALOG_BACKUPU}/nieudane_pobrania.txt"
> "$GLOBALNY_LOG"
> "$NIEUDANE"

# Parametry pobierania
MAX_PROCESSES=4

# Sprawdzanie wymaganych narzędzi
command -v wget >/dev/null 2>&1 || { echo "❌ wget nie jest zainstalowany."; exit 1; }
command -v parallel >/dev/null 2>&1 || { echo "❌ parallel nie jest zainstalowany."; exit 1; }

# Czytanie listy i oczyszczanie domen
DOMENY=()
while IFS= read -r linia; do
    [ -z "$linia" ] && continue
    domena="${linia#https://}"
    domena="${domena#http://}"
    domena="${domena%/}"
    DOMENY+=("$domena")
done < "$PLIK_LISTA"

# Pobieranie
printf "%s\n" "${DOMENY[@]}" | parallel -j "$MAX_PROCESSES" bash -c '
    domena="$1"; shift

    if [[ -z "$domena" || ! "$domena" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo "⚠️ Pominięto: $domena" | tee -a "'"$GLOBALNY_LOG"'"
        exit 0
    fi

    echo "--------------------------------------------------" | tee -a "'"$GLOBALNY_LOG"'"
    echo "Pobieranie: $domena" | tee -a "'"$GLOBALNY_LOG"'"
    echo "--------------------------------------------------" | tee -a "'"$GLOBALNY_LOG"'"

    FOLDER="Strona_${domena//./_}"
    KATALOG="'"$KATALOG_BACKUPU"'/${FOLDER}"
    LOG="${KATALOG}.log"
    mkdir -p "$KATALOG"

    ROOT_DOMENA=$(echo "$domena" | awk -F. '\''{if (NF>1) printf "%s.%s", $(NF-1), $NF; else print $0}'\'')

    {
        wget \
            --mirror \
            --convert-links \
            --adjust-extension \
            --page-requisites \
            --no-parent \
            --span-hosts \
            --domains="$domena,$ROOT_DOMENA" \
            --no-check-certificate \
            --timeout=10 \
            --tries=2 \
            --wait=0.5 \
            --limit-rate=3m \
            --directory-prefix="$KATALOG" \
            "https://${domena}"
    } 2>&1 | tee "$LOG"

    EXIT_CODE=${PIPESTATUS[0]}

    if [ "$EXIT_CODE" -eq 0 ]; then
        echo "✅ OK: $domena" | tee -a "'"$GLOBALNY_LOG"'"
    else
        echo "❌ Błąd: $domena" | tee -a "'"$GLOBALNY_LOG"'"
        echo "$domena" >> "'"$NIEUDANE"'"
    fi
' _ {}

# Tworzenie archiwum
echo "--------------------------------------------------" | tee -a "$GLOBALNY_LOG"
echo "Tworzenie archiwum..." | tee -a "$GLOBALNY_LOG"
cd "$KATALOG_GLOWNY" || exit 1
TAR_FILE="${NAZWA_BACKUP}_${DATA}_$(date +%H%M%S).tar.gz"
tar -czf "$TAR_FILE" "$(basename "$KATALOG_BACKUPU")"
echo "📦 Utworzono: $PWD/$TAR_FILE" | tee -a "$GLOBALNY_LOG"

# Podsumowanie
if [ -s "$NIEUDANE" ]; then
    echo "❗ Problemy z domenami:" | tee -a "$GLOBALNY_LOG"
    cat "$NIEUDANE" | tee -a "$GLOBALNY_LOG"
else
    echo "🎉 Wszystkie domeny pobrane poprawnie!" | tee -a "$GLOBALNY_LOG"
fi
