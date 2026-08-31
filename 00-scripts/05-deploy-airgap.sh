#!/usr/bin/env bash
# ==============================================================================
# Script: 05-deploy-airgap.sh
# Description: Executes the sequential deployment of the air-gapped GitLab 18
#              Duo Self-Hosted & Autonomous Agent stack using Zarf into VMware
#              vSphere with Tanzu.
#
# Modular Execution Order:
#   1. Cluster Pre-flight & Namespaces
#   2. Duo Workflow RSA JWT Secrets
#   3. Zarf Package 01A: MinIO S3 Object Storage
#   4. Zarf Package 01B: GitLab Duo AI Gateway (FIPS)
#   5. Zarf Package 01C: GitLab 18 Core Monolith (FIPS)
#   6. Zarf Package 02:  vLLM Semantic Router Hub
#   7. Zarf Package 03:  Model Spokes (Nemotron, GPT OSS, Laguna XS, Nomic)
#   8. Zarf Package 04:  Agent Sandbox & Zero-Trust Network Policies
# ==============================================================================

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${BASE_DIR}/dist"
KEYS_DIR="${BASE_DIR}/keys"

echo -e "${BOLD}===================================================================${NC}"
echo -e "${BOLD}   AIR-GAPPED GITLAB DUO & vLLM STACK - TANZU DEPLOYMENT PIPELINE  ${NC}"
echo -e "${BOLD}===================================================================${NC}"

# Pre-flight checks
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR] kubectl is not installed or not configured.${NC}"
    exit 1
fi

if ! command -v zarf &> /dev/null; then
    echo -e "${RED}[ERROR] zarf CLI is not installed or not in PATH.${NC}"
    exit 1
fi

echo -e "${BLUE}--> Checking Kubernetes connection...${NC}"
kubectl cluster-info > /dev/null 2>&1 || {
    echo -e "${RED}[ERROR] Cannot communicate with Tanzu Kubernetes Cluster! Check KUBECONFIG.${NC}"
    exit 1
}
echo -e "${GREEN}[OK] Connected to Kubernetes cluster.${NC}"

# Step 0: Ensure Namespaces exist
echo -e "\n${BLUE}--> Creating isolated namespaces...${NC}"
for ns in gitlab minio ai-gateway inference agent-sandbox; do
    kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done
echo -e "${GREEN}[OK] Namespaces verified: gitlab, minio, ai-gateway, inference, agent-sandbox${NC}"

# Step 1: Initialize Zarf if needed
if ! kubectl get namespace zarf > /dev/null 2>&1; then
    echo -e "\n${BLUE}--> Initializing Zarf on the Tanzu cluster (Internal Registry & Git Server)...${NC}"
    zarf init --confirm
    echo -e "${GREEN}[OK] Zarf initialized.${NC}"
else
    echo -e "${GREEN}[INFO] Zarf is already initialized in the cluster.${NC}"
fi

# Step 2: Apply Duo Workflow Secrets if present
if [ -f "${KEYS_DIR}/duo-jwt-secrets.yaml" ]; then
    echo -e "\n${BLUE}--> Applying Duo Workflow JWT Secrets...${NC}"
    kubectl apply -f "${KEYS_DIR}/duo-jwt-secrets.yaml"
    echo -e "${GREEN}[OK] Duo Workflow secrets deployed.${NC}"
else
    echo -e "${YELLOW}[WARNING] ${KEYS_DIR}/duo-jwt-secrets.yaml not found. Generating now...${NC}"
    "${BASE_DIR}/00-scripts/04-generate-jwt-keys.sh"
    kubectl apply -f "${KEYS_DIR}/duo-jwt-secrets.yaml"
fi

# Helper function to deploy zarf package by pattern
deploy_zarf_pkg() {
    local pattern="$1"
    local desc="$2"
    local src_fallback="${3:-}"
    
    echo -e "\n${BOLD}${BLUE}===================================================================${NC}"
    echo -e "${BOLD}--> Deploying: ${desc}${NC}"
    echo -e "${BOLD}${BLUE}===================================================================${NC}"

    local pkg_file=""
    if [ -d "${DIST_DIR}" ]; then
        pkg_file=$(find "${DIST_DIR}" -maxdepth 1 -name "zarf-package-${pattern}*.tar.zst" 2>/dev/null | head -n 1 || true)
    fi

    if [ -n "${pkg_file}" ] && [ -f "${pkg_file}" ]; then
        echo -e "Deploying bundle from dist/: ${pkg_file}"
        zarf package deploy "${pkg_file}" --confirm
        echo -e "${GREEN}[OK] Deployed ${desc}${NC}"
        return
    fi

    # Fallback to local source directory or local .tar.zst
    if [ -n "${src_fallback}" ] && [ -d "${src_fallback}" ]; then
        local local_pkg
        local_pkg=$(find "${src_fallback}" -maxdepth 1 -name "zarf-package-${pattern}*.tar.zst" 2>/dev/null | head -n 1 || true)
        if [ -n "${local_pkg}" ] && [ -f "${local_pkg}" ]; then
            echo -e "Deploying local bundle: ${local_pkg}"
            zarf package deploy "${local_pkg}" --confirm
            echo -e "${GREEN}[OK] Deployed ${desc}${NC}"
            return
        elif [ -f "${src_fallback}/zarf.yaml" ]; then
            echo -e "Deploying directly from source: ${src_fallback}"
            pushd "${src_fallback}" > /dev/null
            zarf package deploy . --confirm
            popd > /dev/null
            echo -e "${GREEN}[OK] Deployed ${desc}${NC}"
            return
        fi
    fi

    echo -e "${YELLOW}[SKIP] Package for ${pattern} not found. Skipping.${NC}"
}

# ------------------------------------------------------------------------------
# 3. Deploy Core Infrastructure (MinIO Storage, AI Gateway, GitLab Monolith)
# ------------------------------------------------------------------------------
deploy_zarf_pkg "minio-storage"    "MinIO S3 Object Storage"              "${BASE_DIR}/01-pkg-gitlab-core/minio"
deploy_zarf_pkg "ai-gateway-fips" "GitLab Duo AI Gateway (FIPS)"         "${BASE_DIR}/01-pkg-gitlab-core/ai-gateway"
deploy_zarf_pkg "gitlab-core"     "GitLab 18 Core Monolith (FIPS)"       "${BASE_DIR}/01-pkg-gitlab-core/gitlab"

# ------------------------------------------------------------------------------
# 4. Deploy vLLM Semantic Router Hub
# ------------------------------------------------------------------------------
deploy_zarf_pkg "vllm-router-hub" "vLLM Semantic Router (Hub Gateway)"   "${BASE_DIR}/02-pkg-vllm-router-hub"

# ------------------------------------------------------------------------------
# 5. Deploy Model Spokes
# ------------------------------------------------------------------------------
deploy_zarf_pkg "model-nemotron-3-5" "Nemotron 3.5 Spoke (30B MoE, Hermes)" "${BASE_DIR}/03-pkg-models-spokes/model-nemotron-3.5"
deploy_zarf_pkg "model-gpt-oss-120b" "GPT OSS 120B Spoke (FP8 MoE Reasoning)" "${BASE_DIR}/03-pkg-models-spokes/model-gpt-oss-120b"
deploy_zarf_pkg "model-laguna-xs"    "Laguna XS 2.1 Spoke (256k Context Model)" "${BASE_DIR}/03-pkg-models-spokes/model-laguna-xs"
deploy_zarf_pkg "model-nomic-embed"  "Nomic Embed Spoke (TEI Embeddings)"      "${BASE_DIR}/03-pkg-models-spokes/model-nomic-embed"

# ------------------------------------------------------------------------------
# 6. Deploy Zero-Trust Agent Sandbox & Runner
# ------------------------------------------------------------------------------
deploy_zarf_pkg "agent-sandbox" "Agent Sandbox Runner & Network Policies" "${BASE_DIR}/04-pkg-agent-sandbox"

# ------------------------------------------------------------------------------
# Status Verification
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}===================================================================${NC}"
echo -e "${BOLD}                POST-DEPLOYMENT CLUSTER STATUS                     ${NC}"
echo -e "${BOLD}===================================================================${NC}"

echo -e "\n${BLUE}--> Checking GPU Pod Allocation in 'inference' namespace:${NC}"
kubectl get pods -n inference -o wide 2>/dev/null || true

echo -e "\n${BLUE}--> Checking MinIO, GitLab & AI Gateway Pods:${NC}"
kubectl get pods -n minio 2>/dev/null || true
kubectl get pods -n gitlab 2>/dev/null || true
kubectl get pods -n ai-gateway 2>/dev/null || true

echo -e "\n${BLUE}--> Checking Agent Sandbox Runner Pods:${NC}"
kubectl get pods -n agent-sandbox 2>/dev/null || true

echo -e "\n${BOLD}===================================================================${NC}"
echo -e "${GREEN}[SUCCESS] Air-Gapped GitLab Duo & Autonomous Agent Stack Deployed!${NC}"
echo -e "Access URLs:"
echo -e "  - GitLab UI: https://gitlab.internal.local"
echo -e "  - MinIO Console: https://minio.gitlab.internal.local (or port 9001)"
echo -e "  - AI Gateway: http://ai-gateway.ai-gateway.svc.cluster.local:5052/v1"
echo -e "  - vLLM Semantic Router: http://vllm-router.inference.svc.cluster.local:8000/v1"
echo -e "${BOLD}===================================================================${NC}"
