#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# SI BONTOT — Official AI Model Downloader (Qwen 0.5B Instruct GGUF)
# Sumber: 100% Resmi Alibaba Cloud Qwen (Hugging Face) | Biaya Rp0 | Tanpa CC
# ==============================================================================

PROJECT_DIR="${1:-$HOME/wa-bontot}"
MODELS_DIR="$PROJECT_DIR/models"
mkdir -p "$MODELS_DIR"

MODEL_NAME="qwen2.5-0.5b-instruct-q4_k_m.gguf"
MODEL_PATH="$MODELS_DIR/$MODEL_NAME"

# URL Resmi Hugging Face (Alibaba Qwen Official Repo)
OFFICIAL_URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
EXPECTED_MIN_BYTES=390000000 # ~398 MB

echo "=== MENGUNDUH MODEL AI RESMI (QWEN 2.5 0.5B INSTRUCT) ==="
echo "Sumber: $OFFICIAL_URL"
echo "Target: $MODEL_PATH"

if [ -f "$MODEL_PATH" ]; then
    CURRENT_SIZE=$(wc -c < "$MODEL_PATH" 2>/dev/null || echo 0)
    if [ "$CURRENT_SIZE" -gt "$EXPECTED_MIN_BYTES" ]; then
        echo "✔ Model AI sudah terpasang lengkap ($(du -h "$MODEL_PATH" | cut -f1)). Melewati unduhan."
        exit 0
    else
        echo "Berkas model sebelumnya tidak lengkap. Melanjutkan unduhan..."
    fi
fi

# Unduh dengan curl resume (-C -) dan follow redirect (-L)
curl -L -C - --progress-bar -o "$MODEL_PATH" "$OFFICIAL_URL"

FINAL_SIZE=$(wc -c < "$MODEL_PATH" 2>/dev/null || echo 0)
if [ "$FINAL_SIZE" -gt "$EXPECTED_MIN_BYTES" ]; then
    echo "✔ Model AI berhasil diunduh dan diverifikasi: $(du -h "$MODEL_PATH" | cut -f1)"
    exit 0
else
    echo "✖ Unduhan gagal atau ukuran berkas tidak sesuai ($FINAL_SIZE byte)."
    exit 1
fi
