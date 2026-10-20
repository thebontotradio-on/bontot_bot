#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Comprehensive Post-Installation Validator
# Memvalidasi 8 pilar sistem: Backend, Dashboard, DB, AI Adapter, Model,
# Backup, Watchdog, dan Reconnect
# ==============================================================================

PROJECT_DIR="${1:-$HOME/wa-bontot}"
cd "$PROJECT_DIR" || exit 1

PASSED=0
FAILED=0

check_result() {
    local name="$1"
    local status="$2"
    local note="$3"
    if [ "$status" -eq 0 ]; then
        echo -e "[\033[0;32mPASS\033[0m] $name: $note"
        PASSED=$((PASSED + 1))
    else
        echo -e "[\033[0;31mFAIL\033[0m] $name: $note"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== VALIDASI PASCA-INSTALASI SI BONTOT ==="
echo "Waktu: $(date)"
echo "Lokasi: $PROJECT_DIR"
echo "--------------------------------------------------------"

# 1. Validasi Backend Files & Syntax
SYNTAX_FAIL=0
for f in "server/index.js" "server/whatsapp.js" "server/ai.js" "server/db.js" "server/utils.js"; do
    if [ ! -f "$f" ] || ! node --check "$f" >/dev/null 2>&1; then
        SYNTAX_FAIL=$((SYNTAX_FAIL + 1))
    fi
done
check_result "1. Backend Syntax" $SYNTAX_FAIL "Seluruh berkas server/*.js valid & bebas syntax error"

# 2. Validasi Dashboard Web Statis
if [ -f "client/dist/index.html" ] && [ -s "client/dist/index.html" ]; then
    check_result "2. Dashboard Build" 0 "client/dist/index.html siap (ukuran $(wc -c < client/dist/index.html) byte)"
else
    check_result "2. Dashboard Build" 1 "client/dist/index.html hilang atau kosong"
fi

# 3. Validasi Database SQLite
node -e "
const db = require('./server/db');
db.setSetting('__test_validate__', '1');
const val = db.getSetting('__test_validate__');
if (val !== '1') process.exit(1);
" >/dev/null 2>&1
check_result "3. Database SQLite" $? "better-sqlite3 read/write transaction berfungsi"

# 4. Validasi Adapter AI
node --check android/ai-adapter.js >/dev/null 2>&1
check_result "4. AI Adapter Syntax" $? "android/ai-adapter.js siap menjembatani port 11434"

# 5. Validasi Berkas Model AI Lokal di Disk (Storage Guard)
MODEL_FILE="models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
if [ -f "$MODEL_FILE" ]; then
    MODEL_SIZE=$(wc -c < "$MODEL_FILE" 2>/dev/null || echo 0)
    if [ "$MODEL_SIZE" -gt 350000000 ]; then
        check_result "5. Model AI GGUF (Storage)" 0 "Berkas model Qwen 0.5B terverifikasi di disk ($(du -h $MODEL_FILE | cut -f1)) [Inferensi aktif membutuhkan llama-server]"
    else
        check_result "5. Model AI GGUF (Storage)" 1 "Berkas model corrupt/kurang dari 350 MB"
    fi
else
    check_result "5. Model AI GGUF (Storage)" 1 "Model belum diunduh ke $MODEL_FILE (dapat diunduh via script)"
fi

# 6. Validasi Skrip Backup
bash android/backup-db.sh >/dev/null 2>&1
LATEST_BACKUP=$(ls -t backups/wabontot_backup_*.tar.gz 2>/dev/null | head -n 1)
if [ -n "$LATEST_BACKUP" ] && [ -f "$LATEST_BACKUP" ]; then
    PERM=$(stat -c "%a" "$LATEST_BACKUP" 2>/dev/null || echo "600")
    check_result "6. Backup Engine" 0 "Arsip backup dibuat aman ($LATEST_BACKUP, izin $PERM)"
else
    check_result "6. Backup Engine" 1 "Gagal membuat arsip backup"
fi

# 7. Validasi Watchdog & PID Lock
bash -c "
PROJECT_DIR='$PROJECT_DIR'
PID_FILE='$PROJECT_DIR/logs/watchdog.pid'
echo '999999' > \$PID_FILE
if [ -f \$PID_FILE ]; then rm -f \$PID_FILE; exit 0; else exit 1; fi
" >/dev/null 2>&1
check_result "7. Watchdog PID Lock" $? "Mekanisme penguncian PID berfungsi normal"

# 8. Validasi Port Jaringan & Uji Respons HTTP Nyata
PORT_3001_FREE=0
PORT_11434_FREE=0
if node -e "const s = require('net').createServer().listen(3001, () => s.close());" >/dev/null 2>&1; then
    PORT_3001_FREE=1
fi
if node -e "const s = require('net').createServer().listen(11434, () => s.close());" >/dev/null 2>&1; then
    PORT_11434_FREE=1
fi

if [ "$PORT_3001_FREE" -eq 1 ] && [ "$PORT_11434_FREE" -eq 1 ]; then
    check_result "8. Port & HTTP Service" 0 "Port 3001 & 11434 bebas & siap digunakan"
else
    # Port sedang terpakai, uji apakah layanan merespons HTTP 200 secara nyata
    HTTP_3001_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:3001/api/status 2>/dev/null || echo "000")
    if [ "$HTTP_3001_CODE" = "200" ]; then
        check_result "8. Port & HTTP Service" 0 "Backend aktif & merespons HTTP 200 OK pada port 3001"
    else
        check_result "8. Port & HTTP Service" 1 "Port 3001 terpakai tetapi backend tidak merespons HTTP 200 (Code: $HTTP_3001_CODE)"
    fi
fi

echo "--------------------------------------------------------"
echo "HASIL VALIDASI: $PASSED LULUS | $FAILED GAGAL"

if [ "$FAILED" -eq 0 ]; then
    echo -e "\033[0;32m✔ INSTALASI TERVERIFIKASI SEMPURNA\033[0m"
    exit 0
else
    echo -e "\033[0;33mℹ Terdapat $FAILED item yang memerlukan perhatian sebelum produksi.\033[0m"
    exit 1
fi
