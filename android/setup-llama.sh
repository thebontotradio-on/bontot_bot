#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Native Llama Engine Installer (Android ARM64 / Termux)
# Biaya: Rp0 | 100% Bebas Kartu Kredit | Tanpa PRoot (Native C++ ARM64)
# Prioritas: Binary Precompiled Resmi Tanpa Ketergantungan Kompilasi CMake
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

find_llama_server() {
    if command -v llama-server >/dev/null 2>&1; then
        command -v llama-server
        return 0
    fi
    for p in \
        "$PROJECT_DIR/bin/llama-server" \
        "$PREFIX/bin/llama-server" \
        "/data/data/com.termux/files/usr/bin/llama-server" \
        "$HOME/llama.cpp/build/bin/llama-server" \
        "$HOME/llama.cpp/llama-server"; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

test_binary_executable() {
    local bin_path="$1"
    if [ -n "$bin_path" ] && [ -x "$bin_path" ]; then
        # Eksekusi singkat flag bantuan/versi untuk memverifikasi kompatibilitas libc/symbol
        "$bin_path" -h >/dev/null 2>&1 || "$bin_path" --version >/dev/null 2>&1
        return $?
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
    echo -e "\n${YELLOW}[Metode Prebuilt] Mengunduh binary resmi ARM64 Android dari GitHub release (ggml-org/llama.cpp)...${NC}"
    mkdir -p "$PROJECT_DIR/bin" "$PROJECT_DIR/scratch"
    local ARCHIVE="$PROJECT_DIR/scratch/llama-android-arm64.tar.gz"
    
    # URL binary resmi Android ARM64 release terverifikasi (Bionic ABI kompatibel)
    local OFFICIAL_RELEASE_URL="https://github.com/ggml-org/llama.cpp/releases/download/b11669/llama-b11669-bin-android-arm64.tar.gz"
    
    echo "Mengunduh paket binary resmi: $OFFICIAL_RELEASE_URL"
    if curl -L -C - --progress-bar -o "$ARCHIVE" "$OFFICIAL_RELEASE_URL"; then
        echo "Mengekstrak binary ke folder proyek..."
        rm -rf "$PROJECT_DIR/scratch/extracted"
        mkdir -p "$PROJECT_DIR/scratch/extracted"
        tar -xzf "$ARCHIVE" -C "$PROJECT_DIR/scratch/extracted" 2>/dev/null || tar -xf "$ARCHIVE" -C "$PROJECT_DIR/scratch/extracted"
        
        local FOUND_BIN
        FOUND_BIN=$(find "$PROJECT_DIR/scratch/extracted" -type f -name "llama-server" 2>/dev/null | head -n 1)
        
        if [ -n "$FOUND_BIN" ] && [ -f "$FOUND_BIN" ]; then
            cp "$FOUND_BIN" "$PROJECT_DIR/bin/llama-server"
            chmod +x "$PROJECT_DIR/bin/llama-server"
            
            # Salin library pendukung jika ada
            find "$PROJECT_DIR/scratch/extracted" -type f -name "*.so*" -exec cp {} "$PROJECT_DIR/bin/" \; 2>/dev/null || true
            if [ -d "$PREFIX/lib" ]; then
                find "$PROJECT_DIR/scratch/extracted" -type f -name "*.so*" -exec cp {} "$PREFIX/lib/" \; 2>/dev/null || true
            fi
            
            # Verifikasi binary hasil ekstraksi
            if test_binary_executable "$PROJECT_DIR/bin/llama-server"; then
                echo -e "${GREEN}✔ Prebuilt binary llama-server berhasil dipasang dan lulus uji eksekusi!${NC}"
                rm -f "$ARCHIVE"
                rm -rf "$PROJECT_DIR/scratch/extracted"
                return 0
            fi
        fi
    fi
    echo -e "${YELLOW}[INFO] Unduhan binary prebuilt belum berhasil. Memeriksa alternatif repositori...${NC}"
    return 1
}

# 2. Cek apakah llama-server fungsional sudah terpasang
EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
if [ -n "$EXISTING_BIN" ] && test_binary_executable "$EXISTING_BIN"; then
    echo -e "${GREEN}✔ Binary llama-server fungsional sudah terpasang di: $EXISTING_BIN${NC}"
    echo "Versi: $("$EXISTING_BIN" --version 2>/dev/null || echo 'llama-server ARM64')"
else
    INSTALLED=0

    # Prioritas 1: Paket resmi Termux tur-repo
    echo -e "\n${YELLOW}[Prioritas 1] Mencoba instalasi paket resmi Termux User Repository (tur-repo)...${NC}"
    pkg install -y tur-repo < /dev/null 2>&1 || true
    pkg update -y < /dev/null 2>&1 || true
    pkg install -y llama-cpp < /dev/null 2>&1 || true

    EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
    if [ -n "$EXISTING_BIN" ] && test_binary_executable "$EXISTING_BIN"; then
        echo -e "${GREEN}✔ Paket llama-cpp berhasil dipasang via package manager Termux.${NC}"
        INSTALLED=1
    fi

    # Prioritas 2: Unduh Prebuilt Official Binary (Bypass CMake & toolchain rusak)
    if [ "$INSTALLED" -eq 0 ]; then
        if download_official_prebuilt; then
            INSTALLED=1
        fi
    fi

    # Prioritas 3: Kompilasi C++ Native HANYA JIKA toolchain CMake terbukti sehat
    if [ "$INSTALLED" -eq 0 ]; then
        echo -e "\n${YELLOW}[Prioritas 3] Memeriksa kelayakan toolchain kompilasi lokal...${NC}"
        
        # Audit apakah cmake mengalami symbol linker error seperti yang dilaporkan
        if ! cmake --version >/dev/null 2>&1; then
            echo -e "${RED}[DIAGNOSTIK] cmake di Termux mengalami symbol linker error atau tidak kompatibel.${NC}"
            echo -e "${YELLOW}Kompilasi lokal dilewati demi mencegah crash linker yang berulang.${NC}"
        else
            echo "Toolchain CMake terdeteksi sehat. Mempersiapkan kompilasi native C++..."
            pkg install -y git clang make libandroid-spawn < /dev/null 2>&1 || true

            SRC_DIR="$HOME/llama.cpp"
            if [ ! -d "$SRC_DIR" ]; then
                git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$SRC_DIR" < /dev/null 2>&1 || true
            fi

            if [ -d "$SRC_DIR" ]; then
                cmake -B "$SRC_DIR/build" -S "$SRC_DIR" \
                    -DCMAKE_BUILD_TYPE=Release \
                    -DLLAMA_BUILD_TESTS=OFF \
                    -DLLAMA_BUILD_EXAMPLES=OFF \
                    -DLLAMA_BUILD_SERVER=ON \
                    -DLLAMA_CURL=OFF

                cmake --build "$SRC_DIR/build" --target llama-server -j2
                if [ -f "$SRC_DIR/build/bin/llama-server" ]; then
                    mkdir -p "$PROJECT_DIR/bin"
                    cp "$SRC_DIR/build/bin/llama-server" "$PROJECT_DIR/bin/llama-server"
                    chmod +x "$PROJECT_DIR/bin/llama-server"
                    INSTALLED=1
                fi
            fi
        fi
    fi
fi

# 3. Verifikasi Eksekusi Binary Nyata Sebelum Melanjutkan
LLAMA_EXEC=$(find_llama_server 2>/dev/null || true)
if [ -z "$LLAMA_EXEC" ] || [ ! -x "$LLAMA_EXEC" ]; then
    echo -e "${RED}[GAGAL KRITIS] Binary llama-server tidak berhasil dipasang.${NC}"
    echo "Harap pastikan koneksi internet aktif untuk mengunduh paket resmi."
    exit 1
fi

if ! test_binary_executable "$LLAMA_EXEC"; then
    echo -e "${RED}[GAGAL KRITIS] Binary $LLAMA_EXEC ditemukan tetapi tidak dapat dieksekusi oleh OS Android Bionic.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Binary tervalidasi dan siap digunakan: $LLAMA_EXEC${NC}"

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
