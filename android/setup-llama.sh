#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Native Llama Engine Installer (Android ARM64 / Termux)
# Biaya: Rp0 | 100% Bebas Kartu Kredit | Tanpa PRoot (Native C++ ARM64)
# Prioritas: 
# 1. Audit Paket Resmi Termux (llama-cpp 0.7.0 yang sudah terpasang)
# 2. Binary Precompiled ARM64 Bionic Resmi dari GitHub Release (ggml-org/llama.cpp)
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

# Pastikan loader sistem selalu mencari pustaka di folder bin proyek dan prefix Termux
export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

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
# Menangkap stdout/stderr dan TIDAK menganggap exit code nonzero sebagai kegagalan jika help text muncul
test_binary_executable() {
    local bin_path="$1"
    [ -n "$bin_path" ] && [ -x "$bin_path" ] || return 1

    export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

    local test_out
    local exit_code=0
    test_out=$("$bin_path" -h 2>&1) || exit_code=$?
    if [ -z "$test_out" ]; then
        test_out=$("$bin_path" --help 2>&1) || exit_code=$?
    fi
    if [ -z "$test_out" ]; then
        test_out=$("$bin_path" 2>&1 | head -n 25) || exit_code=$?
    fi

    # Deteksi kegagalan fatal linker Bionic libc Android / ketidakcocokan arsitektur / pustaka hilang
    if echo "$test_out" | grep -qiE "CANNOT LINK|cannot locate symbol|bad ELF|Exec format|Illegal instruction|library \".*\" not found|No such file or directory"; then
        return 1
    fi

    # Jika binary menghasilkan banner atau help text (terlepas dari exit code nonzero 1 atau 255) -> Valid
    if echo "$test_out" | grep -qiE "llama|usage|options|help|server|build|version|ggml"; then
        return 0
    fi

    # Jika ada output dan bukan crash linker
    if [ -n "$test_out" ] && [ "$exit_code" -le 2 ]; then
        return 0
    fi

    return 1
}

# Helper: Audit mendalam satu kandidat binary dengan logging transparan
audit_binary_candidate() {
    local bin_path="$1"
    local source_desc="$2"
    echo -e "  [Audit Kandidat] $source_desc: $bin_path"
    if [ ! -f "$bin_path" ]; then
        echo "    -> Berkas tidak ada di disk."
        return 1
    fi
    if [ ! -x "$bin_path" ]; then
        echo "    -> Berkas tidak executable. Memberikan izin chmod +x..."
        chmod +x "$bin_path" 2>/dev/null || true
    fi

    export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

    local out
    local code=0
    out=$("$bin_path" -h 2>&1) || code=$?

    echo "    -> Exit Code: $code"
    local preview
    preview=$(echo "$out" | head -n 3 | tr '\n' ' ' | cut -c1-120)
    echo "    -> Cuplikan Respons: \"$preview...\""

    if echo "$out" | grep -qiE "CANNOT LINK|cannot locate symbol|bad ELF|Exec format|Illegal instruction|library \".*\" not found"; then
        local err_line
        err_line=$(echo "$out" | grep -iE "CANNOT LINK|cannot locate symbol|bad ELF|Exec format|Illegal instruction|library" | head -n 1)
        echo -e "    -> ${RED}[GAGAL LINKER] $err_line${NC}"
        return 1
    elif echo "$out" | grep -qiE "llama|usage|options|help|server|build|version|ggml"; then
        echo -e "    -> ${GREEN}[VALID] Binary lolos uji eksekusi dan menghasilkan teks bantuan normal.${NC}"
        return 0
    elif [ -n "$out" ]; then
        echo -e "    -> ${GREEN}[VALID] Binary merespons tanpa error linker.${NC}"
        return 0
    else
        echo -e "    -> ${RED}[GAGAL] Binary tidak menghasilkan output apa pun.${NC}"
        return 1
    fi
}

# Helper: Cari binary llama-server di semua lokasi potensial
find_llama_server() {
    export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

    # 1. Cek dari paket dpkg llama-cpp / llama.cpp jika terpasang di Termux
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

    # 2. Cek lokasi standar Termux dan folder proyek
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
    echo -e "\n${YELLOW}[Jalur Prebuilt Bionic] Mengunduh binary resmi ARM64 Android dari GitHub release (ggml-org/llama.cpp)...${NC}"
    mkdir -p "$PROJECT_DIR/bin" "$PROJECT_DIR/scratch"
    local ARCHIVE="$PROJECT_DIR/scratch/llama-android-arm64.tar.gz"
    local CANDIDATE_URLS=()

    # Daftar rilis terverifikasi upstream ggml-org/llama.cpp untuk Android ARM64 Bionic (NDK API 28)
    # b11669 merupakan build resmi untuk rilis v0.7.0
    local OFFICIAL_TAGS=("b11753" "b11699" "b11669" "b11641" "b11617")

    # Upayakan query GitHub API jika kuota IP belum terlampaui
    local API_URL="https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=5"
    echo "Memeriksa ketersediaan rilis terbaru via GitHub API..."
    local API_RESP
    API_RESP=$(curl -s -L -4 --connect-timeout 8 --max-time 12 -H "Accept: application/vnd.github.v3+json" -H "User-Agent: Bontot-Termux-Agent" "$API_URL" 2>/dev/null || true)

    if [ -n "$API_RESP" ]; then
        while IFS= read -r match_url; do
            if [ -n "$match_url" ]; then
                CANDIDATE_URLS+=("$match_url")
            fi
        done < <(echo "$API_RESP" | grep -o 'https://github.com/ggml-org/llama.cpp/releases/download/[^"]*bin-android-arm64\.tar\.gz' | sort -u || true)
    fi

    # Gabungkan daftar kandidat rilis resmi upstream
    for tag in "${OFFICIAL_TAGS[@]}"; do
        CANDIDATE_URLS+=("https://github.com/ggml-org/llama.cpp/releases/download/${tag}/llama-${tag}-bin-android-arm64.tar.gz")
    done

    # Hapus duplikat kandidat
    local UNIQUE_URLS=()
    for u in "${CANDIDATE_URLS[@]}"; do
        local seen=0
        for uu in "${UNIQUE_URLS[@]}"; do
            if [ "$uu" = "$u" ]; then
                seen=1
                break
            fi
        done
        if [ "$seen" -eq 0 ]; then
            UNIQUE_URLS+=("$u")
        fi
    done

    echo "Total kandidat rilis ARM64 yang akan diuji: ${#UNIQUE_URLS[@]}"

    for TARGET_URL in "${UNIQUE_URLS[@]}"; do
        echo -e "\n--- Menguji Kandidat: $TARGET_URL ---"
        # 1. Audit HTTP Header via HEAD (-I) request dengan IPv4 (-4) dan follow redirect (-L)
        # KRITIS: Jangan gunakan -o /dev/null tanpa -I karena akan mencoba mengunduh seluruh 73 MB dan menyebabkan timeout (HTTP 000)
        local HTTP_CODE
        HTTP_CODE=$(curl -s -I -L -4 --connect-timeout 10 --max-time 15 -w "%{http_code}" -o /dev/null "$TARGET_URL" 2>/dev/null || echo "000")
        echo "HTTP Status Code (HEAD): $HTTP_CODE"

        if [ "$HTTP_CODE" != "200" ]; then
            echo -e "${YELLOW}URL tidak mengembalikan HTTP 200 (Status: $HTTP_CODE). Melewati kandidat ini.${NC}"
            continue
        fi

        # 2. Unduh berkas dengan curl IPv4, timeout realistis (600s), dan retry otomatis
        echo -e "${GREEN}✔ Aset rilis valid (HTTP 200). Mengunduh arsip binary Android ARM64 (~73 MB)...${NC}"
        rm -f "$ARCHIVE"
        local CURL_LOG="$PROJECT_DIR/scratch/curl_dl.log"
        if ! curl -L -4 --connect-timeout 20 --max-time 600 --retry 3 --retry-delay 2 --progress-bar -o "$ARCHIVE" "$TARGET_URL" 2>"$CURL_LOG"; then
            echo -e "${RED}[ERROR UNDUHAN] curl gagal mengunduh dari server GitHub.${NC}"
            if [ -f "$CURL_LOG" ]; then
                cat "$CURL_LOG"
            fi
            rm -f "$ARCHIVE" "$CURL_LOG"
            continue
        fi
        rm -f "$CURL_LOG"

        local FILE_SIZE
        FILE_SIZE=$(wc -c < "$ARCHIVE" 2>/dev/null || echo 0)
        echo "Ukuran berkas yang diunduh: $FILE_SIZE byte ($((FILE_SIZE / 1048576)) MB)"

        if [ "$FILE_SIZE" -lt 10000000 ]; then
            echo -e "${RED}[ERROR INTEGRITAS] Berkas terlalu kecil ($FILE_SIZE byte), bukan arsip biner lengkap.${NC}"
            rm -f "$ARCHIVE"
            continue
        fi

        # 3. Verifikasi integritas format tar.gz
        if ! tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
            echo -e "${RED}[ERROR INTEGRITAS] Berkas yang diunduh bukan format tar.gz yang valid.${NC}"
            rm -f "$ARCHIVE"
            continue
        fi

        # 4. Ekstrak
        echo "Mengekstrak binary ke folder scratch/extracted..."
        rm -rf "$PROJECT_DIR/scratch/extracted"
        mkdir -p "$PROJECT_DIR/scratch/extracted"
        tar -xzf "$ARCHIVE" -C "$PROJECT_DIR/scratch/extracted"

        local FOUND_BIN
        FOUND_BIN=$(find "$PROJECT_DIR/scratch/extracted" -type f -name "llama-server" 2>/dev/null | head -n 1)

        if [ -n "$FOUND_BIN" ] && [ -f "$FOUND_BIN" ]; then
            cp "$FOUND_BIN" "$PROJECT_DIR/bin/llama-server"
            chmod +x "$PROJECT_DIR/bin/llama-server"

            # Salin seluruh library pendukung (.so) ke folder bin proyek dan prefix Termux
            find "$PROJECT_DIR/scratch/extracted" -type f -name "*.so*" -exec cp {} "$PROJECT_DIR/bin/" \; 2>/dev/null || true
            if [ -d "$PREFIX/lib" ]; then
                find "$PROJECT_DIR/scratch/extracted" -type f -name "*.so*" -exec cp {} "$PREFIX/lib/" \; 2>/dev/null || true
            fi

            export LD_LIBRARY_PATH="$PROJECT_DIR/bin:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

            if audit_binary_candidate "$PROJECT_DIR/bin/llama-server" "Prebuilt Binary Hasil Ekstraksi"; then
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

# ==============================================================================
# 2. AUDIT SISTEM: PERIKSA PAKET RESMI llama-cpp & BINARY LOKAL
# ==============================================================================
echo -e "\n${BOLD}=================================================================="
echo "    [Tahap 1] AUDIT MANIFEST PAKET & BINARY LOKAL                "
echo "==================================================================${NC}"
INSTALLED=0

# Audit isi paket llama-cpp dari database dpkg Termux
if command -v dpkg >/dev/null 2>&1; then
    for pkg_check in "llama-cpp" "llama.cpp" "llama-cpp-tools"; do
        if dpkg -s "$pkg_check" >/dev/null 2>&1; then
            echo -e "${GREEN}✔ Paket resmi '$pkg_check' terdeteksi di database dpkg!${NC}"
            echo "  Detail Paket:"
            dpkg -s "$pkg_check" 2>/dev/null | grep -E '^(Package|Version|Architecture|Status|Depends):' | sed 's/^/    /'

            echo "  Daftar executable yang disediakan paket $pkg_check:"
            local pkg_bins
            pkg_bins=$(dpkg -L "$pkg_check" 2>/dev/null | grep -E '/bin/' || true)
            if [ -n "$pkg_bins" ]; then
                echo "$pkg_bins" | sed 's/^/    - /'
                
                # Uji setiap binary yang disediakan paket
                while IFS= read -r bin_cand; do
                    if [ -n "$bin_cand" ] && [ -f "$bin_cand" ]; then
                        if audit_binary_candidate "$bin_cand" "Paket $pkg_check"; then
                            if echo "$bin_cand" | grep -q "server"; then
                                mkdir -p "$PROJECT_DIR/bin"
                                cp "$bin_cand" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || ln -sf "$bin_cand" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
                                chmod +x "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
                                INSTALLED=1
                                EXISTING_BIN="$PROJECT_DIR/bin/llama-server"
                                break
                            fi
                        fi
                    fi
                done <<< "$pkg_bins"
            else
                echo "    (tidak ada berkas di /bin/)"
            fi
        fi
    done
fi

# Jika belum terdeteksi dari dpkg, audit binary di lokasi standar proyek dan sistem
if [ "$INSTALLED" -eq 0 ]; then
    echo -e "\nMemeriksa binary di direktori standar sistem dan proyek..."
    for std_bin in \
        "$PROJECT_DIR/bin/llama-server" \
        "$PREFIX/bin/llama-server" \
        "/data/data/com.termux/files/usr/bin/llama-server" \
        "$PREFIX/bin/llama.cpp-server" \
        "/data/data/com.termux/files/usr/bin/llama.cpp-server" \
        "$HOME/llama.cpp/build/bin/llama-server" \
        "$HOME/llama.cpp/llama-server"; do
        if [ -f "$std_bin" ]; then
            if audit_binary_candidate "$std_bin" "Lokasi Standar"; then
                mkdir -p "$PROJECT_DIR/bin"
                if [ "$std_bin" != "$PROJECT_DIR/bin/llama-server" ]; then
                    cp "$std_bin" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || ln -sf "$std_bin" "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
                    chmod +x "$PROJECT_DIR/bin/llama-server" 2>/dev/null || true
                fi
                INSTALLED=1
                EXISTING_BIN="$PROJECT_DIR/bin/llama-server"
                break
            fi
        fi
    done
fi

# Jika binary belum berfungsi, coba unduh Prebuilt Binary ARM64 Resmi dari GitHub Release
if [ "$INSTALLED" -eq 0 ]; then
    echo -e "\n${BOLD}=================================================================="
    echo "    [Tahap 2] MENGUNDUH PRECOMPILED BINARY ANDROID ARM64 RESMI   "
    echo "==================================================================${NC}"
    if download_official_prebuilt; then
        INSTALLED=1
        EXISTING_BIN="$PROJECT_DIR/bin/llama-server"
    fi
fi

# DILARANG MEMANGGIL CMAKE
if [ "$INSTALLED" -eq 0 ]; then
    echo -e "\n${RED}${BOLD}=================================================================="
    echo "    ❌ [GAGAL KRITIS] TIDAK ADA BINARY LLAMA YANG DAPAT DIAKTIFKAN"
    echo "==================================================================${NC}"
    echo "Laporan Hambatan Sebenarnya:"
    echo "1. Paket Termux lokal (jika terpasang) mengalami symbol linker crash pada Bionic libc atau tidak memuat server."
    echo "2. Seluruh kandidat unduhan binary resmi ARM64 gagal diunduh atau dieksekusi di OS ini."
    echo "3. Kompilasi lokal CMake dilarang karena toolchain cmake di perangkat Anda mengalami symbol linker error."
    echo "Periksa sambungan internet perangkat Anda lalu coba jalankan kembali skrip ini."
    exit 1
fi

echo -e "\n${GREEN}${BOLD}✔ Verifikasi Binary Berhasil!${NC}"
echo "  Lokasi Binary Terpilih: $EXISTING_BIN"

# ==============================================================================
# 3. VERIFIKASI MODEL GGUF
# ==============================================================================
echo -e "\n${BOLD}=================================================================="
echo "    [Tahap 3] VERIFIKASI BERKAS MODEL AI GGUF                    "
echo "==================================================================${NC}"
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

# ==============================================================================
# 4. RESTART LAYANAN BOT & POLLING ENGINE
# ==============================================================================
echo -e "\n${BOLD}=================================================================="
echo "    [Tahap 4] MEMULAI ULANG LAYANAN SI BONTOT (PORT 8080 & 3001) "
echo "==================================================================${NC}"
bash "$PROJECT_DIR/android/start-service.sh" restart

echo -e "\n${YELLOW}Menunggu Llama Engine memuat model ke memori (polling /health)...${NC}"
WAIT_COUNT=0
ENGINE_READY=0
while [ "$WAIT_COUNT" -lt 15 ]; do
    WAIT_COUNT=$((WAIT_COUNT + 1))
    HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:8080/health 2>/dev/null || echo "000")
    if [ "$HEALTH_CODE" = "200" ]; then
        ENGINE_READY=1
        echo -e "${GREEN}✔ Llama Engine siap di port 8080 (HTTP 200 OK) dalam ${WAIT_COUNT}x2 detik.${NC}"
        break
    elif [ "$HEALTH_CODE" = "503" ]; then
        echo "  [Jeda] Model sedang dimuat ke RAM... (${WAIT_COUNT}/15)"
    else
        echo "  [Jeda] Menunggu port 8080 aktif... (${WAIT_COUNT}/15)"
    fi
    sleep 2
done

if [ "$ENGINE_READY" -eq 0 ]; then
    echo -e "${YELLOW}[PERINGATAN] Llama Engine belum mengembalikan HTTP 200 dalam waktu 30 detik.${NC}"
    echo "Periksa logs/llama.log untuk melihat pesan startup engine."
fi

# ==============================================================================
# 5. UJI INFERENSI NYATA LENGKAP
# ==============================================================================
echo -e "\n${BOLD}=================================================================="
echo "    [Tahap 5] UJI INFERENSI HTTP NYATA LENGKAP                   "
echo "==================================================================${NC}"
bash "$PROJECT_DIR/android/test-inference.sh" "$PROJECT_DIR"
