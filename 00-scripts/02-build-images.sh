#!/usr/bin/env bash
# ==============================================================================
# Script: 02-build-images.sh
# Description: Builds custom Docker images baking the downloaded model weights
#              directly into vLLM / TEI containers for air-gapped deployment.
# Output Images:
#   - local-registry/vllm-nemotron:v1
#   - local-registry/vllm-gpt-oss:v1
#   - local-registry/vllm-laguna:v1
#   - local-registry/tei-nomic-embed:v1
# ==============================================================================

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="${BASE_DIR}/models-cache"
REGISTRY_PREFIX="${REGISTRY_PREFIX:-local-registry}"

echo -e "${BOLD}===================================================================${NC}"
echo -e "${BOLD}        AIR-GAPPED vLLM / TEI - MODEL IMAGE BUILDER                ${NC}"
echo -e "${BOLD}===================================================================${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR] Docker is not installed or not in PATH.${NC}"
    exit 1
fi

build_model_image() {
    local model_name="$1"
    local dockerfile_dir="$2"
    local cache_dir="$3"
    local image_tag="${REGISTRY_PREFIX}/${model_name}:v1"

    echo -e "\n${BOLD}--> Building image: ${image_tag}${NC}"
    echo -e "    Dockerfile: ${dockerfile_dir}/Dockerfile"
    echo -e "    Weights Cache: ${cache_dir}"

    if [ ! -d "${cache_dir}" ]; then
        echo -e "${RED}[ERROR] Model cache directory ${cache_dir} does not exist!${NC}"
        echo "Run ./00-scripts/01-download-weights.sh first."
        exit 1
    fi

    # Create temporary build context linking weights directory
    local build_ctx
    build_ctx="$(mktemp -d)"
    trap 'rm -rf "${build_ctx}"' EXIT

    cp "${dockerfile_dir}/Dockerfile" "${build_ctx}/Dockerfile"
    cp -r "${cache_dir}" "${build_ctx}/model-weights"

    docker build \
        --file "${build_ctx}/Dockerfile" \
        --tag "${image_tag}" \
        "${build_ctx}"

    rm -rf "${build_ctx}"
    trap - EXIT

    echo -e "${GREEN}[OK] Image built successfully: ${image_tag}${NC}"
}

# 1. Nemotron 3.5 Lightning (vLLM)
build_model_image \
    "vllm-nemotron" \
    "${BASE_DIR}/03-pkg-models-spokes/model-nemotron-3.5" \
    "${MODELS_DIR}/nemotron-3.5"

# 2. GPT OSS 120B (vLLM FP8)
build_model_image \
    "vllm-gpt-oss" \
    "${BASE_DIR}/03-pkg-models-spokes/model-gpt-oss-120b" \
    "${MODELS_DIR}/gpt-oss-120b"

# 3. Laguna XS 2.1 (vLLM 256k)
build_model_image \
    "vllm-laguna" \
    "${BASE_DIR}/03-pkg-models-spokes/model-laguna-xs" \
    "${MODELS_DIR}/laguna-xs"

# 4. Nomic Embed Text v1.5 (TEI)
build_model_image \
    "tei-nomic-embed" \
    "${BASE_DIR}/03-pkg-models-spokes/model-nomic-embed" \
    "${MODELS_DIR}/nomic-embed"

echo -e "\n${BOLD}===================================================================${NC}"
echo -e "${GREEN}[SUCCESS] All 4 model container images built successfully!${NC}"
echo -e "Images available locally:"
docker images | grep -E "${REGISTRY_PREFIX}/(vllm-|tei-)" || true
echo -e "\nNext step: Run ./00-scripts/03-create-zarf-packages.sh to build Zarf bundles."
echo -e "${BOLD}===================================================================${NC}"
