#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Service Supervisor & Watchdog 24/7 untuk Android Termux
# Idempotent: Mencegah proses ganda dengan PID lock & proteksi port
# ==============================================================================

PROJECT_DIR="$HOME/wa-bontot"
cd "$PROJECT_DIR" || exit 1

PID_DIR="$PROJECT_DIR/logs"
mkdir -p "$PID_DIR"
WATCHDOG_PID_FILE="$PID_DIR/watchdog.pid"
AI_PID_FILE="$PID_DIR/ai_adapter.pid"
LOG_FILE="$PROJECT_DIR/logs/server.log"
MAX_LOG_SIZE=10485760 # 10 MB

# 1. Cek apakah watchdog sudah berjalan sebelumnya
if [ -f "$WATCHDOG_PID_FILE" ]; then
    EXISTING_PID=$(cat "$WATCHDOG_PID_FILE")
    if kill -0 "$EXISTING_PID" 2>/dev/null; then
        echo "[$(date)] Watchdog SI BONTOT sudah aktif dengan PID $EXISTING_PID. Tidak membuat proses ganda." >> "$LOG_FILE"
        exit 0
    fi
fi

# Tulis PID watchdog saat ini
echo $$ > "$WATCHDOG_PID_FILE"

# Hapus PID lock saat script keluar
cleanup() {
    echo "[$(date)] Menghentikan watchdog SI BONTOT..." >> "$LOG_FILE"
    rm -f "$WATCHDOG_PID_FILE"
    if [ -f "$AI_PID_FILE" ]; then
        AI_PID=$(cat "$AI_PID_FILE")
        kill "$AI_PID" 2>/dev/null || true
        rm -f "$AI_PID_FILE"
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# 2. Pastikan Wake-Lock aktif
termux-wake-lock

# 3. Rotasi Log Server (Maksimal 10 MB per berkas)
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOG_FILE" "$PROJECT_DIR/logs/server_old_$(date +%Y%m%d_%H%M%S).log"
        # Simpan maksimal 3 log lama
        ls -t "$PROJECT_DIR/logs/server_old_"*.log 2>/dev/null | tail -n +4 | xargs -r rm -f
    fi
fi

# 4. Jalankan AI Engine Adapter (Port 11434) secara tunggal jika belum aktif
if [ -f "$PROJECT_DIR/android/ai-adapter.js" ]; then
    AI_RUNNING=0
    if [ -f "$AI_PID_FILE" ]; then
        EXISTING_AI_PID=$(cat "$AI_PID_FILE")
        if kill -0 "$EXISTING_AI_PID" 2>/dev/null; then
            AI_RUNNING=1
        fi
    fi
    
    if [ "$AI_RUNNING" -eq 0 ]; then
        echo "[$(date)] Menjalankan AI Adapter tunggal..." >> "$LOG_FILE"
        node "$PROJECT_DIR/android/ai-adapter.js" >> "$PROJECT_DIR/logs/ai.log" 2>&1 &
        echo $! > "$AI_PID_FILE"
    else
        echo "[$(date)] AI Adapter sudah aktif. Melewati peluncuran ganda." >> "$LOG_FILE"
    fi
fi

# 5. Uji Kesiapan Sistem Sebelum Server Diluncurkan
if [ -f "$PROJECT_DIR/android/check-readiness.sh" ]; then
    echo "[$(date)] Menjalankan pemeriksaan kesiapan sistem..." >> "$LOG_FILE"
    if ! bash "$PROJECT_DIR/android/check-readiness.sh" "$PROJECT_DIR" >> "$LOG_FILE" 2>&1; then
        echo "[$(date)] [FATAL] Sistem tidak siap! Server tidak akan dimulai. Periksa logs/server.log" >> "$LOG_FILE"
        exit 1
    fi
fi

# 6. Supervisor Loop: Menjaga Backend Node.js tetap menyala 24/7
echo "[$(date)] Memulai SI BONTOT Backend Watchdog (PID: $$)..." >> "$LOG_FILE"

while true; do
    echo "[$(date)] Meluncurkan Node.js Server..." >> "$LOG_FILE"
    
    export NODE_ENV=production
    export PORT=3001
    node server/index.js >> "$LOG_FILE" 2>&1
    
    EXIT_CODE=$?
    echo "[$(date)] Server berhenti dengan exit code: $EXIT_CODE. Melakukan restart dalam 5 detik..." >> "$LOG_FILE"
    sleep 5
done
