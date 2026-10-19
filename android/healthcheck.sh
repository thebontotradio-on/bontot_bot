#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Android System & Bot Health Check
# ==============================================================================

echo "=== DIAGNOSTIK KESEHATAN SI BONTOT (ANDROID) ==="
echo "Waktu: $(date)"

# 1. Cek Uptime & Memori RAM
echo ""
echo "--- [1] Status Memori RAM & Uptime ---"
uptime
free -h 2>/dev/null || cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable"

# 2. Cek Suhu & Status Baterai (via Termux API jika terpasang)
echo ""
echo "--- [2] Status Daya & Baterai ---"
if command -v termux-battery-status >/dev/null 2>&1; then
    termux-battery-status
else
    echo "Paket termux-api belum aktif. Cek status baterai melalui menu Pengaturan HP."
fi

# 3. Cek Status Backend Node.js
echo ""
echo "--- [3] Status Server Backend (Port 3001) ---"
STATUS_RES=$(curl -s --max-time 3 http://127.0.0.1:3001/api/status || echo "OFFLINE")
if [ "$STATUS_RES" != "OFFLINE" ]; then
    echo "✔ Backend Aktif: $STATUS_RES"
else
    echo "✖ Backend Offline / Tidak Merespons!"
fi

# 4. Cek Status AI Service
echo ""
echo "--- [4] Status AI Service (Port 11434) ---"
AI_RES=$(curl -s --max-time 3 http://127.0.0.1:11434/api/tags || echo "OFFLINE")
if [ "$AI_RES" != "OFFLINE" ]; then
    echo "✔ AI Service Aktif: $AI_RES"
else
    echo "ℹ AI Service Offline atau belum dijalankan."
fi

# 5. Cek Ukuran Database & Sesi Auth
echo ""
echo "--- [5] Persistensi Storage ---"
if [ -d "$HOME/wa-bontot/server/auth_session" ]; then
    AUTH_COUNT=$(ls -1 "$HOME/wa-bontot/server/auth_session" 2>/dev/null | wc -l)
    echo "Jumlah berkas sesi auth: $AUTH_COUNT"
fi

if [ -f "$HOME/wa-bontot/server/data/wabontot.db" ]; then
    DB_SIZE=$(du -h "$HOME/wa-bontot/server/data/wabontot.db" | cut -f1)
    echo "Ukuran database SQLite: $DB_SIZE"
fi

echo ""
echo "=== SELESAI ==="
