import os
import subprocess
from pathlib import Path
from datetime import datetime
from tqdm import tqdm
import tarfile

# === Ustawienia ===
DOMENY_PLIK = "domeny.txt"
KATALOG_BAZOWY = Path("/home/bodzio/Kopia_Domen_URK")
NAZWA_BACKUPU = "Kopia_Stron_HTTrack"
DATA = datetime.now().strftime("%Y-%m-%d")
BACKUP_DIR = KATALOG_BAZOWY / f"{NAZWA_BACKUPU}_{DATA}"
BACKUP_DIR.mkdir(parents=True, exist_ok=True)

LOG_PLIK = BACKUP_DIR / "backup_log.txt"
BLEDY_PLIK = BACKUP_DIR / "nieudane_pobrania.txt"

HTTRACK_OPCJE = [
    "--mirror",
    "-L1",
    "--stay-on-same-domain", "{domena}",  # UWAGA: tu podstawiamy domenę dynamicznie
    "--timeout=5",
    "--retries=1",
    "-vv",
    "-w",
    "-f0",
    "-r99999",
    "-c32",
    "--connection-per-second=10",
    "--disable-security-limits",
    "-k",
    "-N1",
    "-s0",
    "-z",
    "--update",
]

def oczysc_domena(linia):
    return linia.strip().replace("https://", "").replace("http://", "").rstrip("/")

def zapisz_log(sciezka, tresc):
    with open(sciezka, "a") as f:
        f.write(tresc + "\n")

def uruchom_httrack(domena: str, katalog_docelowy: Path) -> bool:
    folder_strony = katalog_docelowy / f"Strona_{domena.replace('.', '_')}"
    log_plik = folder_strony.with_suffix(".log")

    cmd = [
        "httrack",
        f"https://{domena}",
        "-O", str(folder_strony),
        *HTTRACK_OPCJE
    ]

    try:
        with open(log_plik, "w") as log:
            proces = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )

            for linia in proces.stdout:
                print(linia, end="")  # pokazuj w terminalu
                log.write(linia)      # zapisz do logu

            proces.stdout.close()
            proces.wait()

        if proces.returncode == 0:
            zapisz_log(LOG_PLIK, f"✅ Sukces: {domena}")
            return True
        else:
            zapisz_log(LOG_PLIK, f"❌ Błąd: {domena}")
            zapisz_log(BLEDY_PLIK, domena)
            return False
    except Exception as e:
        zapisz_log(LOG_PLIK, f"❌ Błąd (wyjątek): {domena} - {e}")
        zapisz_log(BLEDY_PLIK, domena)
        return False


# === Wczytaj i oczyść domeny ===
DOMENY = []
with open(DOMENY_PLIK, "r", encoding="utf-8") as f:
    for linia in f:
        domena = oczysc_domena(linia)
        if domena and all(c.isalnum() or c in ".-" for c in domena):
            DOMENY.append(domena)

# === Pobieranie ===
print(f"📥 Rozpoczynam mirrorowanie {len(DOMENY)} stron z użyciem HTTrack...\n")
for domena in tqdm(DOMENY, desc="Mirrorowanie"):
    uruchom_httrack(domena, BACKUP_DIR)

# === Archiwizacja ===
archiwum_path = KATALOG_BAZOWY / f"{NAZWA_BACKUPU}_{DATA}_{datetime.now().strftime('%H%M%S')}.tar.gz"
with tarfile.open(archiwum_path, "w:gz") as tar:
    tar.add(BACKUP_DIR, arcname=BACKUP_DIR.name)

print(f"\n📦 Backup zakończony. Archiwum utworzone: {archiwum_path}")
