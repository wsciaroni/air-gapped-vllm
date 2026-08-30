# Air-Gapped GitLab 18 & Duo Self-Hosted on VMware vSphere with Tanzu

Production-grade, modular repository for deploying an air-gapped, FIPS-compliant **GitLab 18** environment with **GitLab Duo Self-Hosted** and **Autonomous Agentic Workflows** on **VMware vSphere with Tanzu** (Dell VxRail) using **Zarf** Hub-and-Spoke packaging.

---

## 1. Architecture Overview

```
                      +------------------------------------------+
                      |         VMware vSphere with Tanzu        |
                      |     8x VxRail Nodes (16x L40 GPUs)       |
                      +------------------------------------------+
                                           |
         +---------------------------------+---------------------------------+
         |                                 |                                 |
+------------------+             +-------------------+             +-------------------+
| Namespace: gitlab|             | Namespace: minio  |             | Namespace: ai-gw  |
| - GitLab 18 Core |<----------->| - MinIO Object    |<----------->| - FIPS AI Gateway |
|   (FIPS images)  |     S3      |   Store (vSAN)    |   Duo JWT   |   (Port 5052)     |
+------------------+             +-------------------+             +-------------------+
         ^                                                                   |
         | Git & API (80/443)                                    OpenAI /v1  |
         |                                                                   v
+-------------------+                                              +-------------------+
| Namespace: sandbox|                                              | Namespace: infer  |
| - Agent Runners   |--------------------------------------------->| - vLLM Router Hub |
| - Zero-Trust NetPol                                              +-------------------+
+-------------------+                                                        |
                                                                             +--> Nemotron 3.5 (TP=2, Hermes)
                                                                             +--> GPT OSS 120B (TP=2, FP8 MoE)
                                                                             +--> Laguna XS 2.1 (TP=2, 256k)
                                                                             +--> Nomic Embed (TEI Embeddings)
```

---

## 2. Directory Structure

```text
.
├── 00-scripts/
│   ├── 01-download-weights.sh          # Hugging Face CLI download commands for all 4 models
│   ├── 02-build-images.sh             # Docker build commands for local-registry images
│   ├── 03-create-zarf-packages.sh     # Zarf package create commands with chunking flags
│   ├── 04-generate-jwt-keys.sh        # OpenSSL script for Duo Workflow RSA keypair
│   └── 05-deploy-airgap.sh            # Sequential Zarf deployment script inside air-gap
├── 01-pkg-gitlab-core/
│   ├── zarf.yaml                      # Zarf package for MinIO, AI Gateway, and GitLab FIPS
│   ├── values-minio.yaml              # MinIO chart values (auto-provisioning 6 GitLab buckets)
│   ├── values-ai-gateway.yaml         # FIPS AI Gateway values, Duo Workflow JWT, model routing
│   └── values-gitlab.yaml             # GitLab 9.x values enforcing FIPS images & MinIO object store
├── 02-pkg-vllm-router-hub/
│   ├── zarf.yaml                      # Hub package pulling llm-semantic-router/vllm-router chart
│   └── values-router.yaml             # Static routes forwarding requests to backend model services
├── 03-pkg-models-spokes/
│   ├── model-nemotron-3.5/
│   │   ├── Dockerfile                 # vLLM base + baked weights
│   │   ├── deployment.yaml            # 2 replicas, TP=2, /dev/shm, Hermes tool parser
│   │   ├── pdb.yaml                   # PodDisruptionBudget (minAvailable: 1)
│   │   └── zarf.yaml                  # Independent Zarf Spoke manifest
│   ├── model-gpt-oss-120b/
│   │   ├── Dockerfile                 # vLLM base + baked weights
│   │   ├── deployment.yaml            # FP8 quantized MoE, TP=2, tool calling enabled
│   │   ├── h200-override-values.yaml  # NodeSelector & TP=8 override for 8x H200 node
│   │   ├── pdb.yaml                   # PodDisruptionBudget
│   │   └── zarf.yaml                  # Independent Zarf Spoke manifest
│   ├── model-laguna-xs/
│   │   ├── Dockerfile                 # vLLM base + baked weights
│   │   ├── deployment.yaml            # 3 replicas, TP=2, 256k context window
│   │   ├── pdb.yaml                   # PodDisruptionBudget
│   │   └── zarf.yaml                  # Independent Zarf Spoke manifest
│   └── model-nomic-embed/
│   │   ├── Dockerfile                 # TEI base + baked embeddings
│   │   ├── deployment.yaml            # Text Embeddings Inference deployment & service
│   │   └── zarf.yaml                  # Independent Zarf Spoke manifest
└── 04-pkg-agent-sandbox/
    ├── zarf.yaml                      # Zarf package for isolated GitLab Runners & security policies
    ├── values-runner.yaml             # Kubernetes executor runner values targeting agent jobs
    └── network-policy.yaml            # Zero-Trust NetworkPolicy isolating runner pods
```

---

## 3. Hardware & GPU Allocation Strategy

Cluster: **8x Dell VxRail nodes** managed by VMware vSphere with Tanzu. Each node is equipped with **2x NVIDIA L40 (48GB) PCIe GPUs** mapped via Tanzu VM Class `vSphere.vm.class: "best-effort-gpu"`.

| Component | Node Count | GPUs Allocated | VM Class | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Nemotron 3.5 Lightning** | 2 Nodes | 4 GPUs (2 Replicas, TP=2) | `best-effort-gpu` | Fast code completion & Hermes tool calling |
| **GPT OSS 120B** | 2 Nodes | 4 GPUs (2 Replicas, TP=2) | `best-effort-gpu` | FP8 MoE for advanced agentic reasoning |
| **Laguna XS 2.1** | 3 Nodes | 6 GPUs (3 Replicas, TP=2) | `best-effort-gpu` | 256k long context for full repository analysis |
| **Nomic Embed Text** | 1 Node | 2 GPUs (2 Replicas, 1 GPU ea) | `best-effort-gpu` | High-throughput semantic code embeddings |
| **Future H200 Expansion** | 1 Node | 8x H200 (141GB SXM5) | `h200-inference-class`| Single-node TP=8 execution via `h200-override-values.yaml` |

---

## 4. Lifecycle & Air-Gap Operations

### Phase 1: Internet-Connected Staging Machine

1. **Download Model Weights:**
   ```bash
   chmod +x ./00-scripts/*.sh
   ./00-scripts/01-download-weights.sh
   ```

2. **Bake Docker Images:**
   ```bash
   ./00-scripts/02-build-images.sh
   ```

3. **Generate Duo Workflow JWT Keypair:**
   ```bash
   ./00-scripts/04-generate-jwt-keys.sh
   ```

4. **Compile Chunked Zarf Packages (20GB max per chunk):**
   ```bash
   ./00-scripts/03-create-zarf-packages.sh
   ```

5. **Transfer Artifacts:** Copy `dist/` and `keys/` directories across the physical air gap / optical diode onto the internal Tanzu bastion host.

---

### Phase 2: Disconnected Tanzu Environment

1. **Execute End-to-End Air-Gap Deployment:**
   ```bash
   ./00-scripts/05-deploy-airgap.sh
   ```

2. **Verify Cluster Health:**
   ```bash
   kubectl get pods -n inference -o wide
   kubectl get pods -n gitlab
   kubectl get pods -n ai-gateway
   kubectl get pods -n agent-sandbox
   ```

---

## 5. Security & Zero-Trust Isolation

- **FIPS 140-2/3 Compliance:** All core GitLab components run with `global.image.tagSuffix: "-fips"` using official Red Hat UBI FIPS base layers.
- **IPC Stability:** All GPU pods mount an `emptyDir` memory volume at `/dev/shm` (size `16Gi` / `64Gi`) to eliminate NCCL inter-process crashes during tensor parallelism.
- **Agent Sandbox Isolation:** Pods running in `agent-sandbox` are enforced with a default-deny `NetworkPolicy`. Egress is restricted exclusively to DNS (`kube-system:53`), GitLab API/Git (`gitlab:80/443`), and AI Gateway (`ai-gateway:5052`), preventing AI-generated code execution from probing the vSphere management plane or internal subnets.
