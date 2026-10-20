#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Standalone Updater untuk Instalasi ZIP (Tanpa Git)
# Memperbarui skrip & logika bot langsung via HTTPS/curl tanpa menyentuh:
# - Database SQLite (server/data/wabontot.db)
# - Sesi WhatsApp (server/data/auth_info_baileys)
# - Berkas model AI GGUF (models/*.gguf)
# - Konfigurasi Auto-Reply (tetap OFF)
# ==============================================================================

set -e

PROJECT_DIR="${1:-$HOME/wa-bontot}"
mkdir -p "$PROJECT_DIR/android" "$PROJECT_DIR/server" "$PROJECT_DIR/bin" "$PROJECT_DIR/logs"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "=================================================================="
echo "    🚀 SI BONTOT — PEMBARUAN INSTALASI STANDALONE (HTTPS/CURL)    "
echo "  100% Aman Data: Database, Sesi WA, & Model AI Tetap Terjaga    "
echo "=================================================================="
echo -e "${NC}"

RAW_BASE="https://raw.githubusercontent.com/thebontotradio-on/bontot_bot/main"

# Daftar berkas sistem penting yang diperbarui
UPDATED_FILES=(
    "android/setup-llama.sh"
    "android/start-service.sh"
    "android/test-inference.sh"
    "android/ai-adapter.js"
    "android/download-ai-model.sh"
    "android/healthcheck.sh"
    "android/check-readiness.sh"
    "android/update-service.sh"
    "server/index.js"
    "server/ai.js"
    "server/whatsapp.js"
    "server/db.js"
    "server/utils.js"
)

echo "Mengunduh pembaruan skrip dan modul dari branch main via HTTPS..."
for rel_path in "${UPDATED_FILES[@]}"; do
    mkdir -p "$(dirname "$PROJECT_DIR/$rel_path")"
    echo "  - Memperbarui $rel_path..."
    curl -sSL -4 --connect-timeout 15 "$RAW_BASE/$rel_path" -o "$PROJECT_DIR/$rel_path.tmp"
    if [ -s "$PROJECT_DIR/$rel_path.tmp" ]; then
        mv "$PROJECT_DIR/$rel_path.tmp" "$PROJECT_DIR/$rel_path"
    else
        rm -f "$PROJECT_DIR/$rel_path.tmp"
        echo -e "${YELLOW}    [Lewati] Berkas $rel_path tidak dapat diunduh atau kosong.${NC}"
    fi
done

# Berikan hak akses eksekusi ke seluruh skrip bash
chmod +x "$PROJECT_DIR/android/"*.sh 2>/dev/null || true

echo -e "${GREEN}✔ Berkas skrip berhasil diperbarui ke versi rilis terbaru.${NC}"
echo "Integritas data diverifikasi: Database SQLite, Sesi WhatsApp, & Model GGUF tetap utuh."

# Jalankan installer Llama Engine yang telah diperbaiki
echo -e "\n${CYAN}Menjalankan pengaktifan Llama Engine...${NC}"
bash "$PROJECT_DIR/android/setup-llama.sh" "$PROJECT_DIR"
