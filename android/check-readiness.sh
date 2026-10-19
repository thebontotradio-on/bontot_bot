#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Pre-flight Readiness Check
# Memastikan seluruh prasyarat terpenuhi sebelum server diluncurkan
# ==============================================================================

PROJECT_DIR="${1:-$HOME/wa-bontot}"
cd "$PROJECT_DIR" || exit 1

ERRORS=0

echo "=== MEMERIKSA KESIAPAN SISTEM SI BONTOT ==="

# 1. Cek Node.js Runtime
if ! command -v node >/dev/null 2>&1; then
    echo "[GAGAL] Node.js belum terpasang di sistem!"
    ERRORS=$((ERRORS + 1))
else
    NODE_VER=$(node -v)
    echo "[OK] Node.js terdeteksi: $NODE_VER"
fi

# 2. Cek Berkas Server Inti
REQUIRED_SERVER_FILES=("server/index.js" "server/whatsapp.js" "server/ai.js" "server/db.js" "server/utils.js")
for f in "${REQUIRED_SERVER_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "[GAGAL] Berkas penting tidak ditemukan: $f"
        ERRORS=$((ERRORS + 1))
    fi
done

# 3. Cek Modul Node (node_modules)
if [ ! -d "node_modules" ] || [ ! -d "node_modules/@whiskeysockets/baileys" ]; then
    echo "[GAGAL] Dependensi node_modules belum terpasang lengkap! Jalankan instalasi terlebih dahulu."
    ERRORS=$((ERRORS + 1))
else
    echo "[OK] Dependensi Node.js (@whiskeysockets/baileys) tersedia."
fi

# 4. Cek Driver Database SQLite
if node -e "require('better-sqlite3')" >/dev/null 2>&1; then
    echo "[OK] Driver database SQLite (better-sqlite3) berfungsi normal."
else
    echo "[GAGAL] Driver SQLite (better-sqlite3) gagal dimuat! Cek kompilasi native addon."
    ERRORS=$((ERRORS + 1))
fi

# 5. Cek Aset Statis Frontend (client/dist)
if [ ! -f "client/dist/index.html" ]; then
    echo "[PERINGATAN] client/dist/index.html tidak ditemukan! Dashboard web mungkin tidak bisa dibuka."
else
    echo "[OK] Frontend statis (client/dist) siap disajikan."
fi

# 6. Cek Folder Persisten dan Hak Akses
mkdir -p server/auth_session server/data backups logs
chmod 700 server/auth_session server/data backups logs
echo "[OK] Folder sesi dan database terisolasi aman (chmod 700)."

# Evaluasi Akhir
if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "=========================================================="
    echo "[STOP] Ditemukan $ERRORS masalah kritis!"
    echo "Sistem menolak berjalan dalam kondisi setengah terpasang."
    echo "=========================================================="
    exit 1
fi

echo ""
echo "[SIAP] Seluruh komponen lolos uji kesiapan. Server aman dijalankan."
exit 0
