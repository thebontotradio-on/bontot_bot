#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Robust Service Supervisor & Watchdog 24/7 untuk Android Termux
# Idempotent: Mencegah proses ganda, anti-stale PID, tahan SIGHUP & terminal close
# Command: bash start-service.sh [start|stop|status|restart] [--foreground]
# ==============================================================================

PROJECT_DIR="${PROJECT_DIR:-$HOME/wa-bontot}"
cd "$PROJECT_DIR" || exit 1

PID_DIR="$PROJECT_DIR/logs"
mkdir -p "$PID_DIR"

WATCHDOG_PID_FILE="$PID_DIR/watchdog.pid"
SERVER_PID_FILE="$PID_DIR/server.pid"
AI_PID_FILE="$PID_DIR/ai_adapter.pid"
LLAMA_PID_FILE="$PID_DIR/llama.pid"
LOG_FILE="$PROJECT_DIR/logs/server.log"
AI_LOG_FILE="$PROJECT_DIR/logs/ai.log"
MAX_LOG_SIZE=10485760 # 10 MB

# ------------------------------------------------------------------------------
# Helper: Deteksi & Pembersihan PID Basi (Anti-Stale Lock)
# ------------------------------------------------------------------------------
is_pid_alive() {
    local pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

check_and_clean_stale_pid() {
    local pid_file="$1"
    local proc_name="$2"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [ -n "$pid" ] && is_pid_alive "$pid"; then
            # Proses benar-benar aktif
            return 0
        else
            # PID file ada tapi proses sudah mati (stale lock)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PID] Membersihkan lock basi: $pid_file (PID $pid tidak lagi berjalan)." >> "$LOG_FILE"
            rm -f "$pid_file"
        fi
    fi
    return 1
}

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

find_model_file() {
    if [ -f "$PROJECT_DIR/models/qwen2.5-0.5b-instruct-q4_k_m.gguf" ]; then
        echo "$PROJECT_DIR/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
        return 0
    fi
    local found
    found=$(ls -S "$PROJECT_DIR/models/"*.gguf 2>/dev/null | head -n 1)
    if [ -n "$found" ] && [ -f "$found" ]; then
        echo "$found"
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# Sub-fungsi: Status Layanan
# ------------------------------------------------------------------------------
service_status() {
    echo "=== STATUS LAYANAN SI BONTOT ==="
    echo "Waktu: $(date)"
    echo "Lokasi: $PROJECT_DIR"
    echo ""

    # Watchdog
    if check_and_clean_stale_pid "$WATCHDOG_PID_FILE" "watchdog"; then
        echo -e "Watchdog Supervisor : \033[0;32mBERJALAN\033[0m (PID: $(cat "$WATCHDOG_PID_FILE"))"
    else
        echo -e "Watchdog Supervisor : \033[0;31mBERHENTI\033[0m"
    fi

    # Backend Node.js
    if check_and_clean_stale_pid "$SERVER_PID_FILE" "server"; then
        echo -e "Backend Server (3001) : \033[0;32mBERJALAN\033[0m (PID: $(cat "$SERVER_PID_FILE"))"
    else
        echo -e "Backend Server (3001) : \033[0;31mBERHENTI\033[0m"
    fi

    # AI Adapter
    if check_and_clean_stale_pid "$AI_PID_FILE" "ai_adapter"; then
        echo -e "AI Adapter (11434)  : \033[0;32mBERJALAN\033[0m (PID: $(cat "$AI_PID_FILE"))"
    else
        echo -e "AI Adapter (11434)  : \033[0;33mBERHENTI / SIAGA\033[0m"
    fi

    # Llama Server
    local llama_bin
    llama_bin=$(find_llama_server 2>/dev/null || echo "")
    local model_file
    model_file=$(find_model_file 2>/dev/null || echo "")

    if check_and_clean_stale_pid "$LLAMA_PID_FILE" "llama"; then
        echo -e "Llama Engine (8080) : \033[0;32mBERJALAN\033[0m (PID: $(cat "$LLAMA_PID_FILE"))"
    else
        if [ -n "$llama_bin" ] && [ -n "$model_file" ]; then
            echo -e "Llama Engine (8080) : \033[0;33mBERHENTI\033[0m (Binary & Model siap)"
        elif [ -n "$model_file" ]; then
            echo -e "Llama Engine (8080) : \033[0;33mOFFLINE\033[0m (Model GGUF di disk, binary belum terpasang -> jalankan bash android/setup-llama.sh)"
        else
            echo -e "Llama Engine (8080) : \033[0;31mOFFLINE\033[0m (Binary / Model belum ada)"
        fi
    fi

    echo ""
    echo "--- Pengujian Respons HTTP Nyata ---"
    local http_3001
    http_3001=$(curl -s --max-time 3 http://127.0.0.1:3001/api/status 2>/dev/null || echo "FAIL")
    if [ "$http_3001" != "FAIL" ]; then
        echo -e "HTTP 3001 (Backend API) : \033[0;32mONLINE (200 OK)\033[0m -> $http_3001"
    else
        echo -e "HTTP 3001 (Backend API) : \033[0;31mOFFLINE\033[0m"
    fi

    local http_11434
    http_11434=$(curl -s --max-time 3 http://127.0.0.1:11434/api/tags 2>/dev/null || echo "FAIL")
    if [ "$http_11434" != "FAIL" ]; then
        echo -e "HTTP 11434 (AI Tags)    : \033[0;32mONLINE (200 OK)\033[0m -> $http_11434"
    else
        echo -e "HTTP 11434 (AI Tags)    : \033[0;33mOFFLINE / SIAGA\033[0m"
    fi

    local http_8080
    http_8080=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:8080/health 2>/dev/null || echo "000")
    if [ "$http_8080" = "200" ]; then
        echo -e "HTTP 8080 (Llama Engine): \033[0;32mONLINE (200 OK - Siap Inferensi)\033[0m"
    elif [ "$http_8080" = "503" ]; then
        echo -e "HTTP 8080 (Llama Engine): \033[1;33mMEMUAT MODEL KE RAM (503 LOADING)\033[0m"
    else
        echo -e "HTTP 8080 (Llama Engine): \033[0;31mOFFLINE (HTTP $http_8080)\033[0m"
    fi
}

# ------------------------------------------------------------------------------
# Sub-fungsi: Helper Manajemen Engine Llama & Adapter
# ------------------------------------------------------------------------------
ensure_llama_server() {
    local LLAMA_BIN
    LLAMA_BIN=$(find_llama_server 2>/dev/null || true)
    local MODEL_FILE
    MODEL_FILE=$(find_model_file 2>/dev/null || true)

    if [ -n "$LLAMA_BIN" ] && [ -n "$MODEL_FILE" ] && [ -f "$MODEL_FILE" ]; then
        if ! check_and_clean_stale_pid "$LLAMA_PID_FILE" "llama"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LLAMA] Menjalankan llama-server lokal pada port 8080..." >> "$LOG_FILE"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LLAMA] Binary: $LLAMA_BIN | Model: $(basename "$MODEL_FILE") ($(du -h "$MODEL_FILE" 2>/dev/null | cut -f1))" >> "$LOG_FILE"
            export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"
            nohup env -u LD_PRELOAD LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}" \
                "$LLAMA_BIN" \
                -m "$MODEL_FILE" \
                --host 127.0.0.1 \
                --port 8080 \
                -c 2048 \
                -t 4 \
                >> "$PROJECT_DIR/logs/llama.log" 2>&1 &
            local LLAMA_PID=$!
            echo "$LLAMA_PID" > "$LLAMA_PID_FILE"
            disown "$LLAMA_PID" 2>/dev/null || true

            sleep 2
            if ! is_pid_alive "$LLAMA_PID"; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LLAMA ERROR] llama-server langsung mati setelah diluncurkan! Isi logs/llama.log:" >> "$LOG_FILE"
                tail -n 15 "$PROJECT_DIR/logs/llama.log" >> "$LOG_FILE" 2>/dev/null || true
                rm -f "$LLAMA_PID_FILE"
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LLAMA] llama-server aktif dengan PID $LLAMA_PID." >> "$LOG_FILE"
            fi
        fi
    else
        if [ -z "$LLAMA_BIN" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LLAMA] llama-server binary belum terpasang. Jalankan 'bash android/setup-llama.sh' untuk memasang." >> "$LOG_FILE"
        elif [ -z "$MODEL_FILE" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LLAMA] Berkas model GGUF belum ditemukan di models/. Jalankan 'bash android/download-ai-model.sh'." >> "$LOG_FILE"
        fi
    fi
}

ensure_ai_adapter() {
    if [ -f "$PROJECT_DIR/android/ai-adapter.js" ]; then
        if ! check_and_clean_stale_pid "$AI_PID_FILE" "ai_adapter"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ADAPTER] Menjalankan AI Adapter (Port 11434)..." >> "$LOG_FILE"
            nohup node "$PROJECT_DIR/android/ai-adapter.js" >> "$AI_LOG_FILE" 2>&1 &
            local AI_PID=$!
            echo "$AI_PID" > "$AI_PID_FILE"
            disown "$AI_PID" 2>/dev/null || true
        fi
    fi
}

# ------------------------------------------------------------------------------
# Sub-fungsi: Stop Layanan
# ------------------------------------------------------------------------------
service_stop() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SHUTDOWN] Menghentikan seluruh proses SI BONTOT..." >> "$LOG_FILE"
    echo "Menghentikan seluruh proses SI BONTOT..."

    # 1. Hentikan Watchdog terlebih dahulu agar tidak melakukan auto-restart
    if [ -f "$WATCHDOG_PID_FILE" ]; then
        local wpid
        wpid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
        if [ -n "$wpid" ] && is_pid_alive "$wpid"; then
            kill -TERM "$wpid" 2>/dev/null || true
        fi
        rm -f "$WATCHDOG_PID_FILE"
    fi

    # 2. Hentikan Server Node.js
    if [ -f "$SERVER_PID_FILE" ]; then
        local spid
        spid=$(cat "$SERVER_PID_FILE" 2>/dev/null)
        if [ -n "$spid" ] && is_pid_alive "$spid"; then
            kill -TERM "$spid" 2>/dev/null || true
            sleep 1
            if is_pid_alive "$spid"; then
                kill -KILL "$spid" 2>/dev/null || true
            fi
        fi
        rm -f "$SERVER_PID_FILE"
    fi

    # 3. Hentikan AI Adapter
    if [ -f "$AI_PID_FILE" ]; then
        local apid
        apid=$(cat "$AI_PID_FILE" 2>/dev/null)
        if [ -n "$apid" ] && is_pid_alive "$apid"; then
            kill -TERM "$apid" 2>/dev/null || true
            sleep 1
            if is_pid_alive "$apid"; then
                kill -KILL "$apid" 2>/dev/null || true
            fi
        fi
        rm -f "$AI_PID_FILE"
    fi

    # 4. Hentikan Llama Engine (jika ada)
    if [ -f "$LLAMA_PID_FILE" ]; then
        local lpid
        lpid=$(cat "$LLAMA_PID_FILE" 2>/dev/null)
        if [ -n "$lpid" ] && is_pid_alive "$lpid"; then
            kill -TERM "$lpid" 2>/dev/null || true
            sleep 1
            if is_pid_alive "$lpid"; then
                kill -KILL "$lpid" 2>/dev/null || true
            fi
        fi
        rm -f "$LLAMA_PID_FILE"
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SHUTDOWN] Seluruh proses SI BONTOT dihentikan bersih." >> "$LOG_FILE"
    echo "✔ Seluruh proses berhasil dihentikan."
}

# ------------------------------------------------------------------------------
# Supervisor Loop (Watchdog Inti)
# ------------------------------------------------------------------------------
run_supervisor() {
    # Abaikan SIGHUP agar terminal close / background tidak membunuh supervisor
    trap '' HUP SIGHUP

    # Simpan PID watchdog saat ini
    echo $$ > "$WATCHDOG_PID_FILE"

    local SHUTDOWN_TRIGGERED=0

    # Handler graceful shutdown hanya untuk SIGTERM dan SIGINT
    on_terminate() {
        local sig="$1"
        SHUTDOWN_TRIGGERED=1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WATCHDOG] Menerima sinyal $sig. Menutup child processes..." >> "$LOG_FILE"

        if [ -f "$SERVER_PID_FILE" ]; then
            local spid
            spid=$(cat "$SERVER_PID_FILE" 2>/dev/null)
            if [ -n "$spid" ] && is_pid_alive "$spid"; then
                kill -TERM "$spid" 2>/dev/null || true
            fi
            rm -f "$SERVER_PID_FILE"
        fi

        if [ -f "$AI_PID_FILE" ]; then
            local apid
            apid=$(cat "$AI_PID_FILE" 2>/dev/null)
            if [ -n "$apid" ] && is_pid_alive "$apid"; then
                kill -TERM "$apid" 2>/dev/null || true
            fi
            rm -f "$AI_PID_FILE"
        fi

        if [ -f "$LLAMA_PID_FILE" ]; then
            local lpid
            lpid=$(cat "$LLAMA_PID_FILE" 2>/dev/null)
            if [ -n "$lpid" ] && is_pid_alive "$lpid"; then
                kill -TERM "$lpid" 2>/dev/null || true
            fi
            rm -f "$LLAMA_PID_FILE"
        fi

        rm -f "$WATCHDOG_PID_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WATCHDOG] Selesai membersihkan proses. Keluar normal." >> "$LOG_FILE"
        exit 0
    }

    trap 'on_terminate SIGTERM' SIGTERM
    trap 'on_terminate SIGINT' SIGINT

    # 1. Pastikan Wake-Lock aktif tanpa memblokir
    termux-wake-lock < /dev/null 2>/dev/null || true

    # 2. Rotasi Log Server (Maksimal 10 MB per berkas)
    if [ -f "$LOG_FILE" ]; then
        local log_size
        log_size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$log_size" -gt "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "$PROJECT_DIR/logs/server_old_$(date +%Y%m%d_%H%M%S).log"
            ls -t "$PROJECT_DIR/logs/server_old_"*.log 2>/dev/null | tail -n +4 | xargs -r rm -f 2>/dev/null || true
        fi
    fi

    # 3. Jalankan Llama-server C++ (jika terpasang & model tersedia)
    ensure_llama_server

    # 4. Jalankan AI Engine Adapter (Port 11434) secara tunggal jika belum aktif
    ensure_ai_adapter

    # 5. Uji Kesiapan Sistem Sebelum Server Diluncurkan
    if [ -f "$PROJECT_DIR/android/check-readiness.sh" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [READINESS] Menjalankan pemeriksaan kesiapan sistem..." >> "$LOG_FILE"
        if ! bash "$PROJECT_DIR/android/check-readiness.sh" "$PROJECT_DIR" >> "$LOG_FILE" 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] Sistem tidak siap! Server tidak akan dimulai. Periksa logs/server.log" >> "$LOG_FILE"
            rm -f "$WATCHDOG_PID_FILE"
            exit 1
        fi
    fi

    # 6. Supervisor Loop: Menjaga Backend Node.js & Layanan AI tetap menyala 24/7
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STARTUP] Memulai SI BONTOT Watchdog Loop (PID: $$)..." >> "$LOG_FILE"

    local CRASH_COUNT=0
    local WINDOW_START
    WINDOW_START=$(date +%s)

    while [ "$SHUTDOWN_TRIGGERED" -eq 0 ]; do
        # 1. Pastikan Llama Engine (port 8080) hidup & otomatis pulih jika crash
        ensure_llama_server

        # 2. Pastikan AI Adapter (port 11434) hidup & otomatis pulih jika crash
        ensure_ai_adapter

        # 3. Pastikan Backend Server (port 3001) hidup & otomatis pulih jika crash
        if ! check_and_clean_stale_pid "$SERVER_PID_FILE" "server"; then
            local NOW
            NOW=$(date +%s)
            if [ $((NOW - WINDOW_START)) -lt 60 ]; then
                CRASH_COUNT=$((CRASH_COUNT + 1))
            else
                CRASH_COUNT=1
                WINDOW_START=$NOW
            fi

            if [ "$CRASH_COUNT" -ge 5 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CRITICAL] Server mengalami 5 crash dalam 60 detik. Menahan restart selama 30 detik demi stabilitas..." >> "$LOG_FILE"
                sleep 30
                CRASH_COUNT=0
                WINDOW_START=$(date +%s)
            fi

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUPERVISOR] Meluncurkan Node.js Server..." >> "$LOG_FILE"
            export NODE_ENV=production
            export PORT=3001
            nohup node server/index.js >> "$LOG_FILE" 2>&1 &
            local SERVER_PID=$!
            echo "$SERVER_PID" > "$SERVER_PID_FILE"
            disown "$SERVER_PID" 2>/dev/null || true
            sleep 2
        fi

        sleep 5
    done

    rm -f "$WATCHDOG_PID_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUPERVISOR] Supervisor loop selesai." >> "$LOG_FILE"
}

# ------------------------------------------------------------------------------
# Entrypoint Utama: Parsing Perintah CLI
# ------------------------------------------------------------------------------
COMMAND="${1:-start}"
MODE="${2:-}"

case "$COMMAND" in
    stop)
        service_stop
        exit 0
        ;;
    status)
        service_status
        exit 0
        ;;
    restart)
        service_stop
        sleep 2
        exec "$0" start
        ;;
    start)
        # Cek apakah watchdog sudah berjalan sebelumnya
        if check_and_clean_stale_pid "$WATCHDOG_PID_FILE" "watchdog"; then
            EXISTING_PID=$(cat "$WATCHDOG_PID_FILE")
            echo "ℹ Watchdog SI BONTOT sudah aktif dengan PID $EXISTING_PID. Tidak membuat proses ganda."
            echo "Untuk memeriksa status lengkap: bash android/start-service.sh status"
            exit 0
        fi

        # Bersihkan stale locks server & ai jika watchdog tidak aktif
        check_and_clean_stale_pid "$SERVER_PID_FILE" "server" || true
        check_and_clean_stale_pid "$AI_PID_FILE" "ai_adapter" || true
        check_and_clean_stale_pid "$LLAMA_PID_FILE" "llama" || true

        if [ "$MODE" = "--foreground" ]; then
            echo "Memulai SI BONTOT dalam mode foreground (tekan Ctrl+C untuk berhenti)..."
            run_supervisor
        else
            echo "Memulai SI BONTOT di latar belakang (daemon 24/7)..."
            # Jalankan supervisor di background dengan nohup agar terisolasi dari penutupan terminal
            nohup bash "$0" run-supervisor-internal >> "$LOG_FILE" 2>&1 &
            WATCHDOG_BG_PID=$!
            disown "$WATCHDOG_BG_PID" 2>/dev/null || true

            # Tunggu 3 detik untuk verifikasi startup awal
            sleep 3

            if is_pid_alive "$WATCHDOG_BG_PID"; then
                echo -e "\033[0;32m✔ SI BONTOT berhasil diluncurkan di latar belakang (PID: $WATCHDOG_BG_PID).\033[0m"
                echo "Dashboard : http://localhost:3001"
                echo "Log Server: $LOG_FILE"
                echo "Cek Status: bash android/start-service.sh status"
                echo "Stop Bot  : bash android/start-service.sh stop"
                exit 0
            else
                echo -e "\033[0;31m✖ Gagal meluncurkan SI BONTOT di latar belakang. Periksa $LOG_FILE\033[0m"
                exit 1
            fi
        fi
        ;;
    run-supervisor-internal)
        # Entrypoint internal yang dipanggil oleh nohup background runner
        run_supervisor
        ;;
    *)
        echo "Penggunaan: bash android/start-service.sh [start|stop|status|restart] [--foreground]"
        exit 1
        ;;
esac
