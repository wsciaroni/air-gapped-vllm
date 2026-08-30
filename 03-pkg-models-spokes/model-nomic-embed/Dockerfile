# ==============================================================================
# Model: Nomic Embed Text v1.5
# Base Image: Hugging Face Text Embeddings Inference (TEI)
# Strategy: Bake embedding weights directly into TEI container for air-gapped run.
# ==============================================================================

FROM ghcr.io/huggingface/text-embeddings-inference:t4-1.5

LABEL maintainer="Platform AI Infrastructure Team"
LABEL description="Air-Gapped TEI image with baked Nomic Embed Text v1.5 weights"

# Create model directory
RUN mkdir -p /models/nomic-embed-text

# Copy pre-downloaded embedding weights from build context
COPY ./model-weights /models/nomic-embed-text

ENV MODEL_ID=/models/nomic-embed-text \
    PORT=8000 \
    HOSTNAME=0.0.0.0

EXPOSE 8000

# Default entrypoint starts the high-throughput TEI webserver
ENTRYPOINT ["text-embeddings-router"]
CMD ["--model-id", "/models/nomic-embed-text", "--port", "8000", "--hostname", "0.0.0.0", "--max-client-batch-size", "64", "--max-batch-tokens", "32768"]
