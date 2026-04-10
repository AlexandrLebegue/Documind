"""DocuMind configuration — all paths, constants, and parameters."""

import json
import os
from pathlib import Path

from dotenv import load_dotenv

# Load .env file from the project root (next to config.py)
load_dotenv(Path(__file__).parent / ".env")

# Base data directory (mounted volume in Docker)
DATA_DIR = os.environ.get("DOCUMIND_DATA_DIR", "/data")
ORIGINALS_DIR = os.path.join(DATA_DIR, "originals")
DB_PATH = os.path.join(DATA_DIR, "documind.db")
SETTINGS_PATH = os.path.join(DATA_DIR, "settings.json")

# ---------------------------------------------------------------------------
# Settings persistence (JSON file in DATA_DIR)
# ---------------------------------------------------------------------------

def load_settings() -> dict:
    """Load saved settings from ``settings.json`` in DATA_DIR.

    Returns an empty dict if the file does not exist or is invalid.
    """
    if os.path.exists(SETTINGS_PATH):
        try:
            with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def save_settings(settings: dict) -> None:
    """Persist *settings* to ``settings.json`` in DATA_DIR."""
    os.makedirs(os.path.dirname(SETTINGS_PATH), exist_ok=True)
    with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)


_saved = load_settings()

# AI provider — "openrouter" | "ollama" | "custom"
# Saved settings take precedence over env vars
AI_PROVIDER = _saved.get(
    "ai_provider",
    os.environ.get("AI_PROVIDER", "openrouter"),
)

# OpenRouter / custom LLM settings — saved settings take precedence over env vars
OPENROUTER_API_KEY = _saved.get(
    "openrouter_api_key",
    os.environ.get("OPENROUTER_API_KEY", ""),
)
OPENROUTER_BASE_URL = _saved.get(
    "openrouter_base_url",
    os.environ.get("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1"),
)
OPENROUTER_MODEL = _saved.get(
    "openrouter_model",
    os.environ.get("OPENROUTER_MODEL", "google/gemini-3.1-pro-preview"),
)

# Ollama settings (used when AI_PROVIDER == "ollama")
OLLAMA_BASE_URL = _saved.get(
    "ollama_base_url",
    os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434"),
)
OLLAMA_MODEL = _saved.get(
    "ollama_model",
    os.environ.get("OLLAMA_MODEL", "qwen3.5:2b"),
)

# llama.cpp server settings (used when AI_PROVIDER == "llamacpp")
LLAMACPP_BASE_URL = _saved.get(
    "llamacpp_base_url",
    os.environ.get("LLAMACPP_BASE_URL", "http://192.168.1.50:8080"),
)
LLAMACPP_MODEL = _saved.get(
    "llamacpp_model",
    os.environ.get("LLAMACPP_MODEL", "local"),
)
LLM_TEMPERATURE = 0.1
LLM_MAX_TOKENS = 2048

# Embedding settings
EMBEDDING_MODEL_NAME = "all-MiniLM-L6-v2"
EMBEDDING_CACHE_DIR = os.path.join(DATA_DIR, "models")

# OCR settings
OCR_LANGUAGES = "fra+eng+deu+ara"
MIN_TEXT_LENGTH_PER_PAGE = 50  # Below this, treat PDF page as scanned image

# Upload settings
MAX_UPLOAD_SIZE_MB = 50
SUPPORTED_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png", ".tiff", ".webp"}

# Search settings
FTS_WEIGHT = 0.4
SEMANTIC_WEIGHT = 0.6
DEFAULT_SEARCH_TOP_K = 20

# Chat RAG settings
RAG_TOP_K_DOCS = 5
RAG_MAX_TOKENS_PER_DOC = 500

# Server settings
HOST = "0.0.0.0"
PORT = 8000

# ---------------------------------------------------------------------------
# Create required directories at import time
# ---------------------------------------------------------------------------
os.makedirs(ORIGINALS_DIR, exist_ok=True)
os.makedirs(EMBEDDING_CACHE_DIR, exist_ok=True)
