# syntax=docker/dockerfile:1
# ============================================================
# DocuMind — Multi-stage Dockerfile
# Stage 1: Build the React/Next.js frontend
# Stage 2: Python application with Tesseract OCR & OpenRouter LLM
# ============================================================

# --------------------------------------------------
# Stage 1: Build frontend
# --------------------------------------------------
FROM node:20-slim AS frontend-builder
WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline
COPY frontend/ .
RUN npm run build

# --------------------------------------------------
# Stage 2: Python app
# --------------------------------------------------
FROM python:3.12-slim

# Install runtime dependencies only (no more build tools needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-fra \
    tesseract-ocr-eng \
    tesseract-ocr-deu \
    tesseract-ocr-ara \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
# Install CPU-only PyTorch first to avoid downloading ~2GB of NVIDIA CUDA libraries
# (sentence-transformers depends on torch, and the default torch includes CUDA)
COPY requirements.txt .
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py config.py database.py models.py pipeline.py \
     ocr.py llm.py embeddings.py search.py prompts.py \
     agent.py web_tools.py update.py ./

# Copy pre-built frontend from Stage 1
COPY --from=frontend-builder /frontend/out ./static/

# Create data directories (will be overridden by volume mount)
RUN mkdir -p /data/originals /data/models

# Environment
ENV DOCUMIND_DATA_DIR=/data
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health')" || exit 1

CMD ["python", "main.py", "--skip-build"]
