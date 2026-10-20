#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Native Llama Engine Installer (Android ARM64 / Termux)
# Biaya: Rp0 | 100% Bebas Kartu Kredit | Tanpa PRoot (Native C++ ARM64)
# ==============================================================================

set -e

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
    echo -e "${RED}[GAGAL] llama-server membutuhkan CPU ARM64 (64-bit).${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Arsitektur ARM64 terverifikasi.${NC}"

find_llama_server() {
    if command -v llama-server >/dev/null 2>&1; then
        command -v llama-server
        return 0
    fi
    for p in \
        "/data/data/com.termux/files/usr/bin/llama-server" \
        "$PREFIX/bin/llama-server" \
        "$HOME/llama.cpp/build/bin/llama-server" \
        "$HOME/llama.cpp/llama-server" \
        "$PROJECT_DIR/bin/llama-server"; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

# 2. Cek apakah llama-server sudah terpasang
EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
if [ -n "$EXISTING_BIN" ] && [ -x "$EXISTING_BIN" ]; then
    echo -e "${GREEN}✔ Binary llama-server sudah terpasang di: $EXISTING_BIN${NC}"
else
    echo -e "\n${YELLOW}[Metode 1] Mencoba instalasi cepat paket resmi Termux (llama-cpp)...${NC}"
    INSTALL_OK=0
    if pkg install -y llama-cpp < /dev/null 2>&1; then
        EXISTING_BIN=$(find_llama_server 2>/dev/null || true)
        if [ -n "$EXISTING_BIN" ] && [ -x "$EXISTING_BIN" ]; then
            echo -e "${GREEN}✔ Paket llama-cpp berhasil dipasang via package manager Termux.${NC}"
            INSTALL_OK=1
        fi
    fi

    # Jika Metode 1 tidak menemukan binary, gunakan Metode 2 (Kompilasi C++ Native)
    if [ "$INSTALL_OK" -eq 0 ]; then
        echo -e "\n${YELLOW}[Metode 2] Paket pkg tidak tersedia di mirror. Membangun llama-server dari sumber resmi...${NC}"
        echo "Memasang toolchain kompilasi C++ (CMake, Clang, Make, libandroid-spawn)..."
        pkg update -y < /dev/null || true
        pkg install -y git cmake clang make libandroid-spawn < /dev/null

        SRC_DIR="$HOME/llama.cpp"
        if [ ! -d "$SRC_DIR" ]; then
            echo "Mengunduh kode sumber resmi ggml-org/llama.cpp..."
            git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$SRC_DIR" < /dev/null
        else
            echo "Memperbarui repositori $SRC_DIR..."
            (cd "$SRC_DIR" && git pull < /dev/null 2>/dev/null || true)
        fi

        echo "Mengonfigurasi build CMake untuk target llama-server..."
        cmake -B "$SRC_DIR/build" -S "$SRC_DIR" \
            -DCMAKE_BUILD_TYPE=Release \
            -DLLAMA_BUILD_TESTS=OFF \
            -DLLAMA_BUILD_EXAMPLES=OFF \
            -DLLAMA_BUILD_SERVER=ON

        N_CORES=$(nproc 2>/dev/null || echo 2)
        echo "Membangun binary llama-server (menggunakan $N_CORES core CPU)..."
        cmake --build "$SRC_DIR/build" --target llama-server -j"$N_CORES"

        mkdir -p "$PROJECT_DIR/bin"
        if [ -f "$SRC_DIR/build/bin/llama-server" ]; then
            cp "$SRC_DIR/build/bin/llama-server" "$PROJECT_DIR/bin/llama-server"
            chmod +x "$PROJECT_DIR/bin/llama-server"
            # Coba salin ke PREFIX/bin jika memungkinkan
            if [ -n "$PREFIX" ] && [ -d "$PREFIX/bin" ]; then
                cp "$SRC_DIR/build/bin/llama-server" "$PREFIX/bin/llama-server" 2>/dev/null || true
                chmod +x "$PREFIX/bin/llama-server" 2>/dev/null || true
            fi
            echo -e "${GREEN}✔ Kompilasi llama-server berhasil selesai!${NC}"
        else
            echo -e "${RED}[GAGAL] Kompilasi selesai tetapi binary llama-server tidak ditemukan.${NC}"
            exit 1
        fi
    fi
fi

# 3. Verifikasi Eksekusi Binary
LLAMA_EXEC=$(find_llama_server 2>/dev/null || true)
if [ -z "$LLAMA_EXEC" ] || [ ! -x "$LLAMA_EXEC" ]; then
    echo -e "${RED}[GAGAL KRITIS] Binary llama-server tidak ditemukan setelah proses instalasi.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Binary tervalidasi: $LLAMA_EXEC${NC}"

# 4. Verifikasi Berkas Model GGUF
echo -e "\n${YELLOW}Memeriksa berkas model AI di $PROJECT_DIR/models/...${NC}"
mkdir -p "$PROJECT_DIR/models"
MODEL_FILE=$(ls -S "$PROJECT_DIR/models/"*.gguf 2>/dev/null | head -n 1 || true)

if [ -n "$MODEL_FILE" ] && [ -f "$MODEL_FILE" ]; then
    MODEL_SIZE_STR=$(du -h "$MODEL_FILE" | cut -f1)
    echo -e "${GREEN}✔ Model GGUF ditemukan: $(basename "$MODEL_FILE") [${MODEL_SIZE_STR}].${NC}"
else
    echo "Berkas model GGUF belum ditemukan di $PROJECT_DIR/models/."
    echo "Mengunduh model resmi Qwen 2.5 0.5B Instruct GGUF..."
    bash "$PROJECT_DIR/android/download-ai-model.sh" "$PROJECT_DIR"
    MODEL_FILE=$(ls -S "$PROJECT_DIR/models/"*.gguf 2>/dev/null | head -n 1 || true)
fi

# 5. Restart Layanan Bot untuk Mengaktifkan Engine
echo -e "\n${CYAN}Memulai ulang layanan SI BONTOT untuk memuat Llama Engine...${NC}"
bash "$PROJECT_DIR/android/start-service.sh" restart

# 6. Berikan Jeda Singkat agar Model Selesai Dimuat ke RAM
echo "Menunggu Llama Engine memuat model ke memori (5 detik)..."
sleep 5

# 7. Jalankan Uji Inferensi HTTP Nyata
echo -e "\n${CYAN}Menjalankan uji inferensi HTTP nyata...${NC}"
bash "$PROJECT_DIR/android/test-inference.sh" "$PROJECT_DIR"
