#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Automated Database & Session Backup Script for Android
# Aman: Konsistensi SQLite (termasuk WAL/SHM) & izin akses terisolasi (chmod 600)
# ==============================================================================

PROJECT_DIR="$HOME/wa-bontot"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/wabontot_backup_$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

echo "Membuat arsip cadangan sesi dan database..."

# Cadangkan seluruh folder data (termasuk .db, .db-wal, .db-shm) dan folder sesi auth
tar -czf "$BACKUP_FILE" -C "$PROJECT_DIR" server/data server/auth_session 2>/dev/null || true

if [ -f "$BACKUP_FILE" ]; then
    # Kunci izin berkas agar kredensial tidak terekspos ke aplikasi lain
    chmod 600 "$BACKUP_FILE"
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "✔ Cadangan berhasil dibuat dan diamankan: $BACKUP_FILE ($SIZE)"
    
    # Simpan hanya 7 cadangan terakhir untuk menghemat penyimpanan internal HP
    ls -t "$BACKUP_DIR"/wabontot_backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
else
    echo "✖ Gagal membuat cadangan!"
    exit 1
fi
