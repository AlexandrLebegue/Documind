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


def _first_setting(candidates: tuple[tuple[str, str], ...], default):
    """Return the first non-empty value among ordered (saved, env) pairs.

    Each pair is tried in order, saved value before environment value, so a
    canonical ``LLM_*`` env var still wins over a legacy ``llamacpp_*`` saved
    setting from an older installation.
    """
    for saved_key, env_name in candidates:
        value = _saved.get(saved_key)
        if value not in (None, ""):
            return value
        value = os.environ.get(env_name)
        if value not in (None, ""):
            return value
    return default


# AI provider — "llamacpp" (local OpenAI-compatible server) | "ollama" |
# "openrouter" | "custom". Saved settings take precedence over env vars.
# The default local provider id stays "llamacpp" for backwards compatibility;
# the server behind it is now HyperQwen/vLLM hosting Qwen3.8-27B.
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

# Local OpenAI-compatible LLM (Qwen3.8-27B served by HyperQwen/vLLM).
# Canonical variables are LLM_*; LLAMACPP_* are kept as backwards-compatible
# aliases for older .env files and saved settings.
LLM_BASE_URL = _first_setting(
    (
        ("llm_base_url", "LLM_BASE_URL"),
        ("llamacpp_base_url", "LLAMACPP_BASE_URL"),
    ),
    "http://192.168.1.59:18020/v1",
)
LLM_MODEL = _first_setting(
    (
        ("llm_model", "LLM_MODEL"),
        ("llamacpp_model", "LLAMACPP_MODEL"),
    ),
    "qwen3.8-27b",
)
# Mandatory for the new HyperQwen/vLLM endpoint. Never committed to git.
LLM_API_KEY = os.environ.get("LLM_API_KEY", "").strip()

# Backwards-compatible aliases used by the settings API and older code.
LLAMACPP_BASE_URL = LLM_BASE_URL
LLAMACPP_MODEL = LLM_MODEL

LLM_TEMPERATURE = float(os.environ.get("LLM_TEMPERATURE", "0.1"))
# Qwen recommends keeping the generated output at or below 16k tokens.
LLM_MAX_TOKENS = int(os.environ.get("LLM_MAX_TOKENS", "16384"))
LLM_MAX_CONTEXT_TOKENS = int(os.environ.get("LLM_MAX_CONTEXT_TOKENS", "196608"))
# Qwen3 thinking must be disabled for deterministic JSON. Any residual
# <think>…</think> block is stripped by the LLM client before parsing.
LLM_DISABLE_THINKING = _env_bool("LLM_DISABLE_THINKING", True)
# Ask vLLM for JSON output (response_format=json_object) when supported.
# The client automatically retries without it on HTTP 400.
LLM_JSON_MODE = _env_bool("LLM_JSON_MODE", True)
# Local 27B generation is slower than the former 2B model: allow long reads.
LLM_TIMEOUT = float(os.environ.get("LLM_TIMEOUT", "900"))
LLM_CONNECT_TIMEOUT = float(os.environ.get("LLM_CONNECT_TIMEOUT", "15"))
# Text-only profile: images are sent exclusively to the OCR backend, never
# to the language model.
LLM_TEXT_ONLY = _env_bool(
    "LLM_LANGUAGE_MODEL_ONLY",
    _env_bool("LLM_TEXT_ONLY", AI_PROVIDER in {"llamacpp", "ollama"}),
)

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

# Long-document handling: split into blocks of pages for LLM map-reduce.
# Qwen3.8-27B has a 196608-token context. With a 16384-token output budget,
# ~600k characters (~150k tokens) leaves a comfortable safety margin.
LLM_MAP_CHUNK_CHARS = int(os.environ.get("LLM_MAP_CHUNK_CHARS", "600000"))
LLM_MAP_CHUNK_PAGES = int(os.environ.get("LLM_MAP_CHUNK_PAGES", "24"))
# Page segmentation is cheap (a short snippet per page) and Qwen can handle
# far more pages per call than the former 2B model.
LLM_SEGMENT_MAX_PAGES = int(os.environ.get("LLM_SEGMENT_MAX_PAGES", "200"))
LLM_SEGMENT_PAGE_CHARS = int(os.environ.get("LLM_SEGMENT_PAGE_CHARS", "2500"))
# Enable LLM-based segmentation of multi-document scans.
SEGMENT_MULTI_DOC = _env_bool("SEGMENT_MULTI_DOC", True)

# SQLite tuning
SQLITE_CACHE_MB = int(os.environ.get("SQLITE_CACHE_MB", "20"))
SQLITE_MMAP_MB = int(os.environ.get("SQLITE_MMAP_MB", "128"))

# Upload settings
MAX_UPLOAD_SIZE_MB = 50
SUPPORTED_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png", ".tiff", ".webp"}

# ---------------------------------------------------------------------------
# Folder-sync ingestion (desktop agent → server)
# ---------------------------------------------------------------------------
INGEST_DIR = os.path.join(DATA_DIR, "ingest")
# Extensions the agent is allowed to send. The server revalidates everything.
INGEST_ALLOWED_EXTENSIONS = {".pdf", ".txt", ".jpg", ".jpeg", ".png", ".bmp"}
INGEST_MIN_SIZE_BYTES = 1024
INGEST_MAX_SIZE_BYTES = MAX_UPLOAD_SIZE_MB * 1024 * 1024
# Below this confidence the judge result is sent to manual review.
INGEST_JUDGE_CONFIDENCE = float(os.environ.get("INGEST_JUDGE_CONFIDENCE", "0.7"))

# Server settings
HOST = "0.0.0.0"
PORT = int(os.environ.get("PORT", "8000"))
# Comma-separated list of allowed CORS origins. "*" allows every origin,
# which is the historic behaviour; the desktop client uses tauri://localhost
# (Linux/macOS) and http://tauri.localhost (Windows).
CORS_ORIGINS = [
    origin.strip()
    for origin in os.environ.get(
        "CORS_ORIGINS",
        "*,tauri://localhost,http://tauri.localhost,https://tauri.localhost",
    ).split(",")
    if origin.strip()
]

# Search settings
FTS_WEIGHT = 0.4
SEMANTIC_WEIGHT = 0.6
DEFAULT_SEARCH_TOP_K = 20

# Chat RAG settings
RAG_TOP_K_DOCS = 5
RAG_MAX_TOKENS_PER_DOC = 500

# ---------------------------------------------------------------------------
# Create required directories at import time
# ---------------------------------------------------------------------------
os.makedirs(ORIGINALS_DIR, exist_ok=True)
os.makedirs(EMBEDDING_CACHE_DIR, exist_ok=True)
os.makedirs(OCR_CACHE_DIR, exist_ok=True)
os.makedirs(INGEST_DIR, exist_ok=True)
