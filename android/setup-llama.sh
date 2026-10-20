#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Native Llama Engine Installer (Android ARM64 / Termux)
# Biaya: Rp0 | 100% Bebas Kartu Kredit | Tanpa PRoot (Native C++ ARM64)
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
        "$PREFIX/bin/llama-server" \
        "/data/data/com.termux/files/usr/bin/llama-server" \
        "$PROJECT_DIR/bin/llama-server" \
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
    [ -n "$bin_path" ] && [ -x "$bin_path" ] && ("$bin_path" -h >/dev/null 2>&1 || "$bin_path" --version >/dev/null 2>&1)
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

# 2. Cek apakah llama-server sudah terpasang dan dapat dieksekusi
EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
if [ -n "$EXISTING_BIN" ] && test_binary_executable "$EXISTING_BIN"; then
    echo -e "${GREEN}✔ Binary llama-server fungsional sudah terpasang di: $EXISTING_BIN${NC}"
else
    echo -e "\n${YELLOW}[Metode 1] Mengaktifkan Termux User Repository (tur-repo) dan memasang llama-cpp...${NC}"
    echo "Catatan: Paket llama-cpp di Termux resmi dikelola oleh tur-repo."

    # Pastikan tur-repo terpasang untuk menyediakan llama-cpp
    pkg install -y tur-repo < /dev/null 2>&1 || true
    pkg update -y < /dev/null 2>&1 || true
    pkg install -y llama-cpp < /dev/null 2>&1 || true

    EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
    if [ -n "$EXISTING_BIN" ] && test_binary_executable "$EXISTING_BIN"; then
        echo -e "${GREEN}✔ Paket llama-cpp berhasil dipasang via package manager Termux (tur-repo).${NC}"
    else
        echo -e "\n${YELLOW}[Metode 2] Paket pkg tur-repo belum tersedia di mirror aktif.${NC}"
        echo "Mempersiapkan kompilasi C++ native resmi ggml-org/llama.cpp (ARM64 Optimized)..."

        # Install compiler toolchain
        pkg update -y < /dev/null 2>&1 || true
        pkg install -y git cmake clang make libandroid-spawn < /dev/null 2>&1 || true

        SRC_DIR="$HOME/llama.cpp"
        if [ ! -d "$SRC_DIR" ]; then
            echo "Mengunduh kode sumber resmi ggml-org/llama.cpp..."
            git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$SRC_DIR" < /dev/null 2>&1 || {
                echo -e "${RED}[GAGAL] Gagal mengunduh repositori llama.cpp. Periksa koneksi internet.${NC}"
                exit 1
            }
        else
            echo "Repositori $SRC_DIR sudah ada, melanjutkan konfigurasi build..."
        fi

        echo "Mengonfigurasi build CMake untuk target llama-server..."
        cmake -B "$SRC_DIR/build" -S "$SRC_DIR" \
            -DCMAKE_BUILD_TYPE=Release \
            -DLLAMA_BUILD_TESTS=OFF \
            -DLLAMA_BUILD_EXAMPLES=OFF \
            -DLLAMA_BUILD_SERVER=ON \
            -DLLAMA_CURL=OFF

        # Di smartphone RAM 4GB, batasi ke 2 thread agar tidak memicu OOM Killer
        BUILD_JOBS=2
        TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 4000000)
        if [ "$TOTAL_RAM_KB" -lt 3000000 ]; then
            BUILD_JOBS=1
        fi

        echo "Membangun binary llama-server (menggunakan $BUILD_JOBS parallel jobs untuk stabilitas RAM)..."
        cmake --build "$SRC_DIR/build" --target llama-server -j"$BUILD_JOBS"

        mkdir -p "$PROJECT_DIR/bin"
        if [ -f "$SRC_DIR/build/bin/llama-server" ]; then
            cp "$SRC_DIR/build/bin/llama-server" "$PROJECT_DIR/bin/llama-server"
            chmod +x "$PROJECT_DIR/bin/llama-server"
            if [ -n "$PREFIX" ] && [ -d "$PREFIX/bin" ]; then
                cp "$SRC_DIR/build/bin/llama-server" "$PREFIX/bin/llama-server" 2>/dev/null || true
                chmod +x "$PREFIX/bin/llama-server" 2>/dev/null || true
            fi
            echo -e "${GREEN}✔ Kompilasi llama-server berhasil selesai!${NC}"
        else
            echo -e "${RED}[GAGAL KRITIS] Kompilasi selesai tetapi binary llama-server tidak terbentuk.${NC}"
            exit 1
        fi
    fi
fi

# 3. Verifikasi Eksekusi Binary Nyata
LLAMA_EXEC=$(find_llama_server 2>/dev/null || true)
if [ -z "$LLAMA_EXEC" ] || [ ! -x "$LLAMA_EXEC" ]; then
    echo -e "${RED}[GAGAL KRITIS] Binary llama-server tidak ditemukan di path mana pun.${NC}"
    exit 1
fi

if ! test_binary_executable "$LLAMA_EXEC"; then
    echo -e "${RED}[GAGAL KRITIS] Binary $LLAMA_EXEC ditemukan tetapi gagal dieksekusi (exit code non-zero).${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Binary tervalidasi dan siap dieksekusi: $LLAMA_EXEC${NC}"

# 4. Verifikasi Berkas Model GGUF
echo -e "\n${YELLOW}Memeriksa berkas model AI di $PROJECT_DIR/models/...${NC}"
mkdir -p "$PROJECT_DIR/models"
MODEL_FILE=$(find_model_file 2>/dev/null || true)

if [ -n "$MODEL_FILE" ] && [ -f "$MODEL_FILE" ]; then
    MODEL_SIZE_STR=$(du -h "$MODEL_FILE" | cut -f1)
    echo -e "${GREEN}✔ Model GGUF ditemukan: $(basename "$MODEL_FILE") [${MODEL_SIZE_STR}].${NC}"
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

# 5. Restart Layanan Bot untuk Mengaktifkan Engine
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
