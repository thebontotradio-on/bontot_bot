#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Automated Database & Session Restore Script for Android
# Memulihkan database dan sesi auth dari arsip backup terbaru secara aman
# ==============================================================================

PROJECT_DIR="${1:-$HOME/wa-bontot}"
BACKUP_DIR="$PROJECT_DIR/backups"
BACKUP_FILE="$2"

cd "$PROJECT_DIR" || exit 1

# Jika berkas backup tidak ditentukan, ambil arsip terbaru
if [ -z "$BACKUP_FILE" ]; then
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/wabontot_backup_*.tar.gz 2>/dev/null | head -n 1)
fi

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
    echo "[GAGAL] Tidak ditemukan berkas cadangan di $BACKUP_DIR!"
    exit 1
fi

echo "=== MEMULIHKAN CADANGAN SI BONTOT ==="
echo "Arsip: $BACKUP_FILE"

# Hentikan server sebelum pemulihan agar SQLite tidak terkunci
WATCHDOG_PID_FILE="$PROJECT_DIR/logs/watchdog.pid"
if [ -f "$WATCHDOG_PID_FILE" ]; then
    WATCHDOG_PID=$(cat "$WATCHDOG_PID_FILE")
    echo "Menghentikan proses server aktif (PID $WATCHDOG_PID)..."
    kill "$WATCHDOG_PID" 2>/dev/null || true
    sleep 2
fi

# Ekstrak arsip
tar -xzf "$BACKUP_FILE" -C "$PROJECT_DIR"

# Kunci izin berkas
chmod 700 "$PROJECT_DIR/server/auth_session" "$PROJECT_DIR/server/data" 2>/dev/null || true
if [ -f "$PROJECT_DIR/server/data/wabontot.db" ]; then
    chmod 600 "$PROJECT_DIR/server/data/wabontot.db"
fi

echo "✔ Pemulihan selesai! Database dan sesi siap digunakan kembali."
exit 0
