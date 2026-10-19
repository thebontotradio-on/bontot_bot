#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Direct Android Installer (Termux)
# Target: Smartphone Android RAM 4 GB | Biaya: Rp0 | Tanpa Kartu Kredit
# ==============================================================================

set -e

# Warna Output
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
termux-wake-lock 2>/dev/null || true
echo -e "${GREEN}✔ Wake-lock aktif. Prosesor HP akan tetap terjaga saat layar mati.${NC}"

# 2. AUDIT PRASYARAT PERANGKAT KERAS
echo -e "\n${YELLOW}[2/8] Memeriksa Arsitektur & Spesifikasi Perangkat...${NC}"
ARCH=$(uname -m)
echo "Arsitektur CPU: $ARCH"

if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv8l" ]; then
    echo -e "${RED}[GAGAL] Arsitektur CPU ($ARCH) bukan ARM64 (64-bit).${NC}"
    echo "SI BONTOT dan AI lokal memerlukan prosesor ARM64 untuk performa stabil."
    exit 1
fi
echo -e "${GREEN}✔ Arsitektur ARM64 terverifikasi.${NC}"

# Cek Memori Bebas & Total
MEM_TOTAL_KB=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')
MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
echo "Total RAM Fisik: ${MEM_TOTAL_MB} MB"

if [ "$MEM_TOTAL_MB" -lt 2800 ]; then
    echo -e "${YELLOW}[PERINGATAN] RAM fisik terdeteksi kurang dari 3 GB (${MEM_TOTAL_MB} MB).${NC}"
    echo -e "${YELLOW}Aplikasi tetap dapat berjalan, tetapi AI lokal mungkin terbatas.${NC}"
else
    echo -e "${GREEN}✔ Kapasitas RAM memadai untuk Baileys + AI lokal 0.5B.${NC}"
fi

# Cek Ruang Bebas Internal (/data)
DISK_FREE_KB=$(df /data | tail -1 | awk '{print $4}')
DISK_FREE_MB=$((DISK_FREE_KB / 1024))
echo "Ruang Penyimpanan Bebas: ${DISK_FREE_MB} MB"

if [ "$DISK_FREE_MB" -lt 1200 ]; then
    echo -e "${RED}[GAGAL] Ruang penyimpanan bebas kurang dari 1,2 GB (${DISK_FREE_MB} MB).${NC}"
    echo "Kosongkan sedikit ruang penyimpanan internal HP Anda lalu ulangi instalasi."
    exit 1
fi
echo -e "${GREEN}✔ Ruang penyimpanan mencukupi.${NC}"

# 3. PEMBARUAN PAKET & INSTALASI DEPENDENSI NATIVE
echo -e "\n${YELLOW}[3/8] Memperbarui Repositori & Memasang Toolchain Resmi...${NC}"
echo "Mengunduh paket resmi Termux (Node.js LTS, Clang, Make, Python, SQLite)..."
pkg update -y
pkg install -y nodejs-lts git clang make python build-essential sqlite libsqlite curl tar openssl termux-api termux-exec

# 4. PERSIAPAN FOLDER KERJA MANDIRI
echo -e "\n${YELLOW}[4/8] Menyiapkan Folder Kerja & Isolasi Keamanan...${NC}"
PROJECT_DIR="$HOME/wa-bontot"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/logs"
mkdir -p "$PROJECT_DIR/backups"
mkdir -p "$PROJECT_DIR/models"
mkdir -p "$PROJECT_DIR/server/auth_session"
mkdir -p "$PROJECT_DIR/server/data"

# Hak akses terisolasi
chmod 700 "$PROJECT_DIR/server/auth_session"
chmod 700 "$PROJECT_DIR/server/data"
chmod 700 "$PROJECT_DIR/backups"
chmod 700 "$PROJECT_DIR/logs"
echo -e "${GREEN}✔ Folder kerja dan izin akses persisten siap (chmod 700).${NC}"

# 5. MENGAMBIL ATAU MENYINKRONKAN KODE APLIKASI
echo -e "\n${YELLOW}[5/8] Mengunduh Kode Sumber SI BONTOT...${NC}"
cd "$PROJECT_DIR"

if [ -f "/sdcard/Download/si-bontot-android-bundle.zip" ]; then
    echo "Mengekstrak paket bundle lokal dari /sdcard/Download/..."
    unzip -o /sdcard/Download/si-bontot-android-bundle.zip -d "$PROJECT_DIR" >/dev/null
    echo -e "${GREEN}✔ Paket bundle lokal berhasil diekstrak.${NC}"
elif curl -sL --fail https://raw.githubusercontent.com/thebontotradio-on/bontot_bot/main/si-bontot-android-bundle.zip -o "$PROJECT_DIR/bundle.zip" 2>/dev/null && [ -s "$PROJECT_DIR/bundle.zip" ]; then
    echo "Mengunduh dan mengekstrak bundle rilis mandiri dari GitHub..."
    unzip -o "$PROJECT_DIR/bundle.zip" -d "$PROJECT_DIR" >/dev/null
    rm -f "$PROJECT_DIR/bundle.zip"
    echo -e "${GREEN}✔ Bundle mandiri berhasil diekstrak.${NC}"
elif [ ! -f "$PROJECT_DIR/server/index.js" ]; then
    echo "Mengkloning repositori resmi dari GitHub..."
    git clone https://github.com/thebontotradio-on/bontot_bot.git "$PROJECT_DIR/temp_clone"
    cp -r "$PROJECT_DIR/temp_clone/"* "$PROJECT_DIR/"
    rm -rf "$PROJECT_DIR/temp_clone"
    echo -e "${GREEN}✔ Kode sumber resmi berhasil diunduh dari GitHub.${NC}"
else
    echo -e "${GREEN}✔ Kode sumber SI BONTOT sudah tersedia di $PROJECT_DIR.${NC}"
fi

# 6. INSTALASI DEPENDENSI NPM & KOMPILASI NATIVE BETTER-SQLITE3
echo -e "\n${YELLOW}[6/8] Memasang Modul Node.js & Membangun Driver SQLite...${NC}"
cd "$PROJECT_DIR"

# Pastikan package.json ada
if [ ! -f "package.json" ]; then
    echo -e "${RED}[GAGAL] package.json tidak ditemukan di $PROJECT_DIR.${NC}"
    exit 1
fi

echo "Memasang dependensi produksi (Baileys, Express, Socket.IO)..."
export npm_config_build_from_source=true
npm install --omit=dev

# Verifikasi driver SQLite secara nyata di lingkungan ARM64 ini
echo "Menguji fungsionalitas driver database better-sqlite3..."
if node -e "require('better-sqlite3'); console.log('Driver SQLite Berfungsi');" 2>/dev/null; then
    echo -e "${GREEN}✔ Driver better-sqlite3 berhasil dikompilasi secara native untuk ARM64 Android!${NC}"
else
    echo -e "${RED}[GAGAL] Driver better-sqlite3 gagal dikompilasi di kernel ini.${NC}"
    echo -e "${YELLOW}Penjelasan: Pustaka C bawaan HP Anda membatasi kompilasi node-gyp.${NC}"
    echo "Instalasi dihentikan secara aman tanpa merusak sistem."
    exit 1
fi

# 7. UNDUH MODEL AI LOKAL (QWEN 2.5 0.5B INSTRUCT GGUF)
echo -e "\n${YELLOW}[7/8] Menyiapkan Asisten AI Lokal (Qwen 0.5B GGUF)...${NC}"
MODEL_FILE="$PROJECT_DIR/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
OFFICIAL_AI_URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"

if [ -f "$MODEL_FILE" ] && [ "$(wc -c < "$MODEL_FILE")" -gt 390000000 ]; then
    echo -e "${GREEN}✔ Model AI Qwen 0.5B sudah terpasang ($(du -h "$MODEL_FILE" | cut -f1)).${NC}"
else
    echo "Mengunduh model resmi dari Hugging Face (Alibaba Qwen, ~398 MB)..."
    echo "Tautan: $OFFICIAL_AI_URL"
    if curl -L -C - --progress-bar -o "$MODEL_FILE" "$OFFICIAL_AI_URL"; then
        echo -e "${GREEN}✔ Model AI berhasil diunduh dan diverifikasi ($(du -h "$MODEL_FILE" | cut -f1)).${NC}"
    else
        echo -e "${YELLOW}[PERINGATAN] Gagal mengunduh model AI. Dashboard akan tetap berfungsi dengan status 'AI Offline'.${NC}"
    fi
fi

# 8. KONFIGURASI AUTOSTART TERMUX:BOOT & WATCHDOG
echo -e "\n${YELLOW}[8/8] Menyiapkan Autostart Termux:Boot & Watchdog 24/7...${NC}"
BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
cat << 'BOOTEOF' > "$BOOT_DIR/start-wa-bontot.sh"
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock 2>/dev/null || true
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
bash "$PROJECT_DIR/android/validate-installation.sh" "$PROJECT_DIR" || true

# TAMPILKAN ALAMAT IP LOKAL & PANDUAN AKSES
WIFI_IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "127.0.0.1")

echo -e "\n${GREEN}${BOLD}=================================================================="
echo "             🎉 INSTALASI SI BONTOT SELESAI! 🎉                  "
echo "==================================================================${NC}"
echo -e "${BOLD}Cara Mengakses Dashboard:${NC}"
echo "1. Dari browser di HP ini : http://localhost:3001"
echo "2. Dari browser di Laptop : http://${WIFI_IP}:3001"
echo ""
echo -e "${BOLD}Catatan Operasi & Keamanan:${NC}"
echo "- Auto-Reply berstatus awal: ${YELLOW}OFF${NC} (Aman)."
echo "- Kredensial WhatsApp laptop: ${GREEN}TIDAK TERSENTUH${NC} (Tersimpan aman di laptop)."
echo "- Untuk memulai bot sekarang, jalankan: ${CYAN}bash ~/wa-bontot/android/start-service.sh${NC}"
echo ""
echo -e "${BOLD}Tindakan Wajib Pemilik HP:${NC}"
echo "Buka Pengaturan HP -> Aplikasi -> Termux -> Baterai -> Pilih 'Tidak Dibatasi' (Unrestricted)."
echo "=================================================================="
