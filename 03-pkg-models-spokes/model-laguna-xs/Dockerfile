# ==============================================================================
# Model: Laguna XS 2.1 (256k Context Window)
# Base Image: vLLM OpenAI Server
# Strategy: Bake model weights directly into container image for air-gapped run.
# ==============================================================================

FROM vllm/vllm-openai:v0.6.3

LABEL maintainer="Platform AI Infrastructure Team"
LABEL description="Air-Gapped vLLM image with baked Laguna XS 2.1 weights"

# Create model weight storage directory
RUN mkdir -p /models/laguna-xs-2.1

# Copy pre-downloaded weights from build context
COPY ./model-weights /models/laguna-xs-2.1

# Set default model directory and runtime environment
ENV MODEL_PATH=/models/laguna-xs-2.1 \
    VLLM_USAGE_SOURCE=airgap \
    VLLM_NO_USAGE_STATS=1 \
    NCCL_DEBUG=WARN \
    PYTHONUNBUFFERED=1

EXPOSE 8000

# Default entrypoint starts the OpenAI-compatible vLLM API server
ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
