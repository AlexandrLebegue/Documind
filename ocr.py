"""OCR module: page rendering, OvisOCR3 (HTTP) and Tesseract backends.

The default backend is OvisOCR3, an OpenAI-compatible vision model served by
llama.cpp on the LAN. Tesseract remains available as an offline fallback.

Design notes
------------
* One HTTP request per page, strictly sequential (the OCR server has a single
  slot and shares CPU with the LLM server).
* Digital PDF pages with enough native text are never OCRed.
* Every OCRed page is cached on disk keyed by the source-file hash, page
  number, DPI, prompt and model. Re-running after a crash therefore skips
  pages that were already processed.
* If OvisOCR3 is unreachable, the page falls back to Tesseract instead of
  failing the whole document.
"""

from __future__ import annotations

import base64
import hashlib
import io
import logging
import os
import sys
import threading
import time
from pathlib import Path

import fitz  # PyMuPDF

from config import (
    MIN_TEXT_LENGTH_PER_PAGE,
    OCR_BACKEND,
    OCR_CACHE_DIR,
    OCR_CACHE_ENABLED,
    OCR_DPI,
    OCR_JPEG_QUALITY,
    OCR_LANGUAGES,
    OCR_MAX_TOKENS,
    OCR_PAGE_RETRIES,
    OCR_PAGE_TIMEOUT,
    OCR_PROMPT,
    OVISOCR_MODEL,
    OVISOCR_URL,
)
from prompts import OVIS_MARKDOWN_PROMPT, OVIS_PLAIN_PROMPT

logger = logging.getLogger(__name__)

# torch/cv2/PIL are imported lazily so that startup does not pay for the
# Tesseract-only dependency chain when the Ovis backend is used.

# Auto-detect Tesseract on Windows
if sys.platform == "win32":
    _win_tesseract = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    if os.path.isfile(_win_tesseract):
        import pytesseract

        pytesseract.pytesseract.tesseract_cmd = _win_tesseract
        logger.info("Tesseract found at %s", _win_tesseract)

# Fallback Tesseract renders at a higher DPI than the Ovis default.
_TESSERACT_FALLBACK_DPI = max(OCR_DPI, 200)

_http_client = None
_http_lock = threading.Lock()


# ---------------------------------------------------------------------------
# HTTP client (OvisOCR3)
# ---------------------------------------------------------------------------

def _get_http_client():
    """Return a shared httpx client for the OCR server (thread-safe)."""
    global _http_client
    with _http_lock:
        if _http_client is None:
            import httpx

            _http_client = httpx.Client(
                timeout=httpx.Timeout(OCR_PAGE_TIMEOUT + 20.0, connect=15.0),
                headers={"Content-Type": "application/json"},
            )
    return _http_client


def _ovis_prompt() -> str:
    if OCR_PROMPT == "markdown":
        return OVIS_MARKDOWN_PROMPT
    return OVIS_PLAIN_PROMPT


def _ovis_ocr_once(jpeg_bytes: bytes) -> str:
    """Send one page to OvisOCR3 and return the generated text."""
    import httpx

    b64 = base64.b64encode(jpeg_bytes).decode("ascii")
    payload = {
        "model": OVISOCR_MODEL,
        "temperature": 0,
        "max_tokens": OCR_MAX_TOKENS,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{b64}"},
                    },
                    {"type": "text", "text": _ovis_prompt()},
                ],
            }
        ],
    }
    client = _get_http_client()
    resp = client.post(f"{OVISOCR_URL}/chat/completions", json=payload)
    resp.raise_for_status()
    data = resp.json()
    choice = data["choices"][0]
    content = choice["message"]["content"]
    if isinstance(content, list):
        content = "".join(
            part.get("text", "") for part in content if isinstance(part, dict)
        )
    usage = data.get("usage") or {}
    logger.info(
        "OvisOCR page: prompt=%d tok, gen=%d tok, finish=%s",
        usage.get("prompt_tokens", 0),
        usage.get("completion_tokens", 0),
        choice.get("finish_reason", "unknown"),
    )
    return (content or "").strip()


def _ovis_ocr(jpeg_bytes: bytes) -> str:
    """Call OvisOCR3 with retries. Raises the last error if all attempts fail."""
    last_error: Exception | None = None
    for attempt in range(OCR_PAGE_RETRIES + 1):
        try:
            return _ovis_ocr_once(jpeg_bytes)
        except Exception as exc:  # network, timeout, HTTP 5xx, bad JSON…
            last_error = exc
            logger.warning(
                "OvisOCR request failed (attempt %d/%d): %s",
                attempt + 1,
                OCR_PAGE_RETRIES + 1,
                exc,
            )
            if attempt < OCR_PAGE_RETRIES:
                time.sleep(min(2.0 * (attempt + 1), 10.0))
    assert last_error is not None
    raise last_error


# ---------------------------------------------------------------------------
# Rendering and caching
# ---------------------------------------------------------------------------

def _render_pdf_page_jpeg(page, dpi: int) -> bytes:
    """Render a PyMuPDF page to JPEG bytes."""
    pix = page.get_pixmap(dpi=dpi)
    return pix.tobytes("jpeg", jpg_quality=OCR_JPEG_QUALITY)


def _image_file_to_jpeg(path: Path) -> bytes:
    """Load a standalone image and re-encode it as JPEG (quality ~80)."""
    from PIL import Image

    img = Image.open(str(path))
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    elif img.mode == "L":
        img = img.convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=OCR_JPEG_QUALITY)
    return buf.getvalue()


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _cache_key(file_hash: str, page_num: int, backend: str) -> str:
    raw = "|".join(
        [
            file_hash,
            f"page={page_num}",
            f"backend={backend}",
            f"dpi={OCR_DPI}",
            f"prompt={OCR_PROMPT}",
            f"model={OVISOCR_MODEL}",
        ]
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _cache_read(key: str) -> str | None:
    if not OCR_CACHE_ENABLED:
        return None
    path = os.path.join(OCR_CACHE_DIR, f"{key}.txt")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return None
    except OSError as exc:
        logger.debug("OCR cache read failed for %s: %s", key[:12], exc)
        return None


def _cache_write(key: str, text: str) -> None:
    if not OCR_CACHE_ENABLED or not text:
        return
    path = os.path.join(OCR_CACHE_DIR, f"{key}.txt")
    tmp = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except OSError as exc:
        logger.debug("OCR cache write failed for %s: %s", key[:12], exc)
        try:
            os.unlink(tmp)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Tesseract fallback
# ---------------------------------------------------------------------------

def preprocess_image(image):
    """Apply the Tesseract preprocessing pipeline to an image."""
    import cv2

    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()

    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    enhanced = _deskew(enhanced)
    blurred = cv2.GaussianBlur(enhanced, (3, 3), 0)
    return cv2.adaptiveThreshold(
        blurred,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        11,
        2,
    )


def _deskew(image):
    """Deskew an image by detecting rotation angle from the largest contour."""
    import cv2

    thresh = cv2.threshold(image, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)[1]
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return image

    largest_contour = max(contours, key=cv2.contourArea)
    if cv2.contourArea(largest_contour) < 100:
        return image

    rect = cv2.minAreaRect(largest_contour)
    angle = rect[2]
    if angle < -45:
        angle = 90 + angle
    elif angle > 45:
        angle = angle - 90

    if abs(angle) < 0.5 or abs(angle) > 45:
        return image

    h, w = image.shape[:2]
    center = (w // 2, h // 2)
    rotation_matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
    return cv2.warpAffine(
        image,
        rotation_matrix,
        (w, h),
        flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REPLICATE,
    )


def _tesseract_from_jpeg(jpeg_bytes: bytes) -> str:
    """Run Tesseract on already-rendered JPEG bytes."""
    import numpy as np
    import pytesseract
    from PIL import Image

    img = Image.open(io.BytesIO(jpeg_bytes)).convert("RGB")
    processed = preprocess_image(np.array(img))
    return pytesseract.image_to_string(processed, lang=OCR_LANGUAGES).strip()


def extract_text_from_image(image_path: str) -> str:
    """Extract text from an image file using Tesseract (explicit backend)."""
    import cv2
    import pytesseract

    path = Path(image_path)
    if not path.exists():
        raise FileNotFoundError(f"Image file not found: {image_path}")

    image = cv2.imread(str(path))
    if image is None:
        raise RuntimeError(f"Failed to load image with OpenCV: {image_path}")

    processed = preprocess_image(image)
    text = pytesseract.image_to_string(processed, lang=OCR_LANGUAGES).strip()
    logger.info("Tesseract extracted %d characters from %s", len(text), path.name)
    return text


# ---------------------------------------------------------------------------
# Page extraction
# ---------------------------------------------------------------------------

def _ocr_jpeg_page(
    jpeg_bytes: bytes,
    file_hash: str,
    page_num: int,
    backend: str,
) -> str:
    """OCR one rendered page with cache, retries and Tesseract fallback."""
    key = _cache_key(file_hash, page_num, backend)
    cached = _cache_read(key)
    if cached is not None:
        logger.info("Page %d: OCR cache hit (%d chars)", page_num, len(cached))
        return cached

    text = ""
    if backend == "ovis":
        try:
            text = _ovis_ocr(jpeg_bytes)
        except Exception as exc:
            logger.error(
                "OvisOCR failed for page %d after %d retries — falling back to Tesseract: %s",
                page_num,
                OCR_PAGE_RETRIES,
                exc,
            )
            text = _tesseract_from_jpeg(jpeg_bytes)
    else:
        text = _tesseract_from_jpeg(jpeg_bytes)

    text = text.strip()
    _cache_write(key, text)
    logger.info(
        "Page %d: %s extracted %d chars", page_num, backend, len(text)
    )
    return text


def extract_pages(file_path: str, progress_cb=None, info: dict | None = None) -> list[str]:
    """Extract text for every page of a PDF or image.

    Native PDF text is kept when it is long enough; otherwise the page is
    OCRed with OvisOCR3 (default) or Tesseract.

    Args:
        file_path: Path to a PDF or image file.
        progress_cb: Optional callable ``(pages_done, pages_total)`` invoked
            once before processing and after every page.
        info: Optional dict filled with ``backends`` (set of used backends).

    Returns:
        List of page texts.
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"File not found: {file_path}")

    ext = path.suffix.lower()
    backend = OCR_BACKEND if OCR_BACKEND in ("ovis", "tesseract") else "ovis"
    file_hash = _file_sha256(path)
    used_backends: set[str] = set()

    if ext == ".pdf":
        doc = fitz.open(str(path))
        total = len(doc)
        pages: list[str] = []
        if progress_cb:
            progress_cb(0, total)

        for page_num in range(total):
            page = doc[page_num]
            native_text = page.get_text().strip()

            if len(native_text) >= MIN_TEXT_LENGTH_PER_PAGE:
                page_text = native_text
                used_backends.add("native")
                logger.debug(
                    "Page %d/%d: native text (%d chars)",
                    page_num + 1,
                    total,
                    len(native_text),
                )
            else:
                jpeg = _render_pdf_page_jpeg(page, OCR_DPI)
                used_backends.add(backend)
                try:
                    page_text = _ocr_jpeg_page(
                        jpeg, file_hash, page_num + 1, backend
                    )
                except Exception as exc:
                    logger.error(
                        "All OCR backends failed for page %d/%d: %s",
                        page_num + 1,
                        total,
                        exc,
                    )
                    raise
            pages.append(page_text)
            if progress_cb:
                progress_cb(page_num + 1, total)

        doc.close()
        if info is not None:
            info["backends"] = used_backends
        logger.info(
            "Extracted %d page(s) from PDF %s (backend=%s)",
            total,
            path.name,
            "+".join(sorted(used_backends)) or backend,
        )
        return pages

    if ext in {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}:
        if progress_cb:
            progress_cb(0, 1)
        used_backends.add(backend)
        if backend == "ovis":
            jpeg = _image_file_to_jpeg(path)
            try:
                text = _ocr_jpeg_page(jpeg, file_hash, 1, backend)
            except Exception as exc:
                logger.error(
                    "OvisOCR failed for image %s — falling back to Tesseract: %s",
                    path.name,
                    exc,
                )
                text = _tesseract_from_jpeg(jpeg)
        else:
            text = extract_text_from_image(str(path))
        if progress_cb:
            progress_cb(1, 1)
        if info is not None:
            info["backends"] = used_backends
        return [text]

    raise ValueError(
        f"Unsupported file format '{ext}'. "
        "Supported formats: .pdf, .jpg, .jpeg, .png, .bmp, .tiff, .webp"
    )


def _join_pages(pages: list[str]) -> str:
    parts: list[str] = []
    for i, page_text in enumerate(pages):
        parts.append(f"--- Page {i + 1} ---\n\n{page_text}")
    return "\n\n".join(parts)


def extract_text_from_pdf(pdf_path: str, progress_cb=None) -> str:
    """Extract text from a PDF, falling back to OCR for scanned pages."""
    return _join_pages(extract_pages(pdf_path, progress_cb=progress_cb))


def extract_text(file_path: str) -> str:
    """Extract text from a document file (PDF or image)."""
    return _join_pages(extract_pages(file_path))


def extract_images_as_base64(
    file_path: str,
    max_pages: int = 3,
    dpi: int = 200,
    jpeg_quality: int = 80,
) -> list[str]:
    """Extract document pages as base64 JPEG (only used by vision providers)."""
    from PIL import Image

    path = Path(file_path)
    if not path.exists():
        logger.warning("Cannot extract images — file not found: %s", file_path)
        return []

    ext = path.suffix.lower()
    images_b64: list[str] = []
    try:
        if ext == ".pdf":
            doc = fitz.open(str(path))
            for page_num in range(min(len(doc), max_pages)):
                pix = doc[page_num].get_pixmap(dpi=dpi)
                pil_image = Image.frombytes(
                    "RGB", [pix.width, pix.height], pix.samples
                )
                buf = io.BytesIO()
                pil_image.save(buf, format="JPEG", quality=jpeg_quality)
                images_b64.append(
                    base64.b64encode(buf.getvalue()).decode("ascii")
                )
            doc.close()
        elif ext in {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}:
            pil_image = Image.open(str(path))
            if pil_image.mode != "RGB":
                pil_image = pil_image.convert("RGB")
            buf = io.BytesIO()
            pil_image.save(buf, format="JPEG", quality=jpeg_quality)
            images_b64.append(base64.b64encode(buf.getvalue()).decode("ascii"))
    except Exception:
        logger.exception("Failed to extract images from %s", file_path)

    return images_b64
