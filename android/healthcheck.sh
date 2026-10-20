#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Comprehensive Health & HTTP Diagnostic Check (Android)
# Menguji respons HTTP nyata port 3001 & 11434, bukan sekadar port terbuka
# ==============================================================================

PROJECT_DIR="${1:-$HOME/wa-bontot}"
cd "$PROJECT_DIR" || exit 1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== DIAGNOSTIK KESEHATAN SI BONTOT (ANDROID) ===${NC}"
echo "Waktu    : $(date)"
echo "Direktori: $PROJECT_DIR"
echo ""

HEALTH_FAILED=0

# ------------------------------------------------------------------------------
# 1. Audit Proses Berjalan & PID
# ------------------------------------------------------------------------------
echo -e "${BOLD}[1] Status Proses Sistem${NC}"
WATCHDOG_PID=$(cat "$PROJECT_DIR/logs/watchdog.pid" 2>/dev/null || echo "")
SERVER_PID=$(cat "$PROJECT_DIR/logs/server.pid" 2>/dev/null || echo "")
AI_PID=$(cat "$PROJECT_DIR/logs/ai_adapter.pid" 2>/dev/null || echo "")
LLAMA_PID=$(cat "$PROJECT_DIR/logs/llama.pid" 2>/dev/null || echo "")

print_proc_status() {
    local name="$1"
    local pid="$2"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo -e "  - $name: ${GREEN}AKTIF${NC} (PID: $pid)"
    else
        echo -e "  - $name: ${RED}TIDAK BERJALAN${NC}"
    fi
}

print_proc_status "Watchdog Supervisor" "$WATCHDOG_PID"
print_proc_status "Backend Node.js    " "$SERVER_PID"
print_proc_status "AI Adapter         " "$AI_PID"
print_proc_status "Llama Engine       " "$LLAMA_PID"

# ------------------------------------------------------------------------------
# 2. Pengujian Respons HTTP Nyata Backend (Port 3001)
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[2] Pengujian Respons HTTP Backend (Port 3001)${NC}"

# A. Uji API Status
API_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "http://127.0.0.1:3001/api/status" 2>/dev/null || echo "000")
API_BODY=$(curl -s --max-time 4 "http://127.0.0.1:3001/api/status" 2>/dev/null || echo "")

if [ "$API_HTTP_CODE" = "200" ] && [ -n "$API_BODY" ]; then
    echo -e "  - Endpoint GET /api/status : ${GREEN}HTTP 200 OK${NC}"
    echo -e "    Respons Payload           : $API_BODY"
else
    echo -e "  - Endpoint GET /api/status : ${RED}GAGAL${NC} (HTTP: $API_HTTP_CODE)"
    echo -e "    Penyebab: Backend tidak merespons pada port 3001."
    HEALTH_FAILED=$((HEALTH_FAILED + 1))
fi

# B. Uji Dashboard SPA (Web UI)
SPA_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "http://127.0.0.1:3001/" 2>/dev/null || echo "000")
SPA_SNIPPET=$(curl -s --max-time 4 "http://127.0.0.1:3001/" 2>/dev/null | head -n 3 || echo "")

if [ "$SPA_HTTP_CODE" = "200" ]; then
    echo -e "  - Dashboard SPA (Root /)   : ${GREEN}HTTP 200 OK (Web UI Siap)${NC}"
else
    echo -e "  - Dashboard SPA (Root /)   : ${YELLOW}HTTP $SPA_HTTP_CODE (Static file mungkin belum ter-build)${NC}"
fi

# ------------------------------------------------------------------------------
# 3. Pengujian Respons HTTP Nyata Adapter AI (Port 11434)
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[3] Pengujian Respons HTTP AI Adapter (Port 11434)${NC}"

AI_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "http://127.0.0.1:11434/api/tags" 2>/dev/null || echo "000")
AI_BODY=$(curl -s --max-time 4 "http://127.0.0.1:11434/api/tags" 2>/dev/null || echo "")

if [ "$AI_HTTP_CODE" = "200" ]; then
    echo -e "  - Endpoint GET /api/tags   : ${GREEN}HTTP 200 OK (Adapter Merespons)${NC}"
    # Periksa apakah ada model aktif di dalam array
    if echo "$AI_BODY" | grep -q '"name":'; then
        MODEL_NAME=$(echo "$AI_BODY" | grep -o '"name":"[^"]*"' | head -n 1 | cut -d'"' -f4)
        echo -e "  - Status Inferensi AI      : ${GREEN}AKTIF${NC} (Model: $MODEL_NAME)"
    else
        echo -e "  - Status Inferensi AI      : ${YELLOW}STANDBY / SIAGA${NC} (Adapter online, llama-server offline/belum memuat model)"
        echo -e "    Catatan: Auto-Reply & WhatsApp tetap aman dan fungsional tanpa AI aktif."
    fi
else
    echo -e "  - Endpoint GET /api/tags   : ${YELLOW}OFFLINE${NC} (HTTP: $AI_HTTP_CODE - AI Adapter belum berjalan)"
fi

# ------------------------------------------------------------------------------
# 4. Audit Berkas Model GGUF di Disk
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[4] Berkas Model AI di Penyimpanan Internal${NC}"
GGUF_FILE="$PROJECT_DIR/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
if [ -f "$GGUF_FILE" ]; then
    GGUF_SIZE=$(du -h "$GGUF_FILE" 2>/dev/null | cut -f1)
    echo -e "  - Berkas GGUF : ${GREEN}ADA ($GGUF_SIZE)${NC} -> $GGUF_FILE"
else
    echo -e "  - Berkas GGUF : ${YELLOW}TIDAK DITEMUKAN${NC} (Dapat diunduh via android/download-ai-model.sh)"
fi

# ------------------------------------------------------------------------------
# 5. Ringkasan Diagnostik & Rekomendasi
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}--------------------------------------------------------${NC}"
if [ "$HEALTH_FAILED" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✔ HASIL KESEHATAN: SISTEM SI BONTOT SEHAT & AKTIF${NC}"
    echo "Dashboard dapat dibuka di: http://localhost:3001"
    exit 0
else
    echo -e "${RED}${BOLD}✖ HASIL KESEHATAN: TERDETEKSI GANGGUAN ($HEALTH_FAILED masalah kritis)${NC}"
    echo "Untuk memulai ulang layanan, jalankan: bash android/start-service.sh restart"
    echo "Periksa log rinci di                 : ~/wa-bontot/logs/server.log"
    exit 1
fi
