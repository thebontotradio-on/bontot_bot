#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Automated Setup Script for Android Termux (RAM 4 GB)
# Biaya: Rp0 | Tanpa Kartu Kredit | Berjalan 24/7 di Background
# ==============================================================================

set -e

echo "=== [1/6] Memeriksa Arsitektur Perangkat ==="
ARCH=$(uname -m)
echo "Arsitektur CPU: $ARCH"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv8l" ]; then
    echo "[PERINGATAN] Arsitektur bukan ARM64. Performa inferensi AI lokal mungkin terbatas."
fi

echo "=== [2/6] Memperbarui Repositori & Paket Dasar Termux ==="
pkg update -y && pkg upgrade -y
pkg install -y nodejs-lts git clang make python build-essential sqlite libsqlite termux-api termux-exec curl tar openssl

echo "=== [3/6] Mengaktifkan Termux Wake-Lock (Cegah Sleep Mode) ==="
termux-wake-lock
echo "Wake-lock diaktifkan. CPU Android tidak akan dimatikan saat layar mati."

echo "=== [4/6] Menyiapkan Folder Kerja & Penyimpanan Persisten ==="
PROJECT_DIR="$HOME/wa-bontot"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/logs"
mkdir -p "$PROJECT_DIR/backups"
mkdir -p "$PROJECT_DIR/models"

# Folder sesi auth dan database dipastikan terisolasi di internal storage Termux yang aman
mkdir -p "$PROJECT_DIR/server/auth_session"
mkdir -p "$PROJECT_DIR/server/data"
chmod 700 "$PROJECT_DIR/server/auth_session"
chmod 700 "$PROJECT_DIR/server/data"

echo "=== [5/6] Memasang Dependensi Node.js & Validasi better-sqlite3 ==="
cd "$PROJECT_DIR"
if [ -f "package.json" ]; then
    echo "Memasang modul dependensi..."
    npm install --omit=dev || npm install --omit=dev --build-from-source better-sqlite3
    
    # Uji apakah driver better-sqlite3 berhasil dimuat
    if node -e "require('better-sqlite3')" >/dev/null 2>&1; then
        echo "✔ Driver SQLite (better-sqlite3) berhasil dikompilasi dan siap digunakan."
    else
        echo "✖ better-sqlite3 memerlukan proot glibc. Menyiapkan alternatif proot-distro..."
        pkg install -y proot-distro
        echo "proot-distro terpasang untuk isolasi glibc stabil jika diperlukan."
    fi
else
    echo "Berkas package.json belum ada di $PROJECT_DIR. Ekstrak bundle terlebih dahulu."
fi

echo "=== [6/6] Menyiapkan Autostart Termux:Boot (Reboot Persistence) ==="
BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
cat << 'EOF' > "$BOOT_DIR/start-wa-bontot.sh"
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sleep 10
bash "$HOME/wa-bontot/android/start-service.sh" >> "$HOME/wa-bontot/logs/boot.log" 2>&1 &
EOF
chmod +x "$BOOT_DIR/start-wa-bontot.sh"

echo ""
echo "=== Menjalankan Uji Kesiapan Akhir ==="
if [ -f "$PROJECT_DIR/android/check-readiness.sh" ]; then
    bash "$PROJECT_DIR/android/check-readiness.sh" "$PROJECT_DIR"
fi

echo ""
echo "=============================================================================="
echo "✔ PENGATURAN TERMUX SELESAI"
echo "Langkah penting di Pengaturan Android HP Anda:"
echo "1. Buka Pengaturan HP -> Aplikasi -> Termux -> Baterai -> Pilih 'Tidak Dibatasi' (Unrestricted)."
echo "2. Kunci aplikasi Termux di menu Recent Apps (ikon gembok) agar tidak dibersihkan RAM cleaner."
echo "=============================================================================="
