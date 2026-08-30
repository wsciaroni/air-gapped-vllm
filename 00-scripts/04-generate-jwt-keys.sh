#!/usr/bin/env bash
# ==============================================================================
# Script: 04-generate-jwt-keys.sh
# Description: Generates RSA 2048-bit cryptographic keypair for GitLab Duo
#              Workflow Agentic JWT authentication between GitLab Monolith and
#              the GitLab AI Gateway.
# Outputs:
#   - duo_workflow_jwt.key (Private Signing Key for GitLab)
#   - duo_workflow_validation.key (Public Validation Key for AI Gateway)
#   - duo-jwt-secrets.yaml (Kubernetes Secret manifest for air-gap apply)
# ==============================================================================

set -euo pipefail

BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYS_DIR="${BASE_DIR}/keys"

echo -e "${BOLD}===================================================================${NC}"
echo -e "${BOLD}     GITLAB DUO WORKFLOW - RSA JWT KEYPAIR GENERATOR               ${NC}"
echo -e "${BOLD}===================================================================${NC}"

if ! command -v openssl &> /dev/null; then
    echo -e "${RED}[ERROR] openssl is not installed or not in PATH.${NC}"
    exit 1
fi

mkdir -p "${KEYS_DIR}"
chmod 700 "${KEYS_DIR}"

PRIVATE_KEY="${KEYS_DIR}/duo_workflow_jwt.key"
PUBLIC_KEY="${KEYS_DIR}/duo_workflow_validation.key"
SECRETS_MANIFEST="${KEYS_DIR}/duo-jwt-secrets.yaml"

echo -e "${BOLD}--> Generating 2048-bit RSA Private Signing Key...${NC}"
openssl genrsa -out "${PRIVATE_KEY}" 2048
chmod 600 "${PRIVATE_KEY}"
echo -e "${GREEN}[OK] Private key created: ${PRIVATE_KEY}${NC}"

echo -e "\n${BOLD}--> Extracting Public Validation Key...${NC}"
openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}"
chmod 644 "${PUBLIC_KEY}"
echo -e "${GREEN}[OK] Public validation key created: ${PUBLIC_KEY}${NC}"

echo -e "\n${BOLD}--> Generating Kubernetes Secret Manifest (${SECRETS_MANIFEST})...${NC}"

# Base64 encode without line breaks
if [[ "$OSTYPE" == "darwin"* ]]; then
    B64_PRIVATE=$(base64 -i "${PRIVATE_KEY}")
    B64_PUBLIC=$(base64 -i "${PUBLIC_KEY}")
else
    B64_PRIVATE=$(base64 -w 0 "${PRIVATE_KEY}")
    B64_PUBLIC=$(base64 -w 0 "${PUBLIC_KEY}")
fi

cat <<EOF > "${SECRETS_MANIFEST}"
---
# Secret for GitLab Rails / Sidekiq to sign Duo Workflow requests
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-duo-workflow-jwt-signing-key
  namespace: gitlab
  labels:
    app.kubernetes.io/part-of: gitlab
    app.kubernetes.io/component: duo-workflow
type: Opaque
data:
  duo_workflow_jwt.key: ${B64_PRIVATE}

---
# Secret for AI Gateway to validate incoming Duo Workflow requests
apiVersion: v1
kind: Secret
metadata:
  name: ai-gateway-duo-workflow-jwt-validation-key
  namespace: ai-gateway
  labels:
    app.kubernetes.io/part-of: ai-gateway
    app.kubernetes.io/component: auth
type: Opaque
data:
  signing_key.pem: ${B64_PRIVATE}
  validation_key.pem: ${B64_PUBLIC}
EOF

chmod 600 "${SECRETS_MANIFEST}"

echo -e "${GREEN}[OK] Secret manifest generated successfully.${NC}"
echo -e "\n${BOLD}===================================================================${NC}"
echo -e "${GREEN}[SUCCESS] Duo Workflow RSA Keys & Secrets are ready!${NC}"
echo -e "Files created in ${KEYS_DIR}:"
echo -e "  - duo_workflow_jwt.key"
echo -e "  - duo_workflow_validation.key"
echo -e "  - duo-jwt-secrets.yaml"
echo -e "${BOLD}===================================================================${NC}"
