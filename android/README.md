# PANDUAN DEPLOYMENT SI BONTOT — ANDROID TERMUX 24/7 (BIAYA Rp0)

Direktori ini berisi skrip otomasi portabel untuk menjalankan **SI BONTOT** secara mandiri pada smartphone Android cadangan (RAM 4 GB) tanpa laptop menyala, tanpa biaya, dan tanpa kartu kredit.

---

## 📁 Struktur Berkas `android/`

```text
android/
├── setup-termux.sh      # Skrip instalasi otomatis paket dasar Termux, Node.js, & build tools
├── start-service.sh     # Watchdog & daemon supervisor (auto-restart jika crash, rotasi log)
├── ai-adapter.js        # Adapter ultra-ringan Ollama API -> llama-server (OpenAI format)
├── backup-db.sh         # Skrip pencadangan otomatis harian database SQLite & sesi WhatsApp
├── healthcheck.sh       # Skrip diagnostik RAM, suhu baterai, status backend, dan AI
└── README.md            # Dokumentasi arsitektur dan panduan operasional
```

---

## ⚙️ Arsitektur Sistem Hemat Daya & RAM (< 800 MB Total)

1. **Backend & Frontend Tunggal (Single-Port Mode)**:
   - Backend Express berjalan di Port `3001`.
   - Frontend Vite dibangun sekali (`npm run build`) menjadi berkas statis di `client/dist`.
   - Express langsung menyajikan `client/dist` sehingga tidak perlu menjalankan Vite dev server di HP, menghemat **150–200 MB RAM**.
2. **Koneksi WhatsApp (Baileys)**:
   - Menggunakan penyimpanan sesi persisten di `server/auth_session/`.
   - Diberi izin akses `chmod 700` agar terisolasi dan aman di penyimpanan lokal Termux.
3. **Database SQLite (`better-sqlite3`)**:
   - Tersimpan di `server/data/wabontot.db` dengan backup berkala ke `backups/`.
4. **AI Engine Lokal Android (`llama-server`)**:
   - Menghindari Ollama desktop yang boros memori.
   - Menggunakan `llama-server` (C++ ARM64) yang memuat model terkuantisasi `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` (~398 MB).
   - Konsumsi RAM AI hanya **~500–600 MB**, meninggalkan sisa RAM **> 1,2 GB** untuk Android agar terhindar dari *Low Memory Killer (LMK)*.
5. **Cegah Tidur (Wake-Lock & Battery Optimization)**:
   - `termux-wake-lock` menahan CPU tetap aktif saat layar HP mati.
   - Pengaturan optimasi baterai Termux diubah ke *"Unrestricted / Tidak Dibatasi"*.
