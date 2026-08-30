#!/usr/bin/env bash
# ==============================================================================
# Script: 01-download-weights.sh
# Description: Downloads model weights from Hugging Face for air-gapped baking.
# Target Models:
#   1. Nemotron 3.5 Lightning (30B MoE, Hermes tool calling)
#   2. GPT OSS 120B (FP8 Quantized MoE)
#   3. Laguna XS 2.1 (256k Long-Context)
#   4. Nomic Embed Text v1.5 (High-efficiency embeddings)
# Prerequisites: huggingface-cli installed, HF_TOKEN set if accessing gated repos.
# ==============================================================================

set -euo pipefail

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="${BASE_DIR}/models-cache"

echo -e "${BOLD}===================================================================${NC}"
echo -e "${BOLD}     AIR-GAPPED vLLM / GITLAB DUO - MODEL WEIGHT DOWNLOADER        ${NC}"
echo -e "${BOLD}===================================================================${NC}"

# Check prerequisites
if ! command -v huggingface-cli &> /dev/null; then
    echo -e "${RED}[ERROR] huggingface-cli is not installed.${NC}"
    echo "Install it via: pip install -U 'huggingface_hub[cli]'"
    exit 1
fi

mkdir -p "${MODELS_DIR}"
echo -e "${GREEN}[INFO] Target storage directory: ${MODELS_DIR}${NC}"

# Optional HF Token warning
if [ -z "${HF_TOKEN:-}" ]; then
    echo -e "${YELLOW}[WARNING] HF_TOKEN environment variable is not set. Gated models may fail.${NC}"
fi

# Function to download model weights safely
download_model() {
    local model_id="$1"
    local target_dir="$2"
    local exclude_patterns="${3:---exclude '*.pt' '*.bin'}"

    echo -e "\n${BOLD}--> Downloading: ${model_id}${NC}"
    echo -e "    Destination: ${target_dir}"
    
    mkdir -p "${target_dir}"
    
    huggingface-cli download "${model_id}" \
        --local-dir "${target_dir}" \
        --local-dir-use-symlinks False \
        --resume-download \
        ${exclude_patterns}

    echo -e "${GREEN}[OK] Download complete for ${model_id}${NC}"
}

# ------------------------------------------------------------------------------
# 1. Nemotron 3.5 Lightning (30B MoE)
# ------------------------------------------------------------------------------
NEMOTRON_REPO="nvidia/Nemotron-3.5-Lightning-30B-A3B-W4A16"
NEMOTRON_DIR="${MODELS_DIR}/nemotron-3.5"
download_model "${NEMOTRON_REPO}" "${NEMOTRON_DIR}"

# ------------------------------------------------------------------------------
# 2. GPT OSS 120B (FP8 Quantized MoE)
# ------------------------------------------------------------------------------
GPT_OSS_REPO="gpt-oss/gpt-oss-120b-fp8"
GPT_OSS_DIR="${MODELS_DIR}/gpt-oss-120b"
download_model "${GPT_OSS_REPO}" "${GPT_OSS_DIR}"

# ------------------------------------------------------------------------------
# 3. Laguna XS 2.1 (256k Context Window)
# ------------------------------------------------------------------------------
LAGUNA_REPO="laguna/laguna-xs-2.1"
LAGUNA_DIR="${MODELS_DIR}/laguna-xs"
download_model "${LAGUNA_REPO}" "${LAGUNA_DIR}"

# ------------------------------------------------------------------------------
# 4. Nomic Embed Text v1.5
# ------------------------------------------------------------------------------
NOMIC_REPO="nomic-ai/nomic-embed-text-v1.5"
NOMIC_DIR="${MODELS_DIR}/nomic-embed"
download_model "${NOMIC_REPO}" "${NOMIC_DIR}"

echo -e "\n${BOLD}===================================================================${NC}"
echo -e "${GREEN}[SUCCESS] All model weights downloaded successfully into ${MODELS_DIR}${NC}"
echo -e "Next step: Run ./00-scripts/02-build-images.sh to bake models into containers."
echo -e "${BOLD}===================================================================${NC}"
