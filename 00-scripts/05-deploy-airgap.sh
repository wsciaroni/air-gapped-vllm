#!/usr/bin/env bash
# ==============================================================================
# Script: 05-deploy-airgap.sh
# Description: Executes the sequential deployment of the air-gapped GitLab 18
#              Duo Self-Hosted & Autonomous Agent stack using Zarf into VMware
#              vSphere with Tanzu.
#
# Execution Order:
#   1. Cluster Pre-flight & Namespaces
#   2. Duo Workflow JWT Secrets
#   3. Zarf Package 01: GitLab Core + MinIO + AI Gateway (FIPS)
#   4. Zarf Package 02: vLLM Semantic Router Hub
#   5. Zarf Package 03: Model Spokes (Nemotron, GPT OSS 120B, Laguna XS, Nomic)
#   6. Zarf Package 04: Agent Sandbox & Zero-Trust Network Policies
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
    
    echo -e "\n${BOLD}${BLUE}===================================================================${NC}"
    echo -e "${BOLD}--> Deploying: ${desc}${NC}"
    echo -e "${BOLD}${BLUE}===================================================================${NC}"

    local pkg_file
    pkg_file=$(find "${DIST_DIR}" -maxdepth 1 -name "zarf-package-${pattern}*.tar.zst" | head -n 1)

    if [ -z "${pkg_file}" ] || [ ! -f "${pkg_file}" ]; then
        # Check if running directly from component folder
        echo -e "${YELLOW}[INFO] Pre-built package not found in ${DIST_DIR}. Checking local source...${NC}"
        local src_dir="${BASE_DIR}/${pattern}"
        if [ -d "${src_dir}" ]; then
            pushd "${src_dir}" > /dev/null
            zarf package deploy . --confirm
            popd > /dev/null
            return
        else
            echo -e "${RED}[ERROR] Cannot find Zarf package or source for ${pattern}!${NC}"
            exit 1
        fi
    fi

    echo -e "Deploying bundle: ${pkg_file}"
    zarf package deploy "${pkg_file}" --confirm
    echo -e "${GREEN}[OK] Deployed ${desc}${NC}"
}

# ------------------------------------------------------------------------------
# 3. Deploy GitLab Core, MinIO & FIPS AI Gateway
# ------------------------------------------------------------------------------
deploy_zarf_pkg "gitlab-core" "GitLab 18 Core, MinIO, and FIPS AI Gateway"

# ------------------------------------------------------------------------------
# 4. Deploy vLLM Semantic Router Hub
# ------------------------------------------------------------------------------
deploy_zarf_pkg "vllm-router-hub" "vLLM Semantic Router (Hub Gateway)"

# ------------------------------------------------------------------------------
# 5. Deploy Model Spokes
# ------------------------------------------------------------------------------
deploy_zarf_pkg "model-nemotron-3.5" "Nemotron 3.5 Spoke (30B MoE, Hermes Tool Calling)"
deploy_zarf_pkg "model-gpt-oss-120b" "GPT OSS 120B Spoke (FP8 MoE Reasoning)"
deploy_zarf_pkg "model-laguna-xs"    "Laguna XS 2.1 Spoke (256k Context Model)"
deploy_zarf_pkg "model-nomic-embed"  "Nomic Embed Spoke (TEI Vector Embeddings)"

# ------------------------------------------------------------------------------
# 6. Deploy Zero-Trust Agent Sandbox & Runner
# ------------------------------------------------------------------------------
deploy_zarf_pkg "agent-sandbox" "Agent Sandbox Runner & Zero-Trust Network Policies"

# ------------------------------------------------------------------------------
# Status Verification
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}===================================================================${NC}"
echo -e "${BOLD}                POST-DEPLOYMENT CLUSTER STATUS                     ${NC}"
echo -e "${BOLD}===================================================================${NC}"

echo -e "\n${BLUE}--> Checking GPU Pod Allocation in 'inference' namespace:${NC}"
kubectl get pods -n inference -o wide

echo -e "\n${BLUE}--> Checking GitLab & AI Gateway Pods:${NC}"
kubectl get pods -n gitlab -l app.kubernetes.io/name=gitlab
kubectl get pods -n ai-gateway

echo -e "\n${BLUE}--> Checking Agent Sandbox Runner Pods:${NC}"
kubectl get pods -n agent-sandbox

echo -e "\n${BOLD}===================================================================${NC}"
echo -e "${GREEN}[SUCCESS] Air-Gapped GitLab Duo & Autonomous Agent Stack Deployed!${NC}"
echo -e "Access URLs:"
echo -e "  - GitLab UI: https://gitlab.internal.local"
echo -e "  - AI Gateway: http://ai-gateway.ai-gateway.svc.cluster.local:5052/v1"
echo -e "  - vLLM Semantic Router: http://vllm-router.inference.svc.cluster.local:8000/v1"
echo -e "${BOLD}===================================================================${NC}"
