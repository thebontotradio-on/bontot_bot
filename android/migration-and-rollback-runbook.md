# RUNBOOK MIGRASI & ROLLBACK SI BONTOT (ANDROID <-> LAPTOP)

Panduan operasional mitigasi risiko, perpindahan sesi WhatsApp, dan pemulihan darurat tanpa kehilangan data.

---

## 1. Prinsip Utama & Batasan Arsitektur

1. **Baileys Anti-Collision**:
   WhatsApp Web Protocol (Baileys) **TIDAK MENGIZINKAN** dua proses aktif menggunakan satu sesi kredensial (`auth_session`) secara bersamaan. Jika laptop dan Android berjalan dengan folder sesi yang sama, WhatsApp akan memutus salah satu koneksi atau memblokir sementara karena konflik *session sync keys*.
2. **Karakteristik Database SQLite Lokal**:
   File `server/data/wabontot.db` bersifat lokal. Pesan yang masuk dan dibalas oleh Android **TIDAK otomatis muncul** di laptop kecuali database disinkronkan secara fisik via backup.

---

## 2. Dua Skenario Migrasi

### Skenario A: Tautan Perangkat Baru via QR Code (Direkomendasikan)
- **Tujuan**: Memulai SI BONTOT di Android sebagai perangkat tertaut mandiri tanpa menyentuh data sesi di laptop.
- **Prosedur**:
  1. Pastikan server laptop dimatikan (`Ctrl + C` di terminal laptop).
  2. Mulai server di Android (`bash android/start-service.sh`).
  3. Buka dashboard Android di browser laptop: `http://<IP_HP_ANDROID>:3001`.
  4. Buka WhatsApp di HP Utama -> **Perangkat Tertaut** -> **Tautkan Perangkat** -> Pindai QR code di dashboard.
  5. Sesi di laptop tetap utuh sebagai cadangan arsip.

### Skenario B: Memindahkan Sesi Eksisting & Riwayat Database Lengkap
- **Tujuan**: Membawa seluruh riwayat pesan, kontak, dan sesi WhatsApp aktif dari laptop ke Android.
- **Prosedur**:
  1. Matikan total server di laptop (`Ctrl + C`).
  2. Buat arsip cadangan di laptop dari folder `server/data` dan `server/auth_session`.
  3. Salin berkas arsip ke HP Android ke lokasi `~/wa-bontot/`.
  4. Ekstrak arsip di Android dengan hak akses `chmod 700`.
  5. Jalankan server di Android.
  6. **PERINGATAN**: Jangan pernah menyalakan server di laptop selama Android masih aktif!

---

## 3. Prosedur Rollback Instan (Jika Android Mengalami Kendala)

Jika HP Android mengalami kehabisan baterai, panas berlebih, atau Termux terhenti:

1. **Langkah 1 (Hentikan Android)**:
   - Tarik notifikasi Termux di layar HP Android -> Pilih **Exit** atau buka aplikasi Termux ketik `exit`.
2. **Langkah 2 (Nyalakan Kembali di Laptop)**:
   - Buka PowerShell di laptop pada folder `C:\Projects\WA BONTOT`.
   - Jalankan `npm run dev`.
3. **Langkah 3 (Verifikasi)**:
   - Buka `http://localhost:3000`.
   - Status WhatsApp akan langsung kembali **Terhubung** dalam waktu < 10 detik.
   - Selesai. Seluruh kontrol kembali ke laptop tanpa ada data yang hilang.

---

## 4. Cara Sinkronisasi Balik Data dari Android ke Laptop

Jika bot telah berjalan beberapa hari di Android dan ingin memindahkan database terbaru kembali ke laptop:
1. Jalankan `bash android/backup-db.sh` di Android.
2. Salin berkas `~/wa-bontot/backups/wabontot_backup_*.tar.gz` ke laptop.
3. Ekstrak dan timpa folder `server/data/wabontot.db` di laptop.
