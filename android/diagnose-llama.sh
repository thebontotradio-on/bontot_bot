#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Standalone Llama Engine Deep Diagnostic Tool (Android Termux)
# Menghasilkan bukti konkret penyebab llama-server tidak bertahan hidup:
# 1. Isi aktual logs/llama.log & logs/service.log
# 2. Binary terpilih & seluruh pustaka .so di ~/wa-bontot/bin/
# 3. Uji eksekusi langsung di foreground untuk menangkap pesan linker/crash
# 4. Verifikasi berkas model GGUF & status port 8080/11434/3001
# ==============================================================================

PROJECT_DIR="${1:-$HOME/wa-bontot}"
cd "$PROJECT_DIR" || { echo "[ERROR] Direktori $PROJECT_DIR tidak ditemukan!"; exit 1; }

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "=================================================================="
echo "    🔍 SI BONTOT — DIAGNOSTIK MENDALAM LLAMA ENGINE (TERMUX) 🔍  "
echo "  Waktu: $(date '+%Y-%m-%d %H:%M:%S')                             "
echo "  Direktori: $PROJECT_DIR                                         "
echo "=================================================================="
echo -e "${NC}"

# ------------------------------------------------------------------------------
# 1. ISI AKTUAL logs/llama.log
# ------------------------------------------------------------------------------
echo -e "${BOLD}[BUKTI 1] Isi Aktual logs/llama.log:${NC}"
if [ -f "$PROJECT_DIR/logs/llama.log" ]; then
    LOG_SIZE=$(wc -c < "$PROJECT_DIR/logs/llama.log" 2>/dev/null || echo 0)
    echo "  (Ukuran berkas log: $LOG_SIZE byte)"
    if [ "$LOG_SIZE" -gt 0 ]; then
        echo -e "${YELLOW}--- AWAL CUPLIKAN LOG LLAMA (Maks 40 Baris Terakhir) ---${NC}"
        tail -n 40 "$PROJECT_DIR/logs/llama.log"
        echo -e "${YELLOW}--- AKHIR CUPLIKAN LOG LLAMA ---${NC}"
    else
        echo -e "  ${RED}logs/llama.log KOSONG (0 byte). Binary tidak sempat menulis output atau mati sebelum stdout di-flush.${NC}"
    fi
else
    echo -e "  ${RED}Berkas logs/llama.log TIDAK DITEMUKAN.${NC}"
fi

# ------------------------------------------------------------------------------
# 2. ISI logs/service.log TERKAIT [LLAMA]
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[BUKTI 2] Riwayat Supervisor di logs/service.log (Tag LLAMA):${NC}"
if [ -f "$PROJECT_DIR/logs/service.log" ]; then
    grep -E "LLAMA" "$PROJECT_DIR/logs/service.log" | tail -n 15 || echo "  (Tidak ada entri LLAMA dalam service.log)"
else
    echo "  (Berkas logs/service.log tidak ditemukan)"
fi

# ------------------------------------------------------------------------------
# 3. AUDIT DIREKTORI bin/ DAN PUSTAKA .so
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[BUKTI 3] Daftar Berkas di $PROJECT_DIR/bin/:${NC}"
if [ -d "$PROJECT_DIR/bin" ]; then
    ls -lah "$PROJECT_DIR/bin"
    SO_COUNT=$(find "$PROJECT_DIR/bin" -name "*.so*" 2>/dev/null | wc -l)
    echo "  -> Total library .so ditemukan di bin/: $SO_COUNT file"
else
    echo -e "  ${RED}Direktori bin/ tidak ada!${NC}"
fi

# ------------------------------------------------------------------------------
# 4. AUDIT PAKET SISTEM TERKAIT LLAMA DI DPKG
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[BUKTI 4] Status Paket llama di Database dpkg Termux:${NC}"
if command -v dpkg >/dev/null 2>&1; then
    dpkg -l | grep -E "llama|tur-repo" || echo "  (Tidak ada paket 'llama' terdaftar di dpkg)"
else
    echo "  (dpkg tidak tersedia)"
fi

# ------------------------------------------------------------------------------
# 5. DETEKSI BINARY TERPILIH OLEH SISTEM
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[BUKTI 5] Lokasi Binary llama-server yang Terdeteksi:${NC}"

export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

FOUND_BIN=""
for p in \
    "$PROJECT_DIR/bin/llama-server" \
    "$PREFIX/bin/llama-server" \
    "/data/data/com.termux/files/usr/bin/llama-server" \
    "$PREFIX/bin/llama.cpp-server" \
    "$HOME/llama.cpp/build/bin/llama-server" \
    "$HOME/llama.cpp/llama-server"; do
    if [ -f "$p" ]; then
        FOUND_BIN="$p"
        echo -e "  - Kandidat Ditemukan: ${CYAN}$p${NC} (Executable: $([ -x "$p" ] && echo "YA" || echo "TIDAK"))"
        break
    fi
done

if [ -z "$FOUND_BIN" ]; then
    if command -v llama-server >/dev/null 2>&1; then
        FOUND_BIN=$(command -v llama-server)
        echo -e "  - Dari PATH: ${CYAN}$FOUND_BIN${NC}"
    fi
fi

if [ -n "$FOUND_BIN" ]; then
    echo "  - File Info:"
    ls -l "$FOUND_BIN"
    
    # Audit dependensi pustaka via readelf jika ada
    if command -v readelf >/dev/null 2>&1; then
        echo "  - Dynamic Linker Dependencies (readelf -d NEEDED):"
        readelf -d "$FOUND_BIN" 2>/dev/null | grep NEEDED | sed 's/^/    /' || true
    fi

    # Uji eksekusi banner help
    echo "  - Uji Eksekusi (-h) dengan 'env -u LD_PRELOAD':"
    HELP_OUT=$(env -u LD_PRELOAD LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}" "$FOUND_BIN" -h 2>&1 | head -n 10)
    HELP_CODE=$?
    echo "    Exit Code: $HELP_CODE"
    echo "    Output Cuplikan:"
    echo "$HELP_OUT" | sed 's/^/      /'
else
    echo -e "  ${RED}TIDAK ADA binary llama-server yang ditemukan di lokasi mana pun!${NC}"
fi

# ------------------------------------------------------------------------------
# 6. AUDIT BERKAS MODEL GGUF
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[BUKTI 6] Berkas Model AI di $PROJECT_DIR/models/:${NC}"
if [ -d "$PROJECT_DIR/models" ]; then
    ls -lah "$PROJECT_DIR/models"
    MODEL_FILE=$(ls -S "$PROJECT_DIR/models/"*.gguf 2>/dev/null | head -n 1 || true)
    if [ -n "$MODEL_FILE" ] && [ -f "$MODEL_FILE" ]; then
        echo -e "  -> Model terpilih: ${GREEN}$MODEL_FILE${NC}"
    else
        echo -e "  ${RED}-> Tidak ada berkas .gguf di $PROJECT_DIR/models/${NC}"
    fi
else
    echo -e "  ${RED}Folder models/ belum ada.${NC}"
fi

# ------------------------------------------------------------------------------
# 7. UJI EKSEKUSI LANGSUNG FOREGROUND (REAL-TIME CRASH CAPTURE)
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[BUKTI 7] Uji Eksekusi Langsung di Foreground (Melihat Error Real-Time):${NC}"
if [ -n "$FOUND_BIN" ] && [ -x "$FOUND_BIN" ] && [ -n "$MODEL_FILE" ] && [ -f "$MODEL_FILE" ]; then
    echo "Menjalankan: env -u LD_PRELOAD $FOUND_BIN -m $MODEL_FILE --host 127.0.0.1 --port 8080 -c 2048 -t 4"
    echo "Menangkap keluaran selama 4 detik..."
    echo "--------------------------------------------------------"
    
    # Jalankan langsung dan tangkap outputnya
    FOREGROUND_OUT=$(env -u LD_PRELOAD LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}" \
        "$FOUND_BIN" \
        -m "$MODEL_FILE" \
        --host 127.0.0.1 \
        --port 8080 \
        -c 2048 \
        -t 4 2>&1 &
        TEST_PID=$!
        sleep 4
        if kill -0 "$TEST_PID" 2>/dev/null; then
            echo "[SUKSES] llama-server BERHASIL HIDUP dan bertahan di memori! (PID: $TEST_PID)"
            kill "$TEST_PID" 2>/dev/null || true
        else
            wait "$TEST_PID" 2>/dev/null
            EXIT_CODE=$?
            echo "[CRASH / MATI] Process langsung keluar dengan Exit Code: $EXIT_CODE"
        fi
    )
    echo "$FOREGROUND_OUT"
    echo "--------------------------------------------------------"
else
    echo "Uji foreground dilewati karena binary atau model tidak siap."
fi

# ------------------------------------------------------------------------------
# 8. STATUS PORT JARINGAN AKTUAL
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}[BUKTI 8] Status Port Jaringan:${NC}"
for p in 8080 11434 3001; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "http://127.0.0.1:$p/" 2>/dev/null || echo "OFFLINE")
    echo "  - Port $p: $CODE"
done

echo ""
echo -e "${CYAN}${BOLD}=================================================================="
echo "          SELESAI — SALIN KELUARAN DI ATAS UNTUK ANALISIS        "
echo "==================================================================${NC}"
