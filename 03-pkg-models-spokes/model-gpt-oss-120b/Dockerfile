# ==============================================================================
# Model: GPT OSS 120B (FP8 Quantized MoE)
# Base Image: vLLM OpenAI Server
# Strategy: Bake model weights directly into container image for air-gapped run.
# ==============================================================================

FROM vllm/vllm-openai:v0.6.3

LABEL maintainer="Platform AI Infrastructure Team"
LABEL description="Air-Gapped vLLM image with baked GPT OSS 120B FP8 weights"

# Create model weight storage directory
RUN mkdir -p /models/gpt-oss-120b

# Copy pre-downloaded weights from build context
COPY ./model-weights /models/gpt-oss-120b

# Set default model directory and runtime environment
ENV MODEL_PATH=/models/gpt-oss-120b \
    VLLM_USAGE_SOURCE=airgap \
    VLLM_NO_USAGE_STATS=1 \
    NCCL_DEBUG=WARN \
    PYTHONUNBUFFERED=1

EXPOSE 8000

# Default entrypoint starts the OpenAI-compatible vLLM API server
ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
