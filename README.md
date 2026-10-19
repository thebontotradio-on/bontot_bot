# WA BONTOT — Dashboard WhatsApp & Asisten AI Lokal

WA BONTOT adalah aplikasi desktop-friendly berbasis web untuk mengelola percakapan WhatsApp pribadi dengan bantuan asisten AI lokal (Ollama) yang 100% gratis tanpa API key berbayar. Dilengkapi fitur **SI BONTOT Auto-Reply** untuk membalas pesan otomatis dengan karakter ramah dan cerdas dari **THE BONTOT RADIO**.

---

## 🌟 Fitur Utama

- **Koneksi WhatsApp Baileys Stabil**:
  - Scan QR Code langsung dari dashboard web.
  - Sesi tersimpan aman di folder `server/auth_session/` sehingga tidak perlu scan ulang setiap restart normal.
  - Siklus koneksi aman (mencegah double timer reconnect, socket leak, dan event stale).
- **Manajemen Chat & Pesan Realtime**:
  - Sidebar daftar chat dengan badge pesan belum dibaca (*unread count*).
  - Pencarian kontak atau isi pesan secara instan.
  - Membaca riwayat percakapan dengan auto-scroll dan pembaruan realtime via Socket.IO.
  - Optimistic UI saat mengirim pesan dengan status centang (*sending*, *delivered*, *sent*).
  - Pengiriman pesan manual dengan deduplikasi pesan dan keamanan format nomor (tidak merusak JID `@lid`, `@g.us`, dll).
  - Proteksi nama kontak: nama valid (seperti `Adhy`) tidak akan pernah tertimpa oleh fallback atau nomor mentah.
- **SI BONTOT Auto-Reply (Fitur Baru)**:
  - Toggle ON/OFF di header dashboard (Default wajib **OFF** pada startup & restart).
  - Membalas pesan masuk baru secara otomatis menggunakan Ollama AI lokal.
  - Persona resmi: **SI BONTOT, asisten WhatsApp milik THE BONTOT RADIO** (bahasa santai, akrab, cerdas, tidak mengaku sebagai manusia).
  - Membaca konteks percakapan beberapa pesan terakhir agar jawaban relevan dan nyambung.
  - **Mekanisme Anti-Loop & Anti-Spam**:
    - Atomic database lock pada tabel `auto_reply_logs` (pesan yang sama tidak pernah dibalas 2 kali).
    - Cooldown jeda minimum per chat untuk mencegah banjir balasan (*burst spam*).
    - Tidak membalas pesan dari akun sendiri (`fromMe`).
    - Tidak membalas pesan grup (`@g.us`) secara default (fokus pada chat pribadi).
    - Respons AI kosong tidak akan pernah dikirimkan.
- **Asisten Draf AI Manual**:
  - Tombol **"Buat Draf AI"** di sebelah kolom input chat untuk membuat draf jawaban tanpa mengirim langsung.
- **Pengaturan Karakter & System Prompt AI**:
  - Modal pengaturan dengan tombol ikon gear di header.
  - System prompt disimpan secara lokal di tabel SQLite (`settings`).

---

## 🛠️ Struktur Project

```text
C:\Projects\WA BONTOT\
├── server/
│   ├── index.js          # Express server, Socket.IO, dan API routes (termasuk /api/auto-reply/*)
│   ├── whatsapp.js       # Baileys manager, socket handler, dan orkestrator SI BONTOT Auto-Reply
│   ├── db.js             # SQLite Database (better-sqlite3), foreign keys, dan tabel auto_reply_logs
│   ├── ai.js             # Integrasi Ollama lokal, contextual thread reply, dan persona SI BONTOT
│   ├── utils.js          # Deduplikasi pesan, sanitasi JID & placeholder
│   ├── auth_session/     # Kredensial autentikasi WhatsApp (dilindungi .gitignore)
│   └── data/             # Database SQLite wabontot.db
├── client/
│   ├── src/
│   │   ├── components/   # Header (dengan Auto-Reply toggle), Sidebar, ChatArea, QrScreen, AiSettingsModal
│   │   ├── services/     # Axios API service
│   │   ├── App.jsx       # State orchestration & realtime Socket.IO
│   │   ├── index.css     # Tailwind CSS v4 styling
│   │   └── main.jsx
│   ├── vite.config.js    # Port 3000, strictPort: true
│   ├── postcss.config.js # @tailwindcss/postcss
│   └── .env.local        # VITE_API_BASE_URL=http://localhost:3001
├── test/                 # Pengujian unit (33 test lulus 100%)
├── package.json          # Root scripts & orchestrator
├── README.md             # Panduan lengkap
└── .gitignore            # Proteksi sesi auth, DB, dan env
```

---

## 🚀 Cara Menjalankan Aplikasi

Pastikan Node.js (v18+) sudah terinstal di komputer.

### 1. Menjalankan Backend & Frontend Bersamaan (Recommended)

Dari root project (`C:\Projects\WA BONTOT`):

```bash
npm run dev
```

- Backend berjalan di: `http://localhost:3001`
- Frontend berjalan di: `http://localhost:3000`

### 2. Menjalankan Secara Terpisah

**Backend saja:**
```bash
npm run server
```

**Frontend saja:**
```bash
npm run client
```

### 3. Menjalankan Seluruh Unit Test (33 Test)
```bash
npm test
```

---

## 🤖 Cara Memasang & Menjalankan AI Lokal (Ollama)

Aplikasi WhatsApp tetap berfungsi normal tanpa AI. Untuk mengaktifkan fitur **SI BONTOT Auto-Reply** dan **Buat Draf AI**:

### 1. Unduh dan Instal Ollama
Kunjungi situs resmi [https://ollama.com](https://ollama.com) dan unduh installer untuk Windows.

### 2. Pilih & Jalankan Model Sesuai Kapasitas RAM Komputer

Buka **PowerShell** atau **Command Prompt**, lalu ketik salah satu perintah:

- **Laptop / PC dengan RAM 4GB - 8GB (Sangat Ringan & Cepat):**
  ```bash
  ollama run qwen2.5:1.5b
  ```
  *atau*
  ```bash
  ollama run llama3.2:1b
  ```

- **Laptop / PC dengan RAM 8GB - 16GB (Kualitas Bahasa Tinggi):**
  ```bash
  ollama run llama3.2
  ```

Setelah model selesai diunduh, status Ollama di header WA BONTOT akan otomatis berubah menjadi hijau (**AI Siap**).

---

## 📻 Menggunakan Fitur SI BONTOT Auto-Reply

1. Buka dashboard web di `http://localhost:3000`.
2. Pastikan WhatsApp dalam kondisi **Terhubung**.
3. Pastikan Ollama berstatus **AI Siap**.
4. Klik tombol toggle **Auto-Reply** di header untuk mengubah status dari **OFF** menjadi **ON**.
5. Saat ada pesan masuk baru dari kontak pribadi, SI BONTOT akan membaca konteks percakapan dan membalas otomatis atas nama **THE BONTOT RADIO**.
6. Indikator *"SI BONTOT membalas..."* akan muncul di header saat AI sedang menyusun balasan.
7. Untuk mematikan, klik tombol toggle kembali ke status **OFF**.
8. **Keamanan**: Saat server restart, Auto-Reply selalu kembali ke status aman **OFF**.

---

## 🧪 Hasil Pengujian Unit

Aplikasi dilengkapi 33 unit test yang mencakup pengujian database, deduplikasi, identitas kontak, persona AI, anti-loop, dan auto-reply.

Jalankan test dengan:
```bash
npm test
```

Hasil test:
```text
✔ Database: settings storage and retrieval
✔ Database: chat-before-message consistency with foreign keys enabled
✔ AI: system prompt precedence order
✔ MessageDeduplicator: should detect duplicate messages and allow unique ones
✔ MessageDeduplicator: should evict oldest items when exceeding maxSize
✔ MessageDeduplicator: should handle invalid or non-string inputs safely
✔ replacePlaceholders: should replace template variables correctly
✔ replacePlaceholders: should preserve unmapped placeholders or handle empty data
✔ replacePlaceholders: should handle edge cases safely
✔ formatJidDisplay: should handle @lid, @g.us, and @s.whatsapp.net correctly without fake numbers
✔ Test 1: Pesan masuk identik dengan ID yang sama hanya tersimpan satu kali di DB dan tidak menambah unread ganda
✔ Test 2: Dua pesan dengan teks identik tetapi ID berbeda tetap tersimpan dan tampil dua kali
✔ Test 3: Broadcast Socket.IO dan respons REST untuk satu pesan keluar tidak membuat duplikasi (Frontend Deduplication Logic)
✔ Test 4: Listener Socket.IO frontend terpasang sekali dan tidak bertumpuk saat pergantian chat
✔ Test 5: Pesan dengan JID @lid tidak diubah menjadi nomor telepon palsu atau dipaksa ke @s.whatsapp.net
✔ Test 6: Nama kontak yang valid (Adhy) tidak ditimpa oleh fallback saat pesan baru masuk atau keluar
✔ Test 7: Pesan grup tidak mengalami tabrakan ID dengan pesan pribadi (buildMessageDeduplicationKey)
✔ AI service: should handle Ollama unavailable gracefully without crashing
✔ WhatsApp manager: status and contracts
✔ WhatsApp manager: safe destination formatting
✔ WhatsApp manager: sendMessage rejects when disconnected
✔ Test 1: Auto-Reply default status wajib OFF
✔ Test 2: Pesan masuk baru diproses ketika Auto-Reply ON dan Ollama aktif
✔ Test 3: Pesan dari akun sendiri (fromMe) tidak boleh dibalas otomatis
✔ Test 4: Pesan yang sama tidak boleh dibalas dua kali
✔ Test 5: Dua pesan masuk berdekatan ke chat yang sama mematuhi jeda anti-spam (cooldown)
✔ Test 6: Pesan grup (@g.us) tidak dibalas otomatis secara default
✔ Test 7: Ollama offline ditangani dengan aman tanpa crash
✔ Test 8: Respons AI kosong tidak boleh dikirim sebagai pesan
✔ Test 9: Toggle OFF menghentikan pemrosesan pesan baru seketika
✔ Test 10: Pesan lama yang sudah tersimpan di database tidak dibalas ulang saat server restart
✔ Test 11: Pengiriman manual tetap berfungsi dan menghasilkan objek pesan yang valid
✔ Test 12: System prompt default SI BONTOT memuat identitas THE BONTOT RADIO dan santai
ℹ tests 33 | pass 33 | fail 0
```
