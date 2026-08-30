#!/usr/bin/env bash
# ==============================================================================
# Script: 03-create-zarf-packages.sh
# Description: Creates modular Zarf packages for GitLab Core, vLLM Router Hub,
#              Inference Model Spokes, and Agent Sandbox.
#
# Flags:
#   --max-package-size 20000 : Splits packages >20GB into .part00X chunks
#                              for secure transport across air-gapped media.
#   --confirm                : Non-interactive automated build
#   --architecture amd64     : Target Tanzu VxRail architecture
# ==============================================================================

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${BASE_DIR}/dist"
MAX_PACKAGE_SIZE_MB="20000" # 20GB chunk threshold

echo -e "${BOLD}===================================================================${NC}"
echo -e "${BOLD}           ZARF AIR-GAP PACKAGE CREATION PIPELINE                 ${NC}"
echo -e "${BOLD}===================================================================${NC}"

if ! command -v zarf &> /dev/null; then
    echo -e "${RED}[ERROR] Zarf CLI is not installed or not in PATH.${NC}"
    echo "Install Zarf via: https://docs.zarf.dev/getting-started/install/"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"
echo -e "${GREEN}[INFO] Output directory: ${OUTPUT_DIR}${NC}"
echo -e "${GREEN}[INFO] Max chunk size: ${MAX_PACKAGE_SIZE_MB} MB (20 GB)${NC}\n"

create_zarf_package() {
    local package_dir="$1"
    local package_name="$2"

    echo -e "${BOLD}--> Creating Zarf Package: ${package_name}${NC}"
    echo -e "    Directory: ${package_dir}"

    pushd "${package_dir}" > /dev/null

    zarf package create . \
        --output-directory "${OUTPUT_DIR}" \
        --max-package-size "${MAX_PACKAGE_SIZE_MB}" \
        --architecture amd64 \
        --confirm

    popd > /dev/null
    echo -e "${GREEN}[OK] Created package for ${package_name}${NC}\n"
}

# ------------------------------------------------------------------------------
# 1. GitLab 18 Core + MinIO + AI Gateway FIPS Package
# ------------------------------------------------------------------------------
create_zarf_package "${BASE_DIR}/01-pkg-gitlab-core" "01-gitlab-core"

# ------------------------------------------------------------------------------
# 2. vLLM Semantic Router Hub Package
# ------------------------------------------------------------------------------
create_zarf_package "${BASE_DIR}/02-pkg-vllm-router-hub" "02-vllm-router-hub"

# ------------------------------------------------------------------------------
# 3. Model Inference Spokes
# ------------------------------------------------------------------------------
create_zarf_package "${BASE_DIR}/03-pkg-models-spokes/model-nemotron-3.5" "03-model-nemotron-3.5"
create_zarf_package "${BASE_DIR}/03-pkg-models-spokes/model-gpt-oss-120b" "03-model-gpt-oss-120b"
create_zarf_package "${BASE_DIR}/03-pkg-models-spokes/model-laguna-xs" "03-model-laguna-xs"
create_zarf_package "${BASE_DIR}/03-pkg-models-spokes/model-nomic-embed" "03-model-nomic-embed"

# ------------------------------------------------------------------------------
# 4. Zero-Trust Agent Sandbox & Runner Package
# ------------------------------------------------------------------------------
create_zarf_package "${BASE_DIR}/04-pkg-agent-sandbox" "04-agent-sandbox"

# ------------------------------------------------------------------------------
# Generate SHA256 Checksums
# ------------------------------------------------------------------------------
echo -e "${BOLD}--> Generating SHA-256 checksum manifest for transport verification...${NC}"
pushd "${OUTPUT_DIR}" > /dev/null
if command -v sha256sum &> /dev/null; then
    sha256sum zarf-package-*.tar.zst* > CHECKSUMS.sha256 || true
elif command -v shasum &> /dev/null; then
    shasum -a 256 zarf-package-*.tar.zst* > CHECKSUMS.sha256 || true
fi
popd > /dev/null

echo -e "\n${BOLD}===================================================================${NC}"
echo -e "${GREEN}[SUCCESS] All Zarf packages compiled and chunked in ${OUTPUT_DIR}!${NC}"
echo -e "Files generated:"
ls -lh "${OUTPUT_DIR}"
echo -e "\nNext step: Transfer ${OUTPUT_DIR} across the air gap and run ./00-scripts/05-deploy-airgap.sh."
echo -e "${BOLD}===================================================================${NC}"
