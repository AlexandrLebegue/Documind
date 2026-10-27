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


def _env_bool(name: str, default: bool) -> bool:
    """Read a boolean environment variable (1/true/yes/on)."""
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


# AI provider — "llamacpp" | "openrouter" | "ollama" | "custom"
# Saved settings take precedence over env vars. The default is the local
# llama.cpp server (MiniCPM) so no paid API key is required.
AI_PROVIDER = _saved.get(
    "ai_provider",
    os.environ.get("AI_PROVIDER", "llamacpp"),
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
    os.environ.get("LLAMACPP_BASE_URL", "http://192.168.1.59:8080"),
)
LLAMACPP_MODEL = _saved.get(
    "llamacpp_model",
    os.environ.get("LLAMACPP_MODEL", "minicpm5-2b"),
)
LLM_TEMPERATURE = 0.1
LLM_MAX_TOKENS = 8192
# MiniCPM5 has thinking enabled by default — disable it for deterministic
# metadata extraction unless explicitly requested.
LLM_DISABLE_THINKING = _env_bool("LLM_DISABLE_THINKING", True)

# Embedding settings
EMBEDDING_MODEL_NAME = os.environ.get("EMBEDDING_MODEL_NAME", "all-MiniLM-L6-v2")
EMBEDDING_CACHE_DIR = os.path.join(DATA_DIR, "models")
# Load the embedding model on first use instead of at startup (saves ~1 GB
# RSS and several seconds of boot time on idle instances).
EMBEDDING_LAZY_LOAD = _env_bool("EMBEDDING_LAZY_LOAD", True)

# OCR settings
OCR_LANGUAGES = "fra+eng+deu+ara"
MIN_TEXT_LENGTH_PER_PAGE = 50  # Below this, treat PDF page as scanned image

# OCR backend: "ovis" (OvisOCR3 over HTTP, default) or "tesseract"
OCR_BACKEND = os.environ.get("OCR_BACKEND", "ovis").strip().lower()
OVISOCR_URL = os.environ.get(
    "OVISOCR_URL", "http://192.168.1.59:8081/v1"
).rstrip("/")
OVISOCR_MODEL = os.environ.get("OVISOCR_MODEL", "ovisocr3")
# PyMuPDF rendering DPI. 130 is the measured speed/quality sweet spot.
OCR_DPI = int(os.environ.get("OCR_DPI", "130"))
OCR_JPEG_QUALITY = int(os.environ.get("OCR_JPEG_QUALITY", "80"))
OCR_PAGE_TIMEOUT = float(os.environ.get("OCR_PAGE_TIMEOUT", "400"))
OCR_PAGE_RETRIES = int(os.environ.get("OCR_PAGE_RETRIES", "2"))
OCR_MAX_TOKENS = int(os.environ.get("OCR_MAX_TOKENS", "3000"))
# "plain" (plain_ocr prompt) or "markdown" (Markdown + HTML tables)
OCR_PROMPT = os.environ.get("OCR_PROMPT", "plain").strip().lower()
OCR_CACHE_DIR = os.path.join(DATA_DIR, "ocr_cache")
OCR_CACHE_ENABLED = _env_bool("OCR_CACHE_ENABLED", True)

# Long-document handling: split into blocks of pages for MiniCPM map-reduce.
LLM_MAP_CHUNK_CHARS = int(os.environ.get("LLM_MAP_CHUNK_CHARS", "200000"))
LLM_MAP_CHUNK_PAGES = int(os.environ.get("LLM_MAP_CHUNK_PAGES", "8"))
# Enable MiniCPM-based segmentation of multi-document scans.
SEGMENT_MULTI_DOC = _env_bool("SEGMENT_MULTI_DOC", True)

# SQLite tuning
SQLITE_CACHE_MB = int(os.environ.get("SQLITE_CACHE_MB", "20"))
SQLITE_MMAP_MB = int(os.environ.get("SQLITE_MMAP_MB", "128"))

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
os.makedirs(OCR_CACHE_DIR, exist_ok=True)
