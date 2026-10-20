#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Real HTTP Inference & AI Diagnostic Tester (Android Termux)
# Menguji inferensi model secara nyata melalui HTTP port 8080, 11434, dan 3001
# ==============================================================================

PROJECT_DIR="${1:-$HOME/wa-bontot}"
cd "$PROJECT_DIR" || exit 1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== UJI INFERENSI NYATA MODEL AI (ANDROID TERMUX) ===${NC}"
echo "Waktu    : $(date)"
echo "Direktori: $PROJECT_DIR"
echo ""

FAIL_COUNT=0

# ------------------------------------------------------------------------------
# 1. Uji Status Engine Llama (Port 8080)
# ------------------------------------------------------------------------------
echo -e "${BOLD}[1/4] Menguji Kesiapan Llama Engine (Port 8080)...${NC}"
LLAMA_HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:8080/health 2>/dev/null || echo "000")
LLAMA_HEALTH_BODY=$(curl -s --max-time 3 http://127.0.0.1:8080/health 2>/dev/null || echo "")

if [ "$LLAMA_HEALTH_CODE" = "200" ]; then
    echo -e "  - Llama Engine /health: ${GREEN}HTTP 200 OK${NC} -> $LLAMA_HEALTH_BODY"
else
    echo -e "  - Llama Engine /health: ${RED}GAGAL (HTTP $LLAMA_HEALTH_CODE)${NC}"
    echo "    Penyebab: llama-server belum berjalan atau masih memuat model."
    echo "    Periksa log di: $PROJECT_DIR/logs/llama.log"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ------------------------------------------------------------------------------
# 2. Uji Status AI Adapter (Port 11434)
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[2/4] Menguji AI Adapter Ollama Bridge (Port 11434)...${NC}"
TAGS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:11434/api/tags 2>/dev/null || echo "000")
TAGS_BODY=$(curl -s --max-time 3 http://127.0.0.1:11434/api/tags 2>/dev/null || echo "")

if [ "$TAGS_CODE" = "200" ] && echo "$TAGS_BODY" | grep -q '"name":'; then
    MODEL_ACTIVE=$(echo "$TAGS_BODY" | grep -o '"name":"[^"]*"' | head -n 1 | cut -d'"' -f4)
    echo -e "  - Adapter GET /api/tags: ${GREEN}HTTP 200 OK${NC} (Model aktif terdeteksi: ${CYAN}${MODEL_ACTIVE}${NC})"
else
    echo -e "  - Adapter GET /api/tags: ${RED}GAGAL atau Model Kosong${NC}"
    echo "    Respons Payload: $TAGS_BODY"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ------------------------------------------------------------------------------
# 3. Uji Inferensi Nyata Langsung Melalui AI Adapter (Port 11434)
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[3/4] Menguji Inferensi Teks via AI Adapter (Port 11434)...${NC}"
echo "Mengirim prompt: 'Halo! Siapa namamu?'..."

ADAPTER_CHAT_PAYLOAD='{"model":"qwen2.5:0.5b","messages":[{"role":"system","content":"Kamu adalah asisten ramah."},{"role":"user","content":"Halo! Siapa namamu?"}],"options":{"num_predict":30,"temperature":0.3}}'

T_START=$(date +%s)
CHAT_RESP=$(curl -s --max-time 30 -X POST http://127.0.0.1:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$ADAPTER_CHAT_PAYLOAD" 2>/dev/null || echo "FAIL")
T_END=$(date +%s)
T_ELAPSED=$((T_END - T_START))

ADAPTER_REPLY=""
if [ "$CHAT_RESP" != "FAIL" ] && echo "$CHAT_RESP" | grep -q '"content":'; then
    ADAPTER_REPLY=$(echo "$CHAT_RESP" | grep -o '"content":"[^"]*"' | head -n 1 | cut -d'"' -f4)
fi

if [ -n "$ADAPTER_REPLY" ]; then
    echo -e "  - Status Inferensi Adapter: ${GREEN}SUKSES (${T_ELAPSED} detik)${NC}"
    echo -e "  - Teks Hasil Generasi     : ${CYAN}\"$ADAPTER_REPLY\"${NC}"
else
    echo -e "  - Status Inferensi Adapter: ${RED}GAGAL${NC}"
    echo "    Respons Mentah: $CHAT_RESP"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ------------------------------------------------------------------------------
# 4. Uji Inferensi Nyata via Backend SI BONTOT (Port 3001)
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[4/4] Menguji Draf AI Persona SI BONTOT via Backend (Port 3001)...${NC}"
echo "Mengirim pesan WhatsApp tiruan: 'Ngapain Bang Adhy?'..."

BACKEND_AI_PAYLOAD='{"message":"Ngapain Bang Adhy?"}'

BACKEND_RESP=$(curl -s --max-time 30 -X POST http://127.0.0.1:3001/api/ai-reply \
    -H "Content-Type: application/json" \
    -d "$BACKEND_AI_PAYLOAD" 2>/dev/null || echo "FAIL")

BACKEND_REPLY=""
if [ "$BACKEND_RESP" != "FAIL" ] && echo "$BACKEND_RESP" | grep -q '"reply":'; then
    BACKEND_REPLY=$(echo "$BACKEND_RESP" | grep -o '"reply":"[^"]*"' | head -n 1 | cut -d'"' -f4)
fi

if [ -n "$BACKEND_REPLY" ]; then
    echo -e "  - Status Draf Backend     : ${GREEN}SUKSES${NC}"
    echo -e "  - Draf Balasan SI BONTOT  : ${CYAN}\"$BACKEND_REPLY\"${NC}"
else
    echo -e "  - Status Draf Backend     : ${RED}GAGAL${NC}"
    echo "    Respons Mentah: $BACKEND_RESP"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ------------------------------------------------------------------------------
# Ringkasan Akhir
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}--------------------------------------------------------${NC}"
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}🎉 SEMUA TAHAP LULUS! AI LOKAL TERBUKTI AKTIF & MENGHASILKAN TEKS NYATA! 🎉${NC}"
    echo "Dashboard status AI sekarang berstatus: AKTIF"
    echo "Akses dashboard di: http://localhost:3001"
    exit 0
else
    echo -e "${RED}${BOLD}❌ DITEMUKAN $FAIL_COUNT KEGAGALAN PADA UJI INFERENSI AI ❌${NC}"
    echo "Periksa log rinci di $PROJECT_DIR/logs/llama.log dan $PROJECT_DIR/logs/ai.log"
    exit 1
fi
