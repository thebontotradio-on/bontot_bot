#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — 24-Hour Android Endurance & Thermal Benchmark Harness
# ==============================================================================

PROJECT_DIR="$HOME/wa-bontot"
LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

CSV_LOG="$LOG_DIR/endurance_benchmark.csv"
SUMMARY_LOG="$LOG_DIR/endurance_summary.log"

echo "timestamp,uptime_sec,backend_status,ai_status,free_mem_mb,battery_temp_c,battery_level" > "$CSV_LOG"
echo "=== MEMULAI BENCHMARK KETAHANAN SI BONTOT (TARGET: 24 JAM) ===" > "$SUMMARY_LOG"
echo "Mulai: $(date)" >> "$SUMMARY_LOG"

TEST_DURATION_HOURS=24
TOTAL_SECONDS=$((TEST_DURATION_HOURS * 3600))
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ "$ELAPSED" -ge "$TOTAL_SECONDS" ]; then
        echo "=== PENGUJIAN 24 JAM SELESAI PADA $(date) ===" >> "$SUMMARY_LOG"
        break
    fi

    # 1. Cek status Backend Node.js
    BACKEND_STATUS="DOWN"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:3001/api/status || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        BACKEND_STATUS="OK"
    fi

    # 2. Cek status AI Engine
    AI_STATUS="DOWN"
    AI_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:11434/api/tags || echo "000")
    if [ "$AI_CODE" = "200" ]; then
        AI_STATUS="OK"
    fi

    # 3. Catat Memori Bebas
    FREE_MEM=$(free -m 2>/dev/null | awk '/Mem:/ {print $7}' || cat /proc/meminfo | awk '/MemAvailable/ {print int($2/1024)}')

    # 4. Catat Suhu & Baterai
    BATT_TEMP="N/A"
    BATT_LEVEL="N/A"
    if command -v termux-battery-status >/dev/null 2>&1; then
        BATT_JSON=$(termux-battery-status 2>/dev/null || echo "{}")
        BATT_TEMP=$(echo "$BATT_JSON" | grep -o '"temperature":[^,]*' | cut -d: -f2 | tr -d ' ' || echo "N/A")
        BATT_LEVEL=$(echo "$BATT_JSON" | grep -o '"percentage":[^,]*' | cut -d: -f2 | tr -d ' ' || echo "N/A")
    fi

    # Catat ke CSV
    TIMESTAMP_NOW=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$TIMESTAMP_NOW,$ELAPSED,$BACKEND_STATUS,$AI_STATUS,$FREE_MEM,$BATT_TEMP,$BATT_LEVEL" >> "$CSV_LOG"

    # Evaluasi Anomali
    if [ "$BACKEND_STATUS" != "OK" ]; then
        echo "[ALERT $(date)] Backend Port 3001 TIDAK MERESPONS! (Elapsed: ${ELAPSED}s)" >> "$SUMMARY_LOG"
    fi
    if [ "$AI_STATUS" != "OK" ]; then
        echo "[ALERT $(date)] AI Service Port 11434 TIDAK MERESPONS! (Elapsed: ${ELAPSED}s)" >> "$SUMMARY_LOG"
    fi

    sleep 60
done
