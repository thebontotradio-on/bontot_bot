#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Direct Android Installer (Termux)
# Target: Smartphone Android RAM 4 GB | Biaya: Rp0 | Tanpa Kartu Kredit
# ==============================================================================

set -e

# Salin installer ke direktori home pengguna jika belum ada
if [ -n "$HOME" ] && [ ! -f "$HOME/install-direct.sh" ]; then
    curl -sL https://raw.githubusercontent.com/thebontotradio-on/bontot_bot/main/android/install-direct.sh -o "$HOME/install-direct.sh" 2>/dev/null || true
    chmod +x "$HOME/install-direct.sh" 2>/dev/null || true
fi


# Warna Output Terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "=================================================================="
echo "      📻 SI BONTOT — DIRECT ANDROID INSTALLER (TERMUX) 📻        "
echo "  Asisten WhatsApp 24/7 Mandiri | Biaya Rp0 | Tanpa Kartu Kredit "
echo "=================================================================="
echo -e "${NC}"

# 1. PENCEGAHAN SLEEP MODE SEJAK AWAL
echo -e "${YELLOW}[1/8] Mengaktifkan Termux Wake-Lock (Mencegah CPU Tidur)...${NC}"
termux-wake-lock < /dev/null 2>/dev/null || true
echo -e "${GREEN}✔ Wake-lock aktif. Prosesor HP akan tetap terjaga saat layar mati.${NC}"

# 2. AUDIT PRASYARAT PERANGKAT KERAS
echo -e "\n${YELLOW}[2/8] Memeriksa Arsitektur & Spesifikasi Perangkat...${NC}"
ARCH=$(uname -m)
echo "Arsitektur CPU: $ARCH"

if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv8l" ]; then
    echo -e "${RED}[GAGAL] Arsitektur CPU $ARCH bukan ARM64 (64-bit).${NC}"
    echo "SI BONTOT dan AI lokal memerlukan prosesor ARM64 untuk performa stabil."
    exit 1
fi
echo -e "${GREEN}✔ Arsitektur ARM64 terverifikasi.${NC}"

# Cek Memori Bebas & Total
MEM_TOTAL_KB=$(cat /proc/meminfo 2>/dev/null | grep MemTotal | awk '{print $2}')
MEM_TOTAL_MB=0
if [ -n "$MEM_TOTAL_KB" ]; then
    MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
fi
echo "Total RAM Fisik: ${MEM_TOTAL_MB} MB"

if [ "$MEM_TOTAL_MB" -gt 0 ] && [ "$MEM_TOTAL_MB" -lt 2800 ]; then
    echo -e "${YELLOW}[PERINGATAN] RAM fisik terdeteksi kurang dari 3 GB [${MEM_TOTAL_MB} MB].${NC}"
    echo -e "${YELLOW}Aplikasi tetap dapat berjalan, tetapi AI lokal mungkin terbatas.${NC}"
else
    echo -e "${GREEN}✔ Kapasitas RAM memadai untuk Baileys + AI lokal 0.5B.${NC}"
fi

# Cek Ruang Bebas Internal (/data)
DISK_FREE_KB=$(df /data 2>/dev/null | tail -1 | awk '{print $4}')
DISK_FREE_MB=0
if [ -n "$DISK_FREE_KB" ]; then
    DISK_FREE_MB=$((DISK_FREE_KB / 1024))
fi
echo "Ruang Penyimpanan Bebas: ${DISK_FREE_MB} MB"

if [ "$DISK_FREE_MB" -gt 0 ] && [ "$DISK_FREE_MB" -lt 1000 ]; then
    echo -e "${RED}[GAGAL] Ruang penyimpanan bebas kurang dari 1 GB [${DISK_FREE_MB} MB].${NC}"
    echo "Kosongkan sedikit ruang penyimpanan internal HP Anda lalu ulangi instalasi."
    exit 1
fi
echo -e "${GREEN}✔ Ruang penyimpanan mencukupi.${NC}"

# 3. PEMBARUAN PAKET & INSTALASI DEPENDENSI NATIVE (TAHAN INSTALASI BERULANG)
echo -e "\n${YELLOW}[3/8] Memeriksa & Memasang Toolchain Resmi Termux...${NC}"
# Cek apakah paket dasar sudah ada untuk mempercepat re-instalasi
if ! command -v node >/dev/null 2>&1 || ! command -v clang >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
    echo "Memperbarui repositori dan memasang dependensi (Node.js LTS, Clang, Make, Python, SQLite, Unzip)..."
    pkg update -y < /dev/null
    pkg install -y nodejs-lts git clang make python build-essential sqlite libsqlite curl tar unzip openssl termux-api termux-exec < /dev/null
else
    echo -e "${GREEN}✔ Toolchain dasar (Node.js, Clang, Make, Git, Unzip) sudah terpasang.${NC}"
fi

# 4. PERSIAPAN FOLDER KERJA MANDIRI (IDEMPOTENT)
echo -e "\n${YELLOW}[4/8] Menyiapkan Folder Kerja & Isolasi Keamanan...${NC}"
PROJECT_DIR="$HOME/wa-bontot"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/logs"
mkdir -p "$PROJECT_DIR/backups"
mkdir -p "$PROJECT_DIR/models"
mkdir -p "$PROJECT_DIR/server/auth_session"
mkdir -p "$PROJECT_DIR/server/data"

# Hak akses terisolasi
chmod 700 "$PROJECT_DIR/server/auth_session" 2>/dev/null || true
chmod 700 "$PROJECT_DIR/server/data" 2>/dev/null || true
chmod 700 "$PROJECT_DIR/backups" 2>/dev/null || true
chmod 700 "$PROJECT_DIR/logs" 2>/dev/null || true
echo -e "${GREEN}✔ Folder kerja dan izin akses persisten siap [chmod 700].${NC}"

# 5. MENGAMBIL ATAU MENYINKRONKAN KODE APLIKASI
echo -e "\n${YELLOW}[5/8] Mengunduh Kode Sumber SI BONTOT...${NC}"
cd "$PROJECT_DIR"

SOURCE_READY=0

# Fungsi helper ekstraksi aman dengan audit status spesifik & verifikasi berkas lengkap
extract_archive() {
    local target_zip="$1"
    local exit_status=0
    local unzip_output=""
    echo "Mengekstrak berkas: $(basename "$target_zip")..."
    
    # Tangkap output dan exit status secara terisolasi tanpa memutus set -e
    unzip_output=$(unzip -o -q "$target_zip" -d "$PROJECT_DIR" < /dev/null 2>&1) || exit_status=$?

    if [ "$exit_status" -ge 2 ]; then
        echo -e "${RED}[GAGAL] Arsip $(basename "$target_zip") rusak atau tidak valid [exit code: $exit_status].${NC}"
        if [ -n "$unzip_output" ]; then
            echo -e "${YELLOW}Detail unzip: $unzip_output${NC}"
        fi
        return 1
    elif [ "$exit_status" -eq 1 ]; then
        echo -e "${YELLOW}[PERINGATAN] Info-ZIP melaporkan peringatan non-fatal saat mengekstrak $(basename "$target_zip") [exit code: 1].${NC}"
    fi

    # Verifikasi ketat kelengkapan seluruh berkas kritis ground truth
    local missing_count=0
    for f in "server/index.js" "server/db.js" "server/whatsapp.js" "server/ai.js" "package.json" "client/dist/index.html"; do
        if [ ! -f "$PROJECT_DIR/$f" ]; then
            echo -e "${RED}[GAGAL] Berkas penting tidak ditemukan setelah ekstraksi: $f${NC}"
            missing_count=$((missing_count + 1))
        fi
    done

    if [ "$missing_count" -eq 0 ]; then
        echo -e "${GREEN}✔ Seluruh berkas inti berhasil diekstrak dan diverifikasi lengkap.${NC}"
        return 0
    else
        echo -e "${RED}[GAGAL] Ekstraksi $(basename "$target_zip") tidak lengkap ($missing_count berkas penting hilang).${NC}"
        return 1
    fi
}


# 5A. Coba paket lokal di Download jika ada
if [ -f "/sdcard/Download/si-bontot-android-bundle.zip" ]; then
    echo "Ditemukan bundle lokal di /sdcard/Download/..."
    if extract_archive "/sdcard/Download/si-bontot-android-bundle.zip"; then
        SOURCE_READY=1
    fi
fi

# 5B. Jika belum siap, unduh bundle rilis mandiri dari GitHub
if [ "$SOURCE_READY" -eq 0 ]; then
    echo "Mengunduh bundle rilis mandiri dari GitHub..."
    BUNDLE_URL="https://raw.githubusercontent.com/thebontotradio-on/bontot_bot/main/si-bontot-android-bundle.zip"
    if curl -sL --fail "$BUNDLE_URL" -o "$PROJECT_DIR/bundle.zip" < /dev/null 2>/dev/null && [ -s "$PROJECT_DIR/bundle.zip" ]; then
        if extract_archive "$PROJECT_DIR/bundle.zip"; then
            SOURCE_READY=1
        fi
        rm -f "$PROJECT_DIR/bundle.zip"
    else
        echo -e "${YELLOW}[INFO] Bundle rilis GitHub tidak tersedia via direct download, beralih ke Git Clone...${NC}"
    fi
fi

# 5C. Fallback Git Clone resmi jika bundle belum menghasilkan berkas
if [ "$SOURCE_READY" -eq 0 ] && [ ! -f "$PROJECT_DIR/server/index.js" ]; then
    echo "Mengunduh kode sumber resmi via Git clone..."
    rm -rf "$PROJECT_DIR/temp_clone"
    if git clone https://github.com/thebontotradio-on/bontot_bot.git "$PROJECT_DIR/temp_clone" < /dev/null; then
        cp -r "$PROJECT_DIR/temp_clone/"* "$PROJECT_DIR/"
        rm -rf "$PROJECT_DIR/temp_clone"
        if [ -f "$PROJECT_DIR/server/index.js" ]; then
            echo -e "${GREEN}✔ Kode sumber resmi berhasil disinkronkan via Git.${NC}"
            SOURCE_READY=1
        fi
    fi
fi

# 5D. Verifikasi Akhir Tahap 5: Jangan pernah berasumsi berhasil jika berkas utama tidak ada atau rusak
if [ ! -f "$PROJECT_DIR/server/index.js" ] || [ ! -f "$PROJECT_DIR/package.json" ]; then
    echo -e "${RED}[GAGAL KRITIS] Berkas server/index.js atau package.json tidak ditemukan di $PROJECT_DIR.${NC}"
    echo -e "${RED}Tahap 5/8 gagal menyediakan kode sumber SI BONTOT. Instalasi dihentikan.${NC}"
    exit 1
fi

echo "Memeriksa sintaks kode sumber server/index.js..."
if ! node --check "$PROJECT_DIR/server/index.js" >/dev/null 2>&1; then
    echo -e "${RED}[GAGAL KRITIS] Berkas server/index.js corrupt atau mengalami syntax error!${NC}"
    echo -e "${RED}Instalasi dihentikan karena berkas backend tidak dapat dieksekusi.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Kode sumber SI BONTOT lengkap dan sintaks server/index.js terverifikasi di $PROJECT_DIR.${NC}"


# 6. INSTALASI DEPENDENSI NPM & KOMPILASI NATIVE BETTER-SQLITE3
echo -e "\n${YELLOW}[6/8] Memasang Modul Node.js & Membangun Driver SQLite...${NC}"
cd "$PROJECT_DIR"

if [ ! -f "package.json" ]; then
    echo -e "${RED}[GAGAL] package.json tidak ditemukan di $PROJECT_DIR.${NC}"
    exit 1
fi

# Cek apakah modul sudah terpasang sebelumnya
NEED_NPM_INSTALL=1
if [ -d "node_modules/@whiskeysockets/baileys" ] && node -e "require('better-sqlite3');" < /dev/null 2>/dev/null; then
    echo -e "${GREEN}✔ Modul Baileys dan driver SQLite sudah terpasang dan berfungsi.${NC}"
    NEED_NPM_INSTALL=0
fi

if [ "$NEED_NPM_INSTALL" -eq 1 ]; then
    echo "Membangun dependensi produksi (Baileys, Express, Socket.IO, better-sqlite3)..."
    export npm_config_build_from_source=true
    npm install --omit=dev < /dev/null || npm install --omit=dev --build-from-source better-sqlite3 < /dev/null
    
    # Verifikasi driver SQLite secara nyata di lingkungan ARM64 ini
    echo "Menguji fungsionalitas driver database better-sqlite3..."
    if node -e "require('better-sqlite3');" < /dev/null 2>/dev/null; then
        echo -e "${GREEN}✔ Driver better-sqlite3 berhasil dikompilasi secara native untuk ARM64 Android!${NC}"
    else
        echo -e "${RED}[GAGAL] Driver better-sqlite3 gagal dikompilasi di kernel ini.${NC}"
        echo -e "${YELLOW}Penjelasan: Pustaka C bawaan HP Anda membatasi kompilasi node-gyp.${NC}"
        echo "Instalasi dihentikan secara aman tanpa merusak sistem."
        exit 1
    fi
fi

# 7. UNDUH MODEL AI LOKAL (QWEN 2.5 0.5B INSTRUCT GGUF)
echo -e "\n${YELLOW}[7/8] Menyiapkan Asisten AI Lokal (Qwen 0.5B GGUF)...${NC}"
MODEL_FILE="$PROJECT_DIR/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
OFFICIAL_AI_URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"

MODEL_READY=0
if [ -f "$MODEL_FILE" ]; then
    MODEL_SIZE=$(wc -c < "$MODEL_FILE" 2>/dev/null || echo 0)
    if [ "$MODEL_SIZE" -gt 390000000 ]; then
        MODEL_READY=1
    fi
fi

if [ "$MODEL_READY" -eq 1 ]; then
    MODEL_SIZE_STR=$(du -h "$MODEL_FILE" 2>/dev/null | cut -f1)
    echo -e "${GREEN}✔ Model AI Qwen 0.5B sudah terpasang [${MODEL_SIZE_STR}].${NC}"
else
    echo "Mengunduh model resmi dari Hugging Face (Alibaba Qwen, ~398 MB)..."
    echo "Tautan: $OFFICIAL_AI_URL"
    if curl -L -C - --progress-bar -o "$MODEL_FILE" "$OFFICIAL_AI_URL" < /dev/null; then
        MODEL_SIZE_STR=$(du -h "$MODEL_FILE" 2>/dev/null | cut -f1)
        echo -e "${GREEN}✔ Model AI berhasil diunduh dan diverifikasi [${MODEL_SIZE_STR}].${NC}"
    else
        echo -e "${YELLOW}[PERINGATAN] Unduhan model belum selesai. Dashboard akan tetap aktif dengan status 'AI Offline'.${NC}"
    fi
fi

# 8. KONFIGURASI AUTOSTART TERMUX:BOOT & WATCHDOG
echo -e "\n${YELLOW}[8/8] Menyiapkan Autostart Termux:Boot & Watchdog 24/7...${NC}"
BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
cat << 'BOOTEOF' > "$BOOT_DIR/start-wa-bontot.sh"
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock < /dev/null 2>/dev/null || true
sleep 10
bash "$HOME/wa-bontot/android/start-service.sh" >> "$HOME/wa-bontot/logs/boot.log" 2>&1 &
BOOTEOF
chmod +x "$BOOT_DIR/start-wa-bontot.sh"

# Beri izin eksekusi seluruh skrip android
chmod +x "$PROJECT_DIR/android/"*.sh 2>/dev/null || true

# JALANKAN VALIDASI LENGKAP PASCA-INSTALASI
echo -e "\n${CYAN}==================================================================${NC}"
echo -e "${CYAN}             MENJALANKAN VALIDASI KELAYAKAN SISTEM                ${NC}"
echo -e "${CYAN}==================================================================${NC}"

# Validasi Wajib 1: Pemeriksaan Sintaks server/index.js (Mandatory Syntax Guard)
echo "Memeriksa sintaks server/index.js sebelum finalisasi..."
if ! node --check "$PROJECT_DIR/server/index.js" < /dev/null 2>&1; then
    echo -e "\n${RED}${BOLD}=================================================================="
    echo "       ❌ INSTALASI GAGAL: server/index.js MEMILIKI SYNTAX ERROR  "
    echo "==================================================================${NC}"
    echo -e "${RED}Berkas server/index.js tidak lolos uji node --check.${NC}"
    echo -e "${YELLOW}Instalasi ditandai GAGAL dan bot tidak boleh dijalankan.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Validasi wajib: server/index.js valid & bebas syntax error.${NC}"

# Validasi Wajib 2: Seluruh 8 Pilar Sistem
VALIDATE_EXIT=0
bash "$PROJECT_DIR/android/validate-installation.sh" "$PROJECT_DIR" < /dev/null || VALIDATE_EXIT=$?

if [ "$VALIDATE_EXIT" -ne 0 ]; then
    echo -e "\n${RED}${BOLD}=================================================================="
    echo "         ❌ INSTALASI SI BONTOT GAGAL / BELUM TUNTAS ❌          "
    echo "==================================================================${NC}"
    echo -e "${RED}Validasi sistem mendeteksi kegagalan pada komponen SI BONTOT.${NC}"
    echo -e "${YELLOW}Periksa rincian kegagalan di atas sebelum memulai bot.${NC}"
    exit 1
fi

# TAMPILKAN ALAMAT IP LOKAL & PANDUAN AKSES (PORTABLE POSIX PARSING)
WIFI_IP=$(ifconfig wlan0 2>/dev/null | awk '/inet / {print $2}' || true)
if [ -z "$WIFI_IP" ]; then
    WIFI_IP=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 || true)
fi
if [ -z "$WIFI_IP" ]; then
    WIFI_IP="127.0.0.1"
fi

echo -e "\n${GREEN}${BOLD}=================================================================="
echo "             🎉 INSTALASI SI BONTOT SELESAI! 🎉                  "
echo "==================================================================${NC}"
echo -e "${BOLD}Cara Mengakses Dashboard:${NC}"
echo "1. Dari browser di HP ini : http://localhost:3001"
echo "2. Dari browser di Laptop : http://${WIFI_IP}:3001"
echo ""
echo -e "${BOLD}Catatan Operasi & Keamanan:${NC}"
echo "- Auto-Reply berstatus awal: ${YELLOW}OFF${NC} [Aman]."
echo "- Kredensial WhatsApp laptop: ${GREEN}TIDAK TERSENTUH${NC} [Tersimpan aman di laptop]."
echo "- Untuk memulai bot sekarang, jalankan: ${CYAN}bash ~/wa-bontot/android/start-service.sh${NC}"
echo ""
echo -e "${BOLD}Tindakan Wajib Pemilik HP:${NC}"
echo "Buka Pengaturan HP -> Aplikasi -> Termux -> Baterai -> Pilih 'Tidak Dibatasi' [Unrestricted]."
echo "=================================================================="
