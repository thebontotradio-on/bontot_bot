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
# 0. Audit Binary & Versi llama-server
# ------------------------------------------------------------------------------
echo -e "${BOLD}[1/5] Memeriksa Eksekusi Binary & Versi llama-server...${NC}"
export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

test_binary_executable() {
    local bin_path="$1"
    [ -n "$bin_path" ] && [ -x "$bin_path" ] || return 1

    export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

    local test_out
    local exit_code=0
    test_out=$(env -u LD_PRELOAD "$bin_path" -h 2>&1) || exit_code=$?
    if [ -z "$test_out" ]; then
        test_out=$(env -u LD_PRELOAD "$bin_path" --help 2>&1) || exit_code=$?
    fi
    if [ -z "$test_out" ]; then
        test_out=$(env -u LD_PRELOAD "$bin_path" 2>&1 | head -n 25) || exit_code=$?
    fi

    # Deteksi kegagalan linker Bionic libc Android / ketidakcocokan arsitektur
    if echo "$test_out" | grep -qiE "CANNOT LINK|cannot locate symbol|bad ELF|Exec format|Illegal instruction|library \".*\" not found|No such file or directory"; then
        return 1
    fi

    # Jika binary menghasilkan banner atau help text (terlepas dari exit code nonzero) -> Valid
    if echo "$test_out" | grep -qiE "llama|usage|options|help|server|build|version|ggml"; then
        return 0
    fi

    if [ -n "$test_out" ] && [ "$exit_code" -le 2 ]; then
        return 0
    fi
    return 1
}

find_llama_server() {
    export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

    # 1. Cek dari paket dpkg llama-cpp / llama.cpp jika terpasang
    if command -v dpkg >/dev/null 2>&1; then
        for pkg_name in "llama-cpp" "llama.cpp" "llama-cpp-tools"; do
            if dpkg -s "$pkg_name" >/dev/null 2>&1; then
                local dpkg_bin
                dpkg_bin=$(dpkg -L "$pkg_name" 2>/dev/null | grep -E '/bin/llama-server$' | head -n 1 || true)
                if [ -n "$dpkg_bin" ] && [ -x "$dpkg_bin" ] && test_binary_executable "$dpkg_bin"; then
                    echo "$dpkg_bin"
                    return 0
                fi
                dpkg_bin=$(dpkg -L "$pkg_name" 2>/dev/null | grep -E '/bin/.*server' | head -n 1 || true)
                if [ -n "$dpkg_bin" ] && [ -x "$dpkg_bin" ] && test_binary_executable "$dpkg_bin"; then
                    echo "$dpkg_bin"
                    return 0
                fi
            fi
        done
    fi

    # 2. Cek lokasi standar
    for p in \
        "$PROJECT_DIR/bin/llama-server" \
        "$PREFIX/bin/llama-server" \
        "/data/data/com.termux/files/usr/bin/llama-server" \
        "$PREFIX/bin/llama.cpp-server" \
        "/data/data/com.termux/files/usr/bin/llama.cpp-server" \
        "$HOME/llama.cpp/build/bin/llama-server" \
        "$HOME/llama.cpp/llama-server"; do
        if [ -n "$p" ] && [ -x "$p" ] && test_binary_executable "$p"; then
            echo "$p"
            return 0
        fi
    done

    # 3. Cek command -v di PATH
    if command -v llama-server >/dev/null 2>&1; then
        local cmd_bin
        cmd_bin=$(command -v llama-server)
        if [ -x "$cmd_bin" ] && test_binary_executable "$cmd_bin"; then
            echo "$cmd_bin"
            return 0
        fi
    fi
    return 1
}

LLAMA_BIN=$(find_llama_server 2>/dev/null || echo "")
if [ -n "$LLAMA_BIN" ]; then
    VERSION_OUTPUT=$(env -u LD_PRELOAD "$LLAMA_BIN" -h 2>&1 | head -n 2 | tr '\n' ' ' || echo "llama-server ARM64")
    echo -e "  - Lokasi Binary : ${CYAN}$LLAMA_BIN${NC}"
    echo -e "  - Output Versi  : ${GREEN}$VERSION_OUTPUT${NC}"
else
    echo -e "  - Lokasi Binary : ${RED}TIDAK DITEMUKAN / TIDAK EXECUTABLE${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ------------------------------------------------------------------------------
# 1. Uji Status Engine Llama (Port 8080) dengan Polling Kesiapan Model
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[2/5] Menguji Kesiapan Llama Engine HTTP (Port 8080)...${NC}"
LLAMA_READY=0
POLL_RETRY=0
MAX_POLL=8

while [ "$POLL_RETRY" -lt "$MAX_POLL" ]; do
    POLL_RETRY=$((POLL_RETRY + 1))
    LLAMA_HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:8080/health 2>/dev/null || echo "000")
    LLAMA_HEALTH_BODY=$(curl -s --max-time 3 http://127.0.0.1:8080/health 2>/dev/null || echo "")

    if [ "$LLAMA_HEALTH_CODE" = "200" ]; then
        echo -e "  - Llama Engine /health: ${GREEN}HTTP 200 OK${NC} -> $LLAMA_HEALTH_BODY"
        LLAMA_READY=1
        break
    elif [ "$LLAMA_HEALTH_CODE" = "503" ]; then
        echo -e "  - Llama Engine /health: ${YELLOW}HTTP 503 (Model sedang dimuat ke RAM... coba lagi dalam 2 detik)${NC}"
        sleep 2
    else
        if [ "$POLL_RETRY" -eq 1 ]; then
            echo "  - Menunggu Llama Engine online di 127.0.0.1:8080..."
        fi
        sleep 2
    fi
done

if [ "$LLAMA_READY" -eq 0 ]; then
    echo -e "  - Llama Engine /health: ${RED}GAGAL (HTTP $LLAMA_HEALTH_CODE)${NC}"
    echo "    Penyebab: llama-server belum berjalan atau mengalami crash saat memuat model."
    echo "    --- Cuplikan Log Terakhir: $PROJECT_DIR/logs/llama.log ---"
    if [ -f "$PROJECT_DIR/logs/llama.log" ]; then
        tail -n 15 "$PROJECT_DIR/logs/llama.log"
    else
        echo "    (Berkas log llama.log belum ada)"
    fi
    echo "    --------------------------------------------------------"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ------------------------------------------------------------------------------
# 2. Uji Status AI Adapter (Port 11434)
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[3/5] Menguji AI Adapter Ollama Bridge (Port 11434)...${NC}"
TAGS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:11434/api/tags 2>/dev/null || echo "000")
TAGS_BODY=$(curl -s --max-time 3 http://127.0.0.1:11434/api/tags 2>/dev/null || echo "")

if [ "$TAGS_CODE" = "200" ] && echo "$TAGS_BODY" | grep -q '"name":'; then
    MODEL_ACTIVE=$(echo "$TAGS_BODY" | grep -o '"name":"[^"]*"' | head -n 1 | cut -d'"' -f4)
    echo -e "  - Adapter GET /api/tags: ${GREEN}HTTP 200 OK${NC} (Model aktif terdeteksi: ${CYAN}${MODEL_ACTIVE}${NC})"
else
    echo -e "  - Adapter GET /api/tags: ${RED}GAGAL atau Model Kosong (HTTP $TAGS_CODE)${NC}"
    echo "    Respons Payload: $TAGS_BODY"
    if [ -f "$PROJECT_DIR/logs/ai.log" ]; then
        echo "    --- Cuplikan Log Terakhir: $PROJECT_DIR/logs/ai.log ---"
        tail -n 10 "$PROJECT_DIR/logs/ai.log"
        echo "    -----------------------------------------------------"
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ------------------------------------------------------------------------------
# 3. Uji Inferensi Nyata Langsung Melalui AI Adapter (Port 11434)
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[4/5] Menguji Inferensi Teks via AI Adapter (Port 11434)...${NC}"
echo "Mengirim prompt: 'Halo! Siapa namamu?'..."

ADAPTER_CHAT_PAYLOAD='{"model":"qwen2.5:0.5b","messages":[{"role":"system","content":"Kamu adalah asisten ramah."},{"role":"user","content":"Halo! Siapa namamu?"}],"options":{"num_predict":30,"temperature":0.3}}'

T_START=$(date +%s)
CHAT_RESP=$(curl -s --max-time 45 -X POST http://127.0.0.1:11434/api/chat \
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
echo -e "${BOLD}[5/5] Menguji Draf AI Persona SI BONTOT via Backend (Port 3001)...${NC}"
echo "Mengirim pesan WhatsApp tiruan: 'Ngapain Bang Adhy?'..."

BACKEND_AI_PAYLOAD='{"message":"Ngapain Bang Adhy?"}'

BACKEND_RESP=$(curl -s --max-time 45 -X POST http://127.0.0.1:3001/api/ai-reply \
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
