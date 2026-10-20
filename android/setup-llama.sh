#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Native Llama Engine Installer (Android ARM64 / Termux)
# Biaya: Rp0 | 100% Bebas Kartu Kredit | Tanpa PRoot (Native C++ ARM64)
# Prioritas: 
# 1. Paket Resmi Termux (llama-cpp 0.7.0 yang sudah terpasang)
# 2. Binary Precompiled ARM64 Resmi dari GitHub Release (dengan verifikasi HTTP & integritas)
# 3. NOL CMAKE — Dilarang memanggil cmake yang rusak linker
# ==============================================================================

PROJECT_DIR="${1:-$HOME/wa-bontot}"
cd "$PROJECT_DIR" || exit 1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "=================================================================="
echo "    🦙 SI BONTOT — NATIVE LLAMA ENGINE INSTALLER (TERMUX) 🦙     "
echo "  Inferensi AI Lokal Mandiri | ARM64 Native | Biaya Rp0           "
echo "=================================================================="
echo -e "${NC}"

# 1. Audit Arsitektur CPU
ARCH=$(uname -m)
echo "Arsitektur CPU: $ARCH"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv8l" ]; then
    echo -e "${RED}[GAGAL] llama-server membutuhkan CPU ARM64 (64-bit). Arsitektur Anda: $ARCH${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Arsitektur ARM64 terverifikasi.${NC}"

# Helper: Uji apakah binary ELF ARM64 dapat dieksekusi tanpa error linker Bionic
test_binary_executable() {
    local bin_path="$1"
    [ -n "$bin_path" ] && [ -x "$bin_path" ] || return 1

    local test_out
    test_out=$("$bin_path" --version 2>&1 || true)
    if [ -z "$test_out" ]; then
        test_out=$("$bin_path" -h 2>&1 | head -n 25 || true)
    fi
    if [ -z "$test_out" ]; then
        test_out=$("$bin_path" 2>&1 | head -n 25 || true)
    fi

    # Deteksi kegagalan linker Bionic libc Android / ketidakcocokan arsitektur
    if echo "$test_out" | grep -qiE "CANNOT LINK|cannot locate symbol|bad ELF|Exec format|Illegal instruction|not found in library|No such file"; then
        return 1
    fi

    # Jika binary menghasilkan banner atau help text (terlepas dari exit code 0 atau 1) -> Valid
    if echo "$test_out" | grep -qiE "llama|usage|options|help|server|build|version|ggml"; then
        return 0
    fi

    # Jika binary menghasilkan output apa pun tanpa linker crash
    if [ -n "$test_out" ]; then
        return 0
    fi

    return 1
}

# Helper: Cari binary llama-server di semua lokasi potensial
find_llama_server() {
    # 1. Cek dari paket dpkg llama-cpp jika terpasang di Termux
    if command -v dpkg >/dev/null 2>&1; then
        local dpkg_bin
        dpkg_bin=$(dpkg -L llama-cpp 2>/dev/null | grep -E '/bin/llama-server$' | head -n 1 || true)
        if [ -n "$dpkg_bin" ] && [ -x "$dpkg_bin" ] && test_binary_executable "$dpkg_bin"; then
            echo "$dpkg_bin"
            return 0
        fi
        dpkg_bin=$(dpkg -L llama-cpp 2>/dev/null | grep -E '/bin/.*server' | head -n 1 || true)
        if [ -n "$dpkg_bin" ] && [ -x "$dpkg_bin" ] && test_binary_executable "$dpkg_bin"; then
            echo "$dpkg_bin"
            return 0
        fi
    fi

    # 2. Cek lokasi standar Termux dan proyek
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

download_official_prebuilt() {
    echo -e "\n${YELLOW}[Jalur Prebuilt] Memeriksa & mengunduh binary resmi ARM64 Android dari GitHub release (ggml-org/llama.cpp)...${NC}"
    mkdir -p "$PROJECT_DIR/bin" "$PROJECT_DIR/scratch"
    local ARCHIVE="$PROJECT_DIR/scratch/llama-android-arm64.tar.gz"
    local API_URL="https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10"
    local CANDIDATE_URLS=()

    echo "Menghubungi GitHub API untuk memverifikasi aset rilis ARM64 Android..."
    local API_RESP
    API_RESP=$(curl -sL --max-time 15 -H "Accept: application/vnd.github.v3+json" "$API_URL" 2>/dev/null || true)

    if [ -n "$API_RESP" ]; then
        while IFS= read -r match_url; do
            if [ -n "$match_url" ]; then
                CANDIDATE_URLS+=("$match_url")
            fi
        done < <(echo "$API_RESP" | grep -o 'https://github.com/ggml-org/llama.cpp/releases/download/[^"]*android-arm64[^"]*\.tar\.gz' | sort -u || true)
    fi

    echo "Ditemukan ${#CANDIDATE_URLS[@]} kandidat aset rilis dari GitHub API."

    # Daftar URL cadangan jika GitHub API dibatasi kuota (HTTP 403 Rate Limited)
    if [ ${#CANDIDATE_URLS[@]} -eq 0 ]; then
        echo "GitHub API tidak mengembalikan daftar (kemungkinan limit kuota API). Menggunakan daftar rilis terverifikasi..."
        CANDIDATE_URLS+=(
            "https://github.com/ggml-org/llama.cpp/releases/download/b11699/llama-b11699-bin-android-arm64.tar.gz"
            "https://github.com/ggml-org/llama.cpp/releases/download/b11641/llama-b11641-bin-android-arm64.tar.gz"
            "https://github.com/ggml-org/llama.cpp/releases/download/b11617/llama-b11617-bin-android-arm64.tar.gz"
            "https://github.com/ggml-org/llama.cpp/releases/download/b11334/llama-b11334-bin-android-arm64.tar.gz"
        )
    fi

    for TARGET_URL in "${CANDIDATE_URLS[@]}"; do
        echo -e "\n--- Menguji Kandidat Rilis: $TARGET_URL ---"
        # 1. Audit HTTP Header sebelum unduhan
        local HTTP_CODE
        HTTP_CODE=$(curl -s -L -o /dev/null -w "%{http_code}" --max-time 15 "$TARGET_URL" 2>/dev/null || echo "000")
        echo "HTTP Status Code: $HTTP_CODE"

        if [ "$HTTP_CODE" != "200" ]; then
            echo -e "${YELLOW}URL tidak mengembalikan HTTP 200 (Status: $HTTP_CODE). Melewati kandidat ini.${NC}"
            continue
        fi

        # 2. Unduh berkas dengan curl dan tangkap error asli
        echo "Mengunduh arsip binary dari $TARGET_URL..."
        rm -f "$ARCHIVE"
        local CURL_LOG="$PROJECT_DIR/scratch/curl_dl.log"
        if ! curl -L --fail --progress-bar -o "$ARCHIVE" "$TARGET_URL" 2>"$CURL_LOG"; then
            echo -e "${RED}[ERROR UNDUHAN] curl gagal mengunduh dari server GitHub.${NC}"
            if [ -f "$CURL_LOG" ]; then
                echo "Detail log curl:"
                cat "$CURL_LOG"
            fi
            rm -f "$ARCHIVE" "$CURL_LOG"
            continue
        fi
        rm -f "$CURL_LOG"

        local FILE_SIZE
        FILE_SIZE=$(wc -c < "$ARCHIVE" 2>/dev/null || echo 0)
        echo "Ukuran berkas yang diunduh: $FILE_SIZE byte ($((FILE_SIZE / 1048576)) MB)"

        if [ "$FILE_SIZE" -lt 5000000 ]; then
            echo -e "${RED}[ERROR INTEGRITAS] Berkas terlalu kecil ($FILE_SIZE byte), kemungkinan halaman error HTML.${NC}"
            echo "Isi awal berkas:"
            head -n 5 "$ARCHIVE" 2>/dev/null || true
            rm -f "$ARCHIVE"
            continue
        fi

        # 3. Verifikasi integritas tar.gz
        if ! tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
            echo -e "${RED}[ERROR INTEGRITAS] Berkas yang diunduh bukan format tar.gz yang valid.${NC}"
            rm -f "$ARCHIVE"
            continue
        fi

        # 4. Ekstrak
        echo "Mengekstrak binary ke folder scratch..."
        rm -rf "$PROJECT_DIR/scratch/extracted"
        mkdir -p "$PROJECT_DIR/scratch/extracted"
        tar -xzf "$ARCHIVE" -C "$PROJECT_DIR/scratch/extracted"

        local FOUND_BIN
        FOUND_BIN=$(find "$PROJECT_DIR/scratch/extracted" -type f -name "llama-server" 2>/dev/null | head -n 1)

        if [ -n "$FOUND_BIN" ] && [ -f "$FOUND_BIN" ]; then
            cp "$FOUND_BIN" "$PROJECT_DIR/bin/llama-server"
            chmod +x "$PROJECT_DIR/bin/llama-server"

            # Salin library pendukung (.so)
            find "$PROJECT_DIR/scratch/extracted" -type f -name "*.so*" -exec cp {} "$PROJECT_DIR/bin/" \; 2>/dev/null || true
            if [ -d "$PREFIX/lib" ]; then
                find "$PROJECT_DIR/scratch/extracted" -type f -name "*.so*" -exec cp {} "$PREFIX/lib/" \; 2>/dev/null || true
            fi

            if test_binary_executable "$PROJECT_DIR/bin/llama-server"; then
                echo -e "${GREEN}✔ Prebuilt binary llama-server berhasil diekstrak dan lolos uji eksekusi Android Bionic!${NC}"
                rm -f "$ARCHIVE"
                rm -rf "$PROJECT_DIR/scratch/extracted"
                return 0
            else
                echo -e "${RED}[ERROR] Binary hasil ekstraksi gagal saat dieksekusi di OS Android Bionic.${NC}"
                rm -f "$ARCHIVE"
                rm -rf "$PROJECT_DIR/scratch/extracted"
                continue
            fi
        fi

        echo -e "${YELLOW}[PERINGATAN] Berkas llama-server tidak ditemukan di dalam arsip ini.${NC}"
        rm -f "$ARCHIVE"
        rm -rf "$PROJECT_DIR/scratch/extracted"
    done

    echo -e "${RED}[ERROR AKHIR] Semua kandidat binary prebuilt ARM64 gagal diunduh atau dieksekusi.${NC}"
    return 1
}

# 2. Audit dan Deteksi Paket llama-cpp / llama-server
echo -e "\n${BOLD}[Audit Paket & Binary Lokal] Memeriksa status instalasi llama di Termux...${NC}"
INSTALLED=0

# Audit isi paket llama-cpp dari Termux jika dpkg tersedia
if command -v dpkg >/dev/null 2>&1; then
    if dpkg -s llama-cpp >/dev/null 2>&1; then
        echo -e "${GREEN}✔ Paket resmi 'llama-cpp' terdeteksi di database dpkg!${NC}"
        PKG_VERSION=$(dpkg -s llama-cpp 2>/dev/null | grep -i '^Version:' | head -n 1 || echo "Version: 0.7.0")
        echo "  $PKG_VERSION"
        echo "  Daftar berkas executable yang disediakan paket llama-cpp:"
        dpkg -L llama-cpp 2>/dev/null | grep -E '/bin/' || echo "  (tidak ada berkas di /bin/)"

        # Temukan executable paket
        EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
        if [ -n "$EXISTING_BIN" ] && test_binary_executable "$EXISTING_BIN"; then
            echo -e "${GREEN}✔ Binary llama-server dari paket llama-cpp berhasil diverifikasi: $EXISTING_BIN${NC}"
            mkdir -p "$PROJECT_DIR/bin"
            cp "$EXISTING_BIN" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || ln -sf "$EXISTING_BIN" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
            chmod +x "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
            INSTALLED=1
        fi
    else
        echo "Paket 'llama-cpp' belum terpasang di database dpkg."
    fi
fi

# Jika belum terdeteksi via dpkg, periksa binary di path standar proyek / sistem
if [ "$INSTALLED" -eq 0 ]; then
    EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
    if [ -n "$EXISTING_BIN" ] && test_binary_executable "$EXISTING_BIN"; then
        echo -e "${GREEN}✔ Binary llama-server fungsional terdeteksi di: $EXISTING_BIN${NC}"
        mkdir -p "$PROJECT_DIR/bin"
        if [ "$EXISTING_BIN" != "$PROJECT_DIR/bin/llama-server" ]; then
            cp "$EXISTING_BIN" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || ln -sf "$EXISTING_BIN" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
            chmod +x "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
        fi
        INSTALLED=1
    fi
fi

# Jika binary belum ada sama sekali, coba pasang via pkg Termux (tur-repo)
if [ "$INSTALLED" -eq 0 ]; then
    echo -e "\n${YELLOW}[Prioritas 1] Memasang paket resmi llama-cpp via Termux pkg manager (tur-repo)...${NC}"
    pkg install -y tur-repo < /dev/null 2>&1 || true
    pkg update -y < /dev/null 2>&1 || true
    pkg install -y llama-cpp < /dev/null 2>&1 || true

    EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
    if [ -n "$EXISTING_BIN" ] && test_binary_executable "$EXISTING_BIN"; then
        echo -e "${GREEN}✔ Paket llama-cpp berhasil dipasang via package manager Termux.${NC}"
        mkdir -p "$PROJECT_DIR/bin"
        cp "$EXISTING_BIN" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || ln -sf "$EXISTING_BIN" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
        chmod +x "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
        INSTALLED=1
    fi
fi

# Jika paket repositori gagal, coba unduh Prebuilt Binary ARM64 Resmi
if [ "$INSTALLED" -eq 0 ]; then
    echo -e "\n${YELLOW}[Prioritas 2: Alternatif Prebuilt] Mengunduh rilis binary resmi ggml-org/llama.cpp...${NC}"
    if download_official_prebuilt; then
        INSTALLED=1
        EXISTING_BIN="$PROJECT_DIR/bin/llama-server"
    fi
fi

# DILARANG MEMANGGIL CMAKE
if [ "$INSTALLED" -eq 0 ]; then
    echo -e "\n${RED}[GAGAL KRITIS] Tidak dapat menemukan atau memasang binary llama-server.${NC}"
    echo "Detail kegagalan:"
    echo "1. Paket repositori Termux llama-cpp tidak menyediakan binary yang lolos uji eksekusi."
    echo "2. Seluruh kandidat unduhan prebuilt binary ARM64 resmi gagal diunduh atau gagal dieksekusi."
    echo "3. Kompilasi lokal CMake dilarang karena toolchain cmake di perangkat Anda mengalami symbol linker error."
    echo "Periksa koneksi jaringan atau repositori Termux Anda, lalu jalankan ulang pembaruan."
    exit 1
fi

VERSION_INFO=$("$EXISTING_BIN" --version 2>/dev/null || "$EXISTING_BIN" -h 2>/dev/null | head -n 2 | tr '\n' ' ' || echo "llama-server ARM64")
echo "  Info Versi: $VERSION_INFO"

# 3. Verifikasi Eksekusi Binary Nyata Sebelum Memulai Layanan
LLAMA_EXEC=$(find_llama_server 2>/dev/null || true)
if [ -z "$LLAMA_EXEC" ] || ! test_binary_executable "$LLAMA_EXEC"; then
    echo -e "${RED}[GAGAL KRITIS] Verifikasi akhir gagal: Binary $LLAMA_EXEC tidak dapat dieksekusi.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Binary tervalidasi siap pakai: $LLAMA_EXEC${NC}"

# 4. Verifikasi Berkas Model GGUF
echo -e "\n${YELLOW}Memeriksa berkas model AI di $PROJECT_DIR/models/...${NC}"
mkdir -p "$PROJECT_DIR/models"
MODEL_FILE=$(find_model_file 2>/dev/null || true)

if [ -n "$MODEL_FILE" ] && [ -f "$MODEL_FILE" ]; then
    MODEL_SIZE_STR=$(du -h "$MODEL_FILE" | cut -f1)
    echo -e "${GREEN}✔ Model GGUF terdeteksi: $(basename "$MODEL_FILE") [${MODEL_SIZE_STR}].${NC}"
else
    echo "Berkas model GGUF belum ditemukan di $PROJECT_DIR/models/."
    echo "Mengunduh model resmi Qwen 2.5 0.5B Instruct GGUF..."
    bash "$PROJECT_DIR/android/download-ai-model.sh" "$PROJECT_DIR"
    MODEL_FILE=$(find_model_file 2>/dev/null || true)
    if [ -z "$MODEL_FILE" ] || [ ! -f "$MODEL_FILE" ]; then
        echo -e "${RED}[GAGAL] Berkas model GGUF gagal diunduh atau tidak ditemukan.${NC}"
        exit 1
    fi
fi

# 5. Restart Layanan Bot untuk Mengaktifkan Engine Persisten
echo -e "\n${CYAN}Memulai ulang layanan SI BONTOT untuk memuat Llama Engine...${NC}"
bash "$PROJECT_DIR/android/start-service.sh" restart

# 6. Polling Kesiapan Port 8080 (Maksimal 20 detik)
echo -e "${YELLOW}Menunggu Llama Engine memuat model ke memori (polling /health)...${NC}"
WAIT_COUNT=0
ENGINE_READY=0
while [ "$WAIT_COUNT" -lt 10 ]; do
    WAIT_COUNT=$((WAIT_COUNT + 1))
    HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:8080/health 2>/dev/null || echo "000")
    if [ "$HEALTH_CODE" = "200" ]; then
        ENGINE_READY=1
        echo -e "${GREEN}✔ Llama Engine siap di port 8080 (HTTP 200 OK) dalam ${WAIT_COUNT}x2 detik.${NC}"
        break
    elif [ "$HEALTH_CODE" = "503" ]; then
        echo "  [Jeda] Model sedang dimuat ke RAM... (${WAIT_COUNT}/10)"
    else
        echo "  [Jeda] Menunggu port 8080 aktif... (${WAIT_COUNT}/10)"
    fi
    sleep 2
done

# 7. Jalankan Uji Inferensi HTTP Nyata
echo -e "\n${CYAN}Menjalankan uji inferensi HTTP nyata...${NC}"
bash "$PROJECT_DIR/android/test-inference.sh" "$PROJECT_DIR"
