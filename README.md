## 1. Executive Summary & Architecture

**The Goal:** Provide developers in a disconnected (air-gapped) environment with GitLab Duo code completion and autonomous agentic workflows (GitLab Duo Agent Platform).

Because the network cannot reach cloud LLMs (like Anthropic or OpenAI), the AI must be self-hosted. The system leverages VMware Tanzu to map 16 physical GPUs to Kubernetes pods. We will use a **Modular (Hub-and-Spoke) Zarf deployment** to bypass the air gap. The "Hub" is a Semantic Router that intercepts AI requests from GitLab, and the "Spokes" are standalone Zarf packages for three massive LLMs: GPT OSS 120B, Nemotron 3.5 Lightning, and Laguna XS 2.1.

---

## 2. Infrastructure & Pre-Flight Checklist

Before touching Zarf, the infrastructure team must configure the VxRail/Tanzu environment and gather the necessary cryptography.

**Hardware & Tanzu Configuration**

* **VxRail Nodes (8):** Ensure all nodes are clustered in vCenter.
* **Physical GPUs (16):** Ensure NVIDIA vGPU VIBs are installed on ESXi or Passthrough is enabled.
* **Tanzu VM Class:** Create a specific VM Class in Tanzu (e.g., `gpu-large`) that maps exactly 2 GPUs to a Kubernetes worker node.
* **vSAN Storage:** Confirm at least 1.5TB of free storage to handle the massive LLM weights, MinIO object storage, and GitLab repositories.

**Cryptography & Credentials**

* **Corporate TLS Certificate:** A wildcard TLS cert (e.g., `*.gitlab.internal.local`) signed by your offline Root CA.
* **GitLab License:** Must include the **GitLab Duo Enterprise** add-on.
* **Agentic JWT Keypair:** Generate an RSA keypair to secure the AI Gateway to the GitLab Monolith [cite: 1.1.1; 1.1.3].
* `openssl genrsa -out duo_workflow_jwt.key 2048` [cite: 1.1.1]
* `openssl genrsa -out duo_workflow_validation.key 2048` [cite: 1.1.1]



---

## 3. GPU Node Allocation Strategy

We have 16 GPUs total (8 nodes x 2 GPUs). They will be allocated declaratively via Kubernetes deployments as follows:

| Component | Tanzu Nodes Required | GPUs Required | Purpose |
| --- | --- | --- | --- |
| **GPT OSS 120B** | 2 Nodes | 4 GPUs | FP8 Quantized MoE for advanced reasoning. |
| **Nemotron 3.5** | 2 Nodes | 4 GPUs | 30B MoE for agentic tool-calling (Hermes parser). |
| **Laguna XS 2.1** | 3 Nodes | 6 GPUs | 256K Context Window for full-repository reads. |
| **Overhead/Embedding** | 1 Node | 2 GPUs | Context embedding (TEI) and cluster overhead. |

---

## 4. The Build & Package Phase

*Requires an internet-connected staging machine with ~500GB NVMe storage, Docker, and the Zarf CLI.*

### Step 4A: Bake the Model Images

Because air-gapped clusters cannot reach Hugging Face, you must download the weights locally and copy them into custom Docker images.

1. Download weights via CLI: `huggingface-cli download nvidia/Nemotron-3.5-Lightning-30B-A3B-W4A16 --local-dir ./nemotron-3.5`
2. Write a Dockerfile using the vLLM base:
```dockerfile
FROM vllm/vllm-openai:latest
COPY ./nemotron-3.5 /models/nemotron-3.5

```


3. Build the images: `docker build -t local-registry/vllm-nemotron:v1 .` (Repeat for GPT OSS and Laguna).

### Step 4B: Create the Modular Zarf Packages

You will define and build multiple decoupled packages so you can lifecycle the AI models independently.

1. **Zarf Package 1 (Infrastructure):** Bundles MinIO, the FIPS AI Gateway [cite: 1.1.1], and GitLab 18 core. Run `zarf dev find-images --update` to automatically resolve all 50+ GitLab FIPS microservices.
2. **Zarf Package 2 (The Hub):** Bundles the `vllm-router` Helm chart directly from GitHub.
3. **Zarf Packages 3, 4, 5 (The Spokes):** Standard Kubernetes manifests mapping to the custom `local-registry` LLM images you built in Step 4A.

### Step 4C: Compile the Bundles

Run the `create` command for each package. Because the model packages are massive (30GB - 80GB each), you **must** use the `--max-package-size` flag to chunk the `.tar.zst` files into manageable sizes for secure media transfer [cite: 1.2.1; 1.2.2].

```bash
zarf package create . --max-package-size 20000 --confirm

```

---

## 5. Transfer & Deploy Phase

*Requires physical movement of the Zarf CLI binary and the chunked `.tar.zst.part00X` files across the air gap to a management VM inside the VxRail environment.*

1. **Authenticate:** SSH into your management VM and point your `kubeconfig` to the Tanzu Supervisor/Workload cluster.
2. **Initialize Zarf:** Run `zarf init`. This installs the internal container registry and Git server directly into Tanzu [cite: 1.2.3].
3. **Deploy Infrastructure:**
```bash
zarf package deploy zarf-package-gitlab-infrastructure-amd64.tar.zst --confirm

```


4. **Deploy the AI Stack (Hub then Spokes):**
```bash
zarf package deploy zarf-package-vllm-router-hub.tar.zst --confirm
zarf package deploy zarf-package-model-nemotron.tar.zst --confirm
zarf package deploy zarf-package-model-gptoss.tar.zst --confirm
zarf package deploy zarf-package-model-lagunaxs.tar.zst --confirm

```


*Zarf will automatically reassemble the chunked files, push the 150GB of model weights into the internal registry, and apply the Kubernetes manifests [cite: 1.2.3].*

---

## 6. Day 2 Operations & Agent Isolation

**Model Scaling:** Because the packages are decoupled, you can pause any model to free up GPUs without uninstalling it:

```bash
kubectl scale deployment vllm-nemotron-backend --replicas=0 -n inference

```

**Zero-Trust Sandboxes:** To support Agentic development (where the AI writes and executes code), you must deploy isolated GitLab Runners [cite: 1.1.1; 1.1.4]. The engineering team must apply a Kubernetes `NetworkPolicy` to the Runner namespace that denies all Egress traffic except to the GitLab instance and the AI Gateway, physically preventing an AI-generated script from scanning the VxRail management plane.

Alternatively, developers can use OpenCode podman containers to develop in sandboxes on their local machine.
