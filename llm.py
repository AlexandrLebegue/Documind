"""LLM module: OpenRouter / Ollama / custom API wrapper for metadata extraction and chat."""

import json
import logging
import re
from typing import Optional

import httpx

import config as _cfg
from classification import finalize_metadata, normalize_doc_type
from prompts import (
    METADATA_EXTRACTION_PROMPT,
    METADATA_CORRECTION_PROMPT,
    METADATA_MERGE_PROMPT,
    JUDGE_PROMPT,
    OCR_TEXT_ONLY_NOTE,
    RAG_CHAT_PROMPT,
    SEGMENTATION_PROMPT,
    VALID_DOC_TYPES,
    PROCEDURE_ANALYSIS_PROMPT,
    PROCEDURE_MATCH_PROMPT,
    segmentation_user_message,
)

logger = logging.getLogger(__name__)

# Maximum characters of OCR text sent in a single call. Beyond this we use a
# map-reduce strategy (chunks of pages + merge). ~4 chars ≈ 1 token, and the
# MiniCPM server exposes a 98k-token context.
_MAX_OCR_CHARS = _cfg.LLM_MAP_CHUNK_CHARS

# Maximum number of images to include in a multimodal request
_MAX_IMAGES = 3

# Maximum characters per document in RAG context (~500 tokens)
_MAX_RAG_DOC_CHARS = 2000

# Timeout for LLM API calls (seconds) — increase for slow local models
_API_TIMEOUT = 600.0


def _active_model() -> str:
    """Return the model identifier for the currently active provider."""
    if _cfg.AI_PROVIDER == "ollama":
        return _cfg.OLLAMA_MODEL
    if _cfg.AI_PROVIDER == "llamacpp":
        return _cfg.LLAMACPP_MODEL
    return _cfg.OPENROUTER_MODEL


def init_llm_client() -> httpx.Client:
    """Create an httpx client pre-configured for the active AI provider.

    Supported providers (``config.AI_PROVIDER``):
    - ``"openrouter"`` — OpenRouter cloud API (requires API key)
    - ``"ollama"``     — Local/remote Ollama instance (no key needed)
    - ``"custom"``     — OpenAI-compatible endpoint with custom base URL

    Returns:
        An :class:`httpx.Client` ready for ``/chat/completions`` calls.

    Raises:
        ValueError: If OpenRouter/custom is selected but the API key is missing.
    """
    provider = _cfg.AI_PROVIDER

    if provider == "ollama":
        # Ollama exposes an OpenAI-compatible endpoint — no auth required
        base_url = _cfg.OLLAMA_BASE_URL.rstrip("/") + "/v1"
        client = httpx.Client(
            base_url=base_url,
            headers={"Content-Type": "application/json"},
            timeout=_API_TIMEOUT,
        )
        logger.info(
            "Ollama LLM client initialised (model=%s, base_url=%s)",
            _cfg.OLLAMA_MODEL,
            base_url,
        )
        return client

    if provider == "llamacpp":
        # llama-server exposes an OpenAI-compatible endpoint — no auth required
        base_url = _cfg.LLAMACPP_BASE_URL.rstrip("/") + "/v1"
        client = httpx.Client(
            base_url=base_url,
            headers={"Content-Type": "application/json"},
            timeout=_API_TIMEOUT,
        )
        logger.info(
            "llama.cpp LLM client initialised (model=%s, base_url=%s)",
            _cfg.LLAMACPP_MODEL,
            base_url,
        )
        return client

    # openrouter or custom — both require an API key
    if not _cfg.OPENROUTER_API_KEY:
        raise ValueError(
            "OPENROUTER_API_KEY is not set. "
            "Please configure it in Settings or set the environment variable."
        )

    client = httpx.Client(
        base_url=_cfg.OPENROUTER_BASE_URL,
        headers={
            "Authorization": f"Bearer {_cfg.OPENROUTER_API_KEY}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://documind.local",
            "X-Title": "DocuMind",
        },
        timeout=_API_TIMEOUT,
    )
    logger.info(
        "LLM client initialised (provider=%s, model=%s, base_url=%s)",
        provider,
        _cfg.OPENROUTER_MODEL,
        _cfg.OPENROUTER_BASE_URL,
    )
    return client


def _call_llm(
    client: httpx.Client,
    system_prompt: str,
    user_message: str,
    images: list[str] | None = None,
    temperature: float = _cfg.LLM_TEMPERATURE,
    max_tokens: int = _cfg.LLM_MAX_TOKENS,
) -> str:
    """Send a chat-completion request to OpenRouter.

    Supports multimodal requests: when *images* is provided, the user
    message is formatted as a content array with text and image_url parts
    following the OpenAI vision API format.

    Args:
        client: Pre-configured :class:`httpx.Client` for OpenRouter.
        system_prompt: System-level instruction for the model.
        user_message: User-facing message / document text.
        images: Optional list of base64-encoded JPEG strings to include
            as vision input alongside the text.
        temperature: Sampling temperature.
        max_tokens: Maximum tokens in the response.

    Returns:
        The assistant message content as a string.

    Raises:
        httpx.HTTPStatusError: If the API returns a non-2xx status.
        KeyError: If the response structure is unexpected.
    """
    # MiniCPM5-2B is a TEXT-ONLY model. Never send images to the llamacpp
    # provider, even if a caller still passes some (e.g. legacy procedure
    # analysis path). Images are handled upstream by OvisOCR3.
    text_only = _cfg.AI_PROVIDER == "llamacpp"
    if text_only and images:
        logger.info(
            "Ignoring %d image(s): the llamacpp provider is text-only",
            len(images),
        )
        images = None

    # Build user content — multimodal only for vision-capable providers
    if images:
        user_content: list[dict] | str = [
            {"type": "text", "text": user_message},
        ]
        for img_b64 in images[:_MAX_IMAGES]:
            user_content.append({
                "type": "image_url",
                "image_url": {
                    "url": f"data:image/jpeg;base64,{img_b64}",
                },
            })
        logger.info(
            "Multimodal request: text + %d image(s)",
            min(len(images), _MAX_IMAGES),
        )
    else:
        user_content = user_message

    payload = {
        "model": _active_model(),
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ],
        "temperature": temperature,
        "max_tokens": max_tokens,
        "max_completion_tokens": max_tokens,
    }
    if text_only and _cfg.LLM_DISABLE_THINKING:
        payload["chat_template_kwargs"] = {"enable_thinking": False}

    response = client.post("/chat/completions", json=payload)
    response.raise_for_status()

    data = response.json()
    choice = data["choices"][0]
    content = choice["message"]["content"]

    # Log finish reason to detect truncation
    finish_reason = choice.get("finish_reason", "unknown")
    if finish_reason == "length":
        logger.warning(
            "LLM response was truncated (finish_reason=length) — "
            "consider increasing max_tokens (currently %d)",
            max_tokens,
        )

    # Log token usage when available
    usage = data.get("usage")
    if usage:
        logger.info(
            "LLM usage — prompt: %d tokens, completion: %d tokens, total: %d tokens, finish: %s",
            usage.get("prompt_tokens", 0),
            usage.get("completion_tokens", 0),
            usage.get("total_tokens", 0),
            finish_reason,
        )

    return content


def _strip_code_fences(text: str) -> str:
    """Remove a surrounding Markdown code fence, if present."""
    text = text.strip()
    fence = re.search(r"```(?:json)?\s*\n?(.*?)```", text, re.DOTALL)
    if fence:
        return fence.group(1).strip()
    return text


def _balanced_json_text(text: str, opener: str) -> str | None:
    """Return the first balanced JSON value starting at *opener*.

    Handles strings, escapes and truncated output (the missing closing
    brackets/quote are appended automatically).
    """
    start = text.find(opener)
    if start == -1:
        return None

    stack: list[str] = []
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char in "{[":
            stack.append(char)
        elif char in "}]":
            if not stack:
                break
            expected = "}" if stack[-1] == "{" else "]"
            if char != expected:
                break
            stack.pop()
            if not stack:
                return text[start:index + 1]

    # Truncated response: close the open string and structures.
    fragment = text[start:]
    if in_string:
        fragment += '"'
    for char in reversed(stack):
        fragment += "}" if char == "{" else "]"
    return fragment


def _extract_json(response_text: str, opener: str = "{"):
    """Extract a JSON object/array from an LLM response, with repair.

    Tries a direct parse, then a balanced-bracket extraction, then a repair
    of trailing commas. Returns ``None`` when nothing usable is found.
    """
    text = _strip_code_fences(response_text)
    candidates: list[str] = [text]

    balanced = _balanced_json_text(text, opener)
    if balanced and balanced != text:
        candidates.append(balanced)

    for candidate in list(candidates):
        repaired = re.sub(r",\s*([}\]])", r"\1", candidate)
        if repaired != candidate:
            candidates.append(repaired)

    for candidate in candidates:
        try:
            return json.loads(candidate)
        except (json.JSONDecodeError, TypeError):
            continue
    return None


def _parse_and_validate_metadata(
    response_text: str,
    source_text: str = "",
    filename: str | None = None,
    preferred_title: str | None = None,
) -> Optional[dict]:
    """Parse LLM output into a validated metadata dictionary.

    Attempts to extract a JSON object from *response_text* even when the
    model wraps its answer with markdown code fences or additional prose.
    Validates required fields, normalises values, and returns ``None``
    when parsing or validation fails.

    Args:
        response_text: Raw text returned by the LLM.

    Returns:
        Validated metadata dict, or ``None`` on failure.
    """
    parsed = _extract_json(response_text, "{")

    if not isinstance(parsed, dict):
        logger.warning("Failed to extract JSON object from LLM response")
        logger.debug("Full raw LLM response (%d chars):\n%s", len(response_text), response_text)
        return None

    # --- Validate required fields -------------------------------------------
    required_fields = {"titre", "type", "emetteur", "date", "resume", "tags"}
    if not required_fields.issubset(parsed.keys()):
        missing = required_fields - parsed.keys()
        logger.warning("Metadata missing required fields: %s", missing)
        # If only titre is missing, generate a fallback title
        if missing == {"titre"}:
            parsed["titre"] = "Document sans titre"
            logger.debug("Using fallback title for missing 'titre' field")
        else:
            return None

    # --- Normalise values ---------------------------------------------------

    # titre: ensure non-empty string
    if not parsed.get("titre") or not isinstance(parsed["titre"], str):
        parsed["titre"] = "Document sans titre"

    # type: alias/keyword normalisation (never silently fall back to autre)
    parsed["type"] = normalize_doc_type(
        parsed.get("type"),
        title=str(parsed.get("titre") or preferred_title or ""),
        emetteur=str(parsed.get("emetteur") or ""),
        resume=str(parsed.get("resume") or ""),
        tags=parsed.get("tags") if isinstance(parsed.get("tags"), list) else None,
        text=source_text,
    )

    # tags: ensure list of strings
    if not isinstance(parsed["tags"], list):
        parsed["tags"] = []
    else:
        parsed["tags"] = [str(t) for t in parsed["tags"]]

    # montant: ensure float or None
    montant = parsed.get("montant")
    if montant is not None:
        try:
            parsed["montant"] = float(montant)
        except (ValueError, TypeError):
            parsed["montant"] = None

    # Ensure optional string fields default to None
    for key in ("reference", "destinataire"):
        if key not in parsed:
            parsed[key] = None

    # date_expiration / date_echeance: validate YYYY-MM-DD format or set to None
    _date_re = re.compile(r"^\d{4}-\d{2}-\d{2}$")
    for date_key in ("date_expiration", "date_echeance"):
        val = parsed.get(date_key)
        if val is not None and isinstance(val, str) and val.strip():
            val = val.strip()
            if _date_re.match(val):
                parsed[date_key] = val
            else:
                logger.debug("Invalid %s format '%s' — setting to None", date_key, val)
                parsed[date_key] = None
        else:
            parsed[date_key] = None

    return finalize_metadata(
        parsed,
        text=source_text,
        filename=filename,
        preferred_title=preferred_title,
    )


def _chunk_text(text: str, max_chars: int) -> list[str]:
    """Split a long OCR text into page-aware chunks of at most *max_chars*."""
    if len(text) <= max_chars:
        return [text]

    parts = re.split(r"(?=--- Page \d+ ---)", text)
    chunks: list[str] = []
    current = ""
    for part in parts:
        if not part:
            continue
        if len(current) + len(part) > max_chars and current:
            chunks.append(current)
            current = part
        else:
            current += part
        # A single page can itself exceed the limit.
        while len(current) > max_chars:
            chunks.append(current[:max_chars])
            current = current[max_chars:]
    if current:
        chunks.append(current)
    return chunks


def _merge_partial_metadata(partials: list[dict]) -> dict:
    """Heuristic merge used when the LLM merge step fails."""
    if not partials:
        return _fallback_metadata()

    def first(key: str, default=None):
        for item in partials:
            value = item.get(key)
            if value not in (None, "", []):
                return value
        return default

    types = [p.get("type") for p in partials if p.get("type") in VALID_DOC_TYPES]
    montants = [p["montant"] for p in partials if isinstance(p.get("montant"), (int, float))]
    tags: list[str] = []
    for item in partials:
        for tag in item.get("tags") or []:
            if tag not in tags:
                tags.append(tag)

    return {
        "titre": first("titre", "Document long"),
        "type": max(set(types), key=types.count) if types else "autre",
        "emetteur": first("emetteur", ""),
        "date": first("date", ""),
        "montant": max(montants) if montants else None,
        "reference": first("reference"),
        "destinataire": first("destinataire"),
        "resume": first("resume", "Document long fusionné"),
        "tags": tags[:5],
        "date_expiration": first("date_expiration"),
        "date_echeance": first("date_echeance"),
    }


def _fallback_metadata() -> dict:
    return {
        "titre": "Document non classifié",
        "type": "autre",
        "emetteur": "",
        "date": "",
        "montant": None,
        "reference": None,
        "destinataire": None,
        "resume": "Classification automatique échouée",
        "tags": [],
        "date_expiration": None,
        "date_echeance": None,
    }


def _metadata_for_chunk(
    client,
    chunk: str,
    index: int,
    total: int,
    filename: str | None = None,
) -> dict | None:
    """Extract metadata from one chunk of a long document (map step)."""
    user_message = (
        f"{OCR_TEXT_ONLY_NOTE}\n\n"
        f"Ceci est le bloc {index}/{total} d'un document long. "
        "Extrais les métadonnées visibles dans CE BLOC uniquement.\n\n"
        f"{chunk}"
    )
    try:
        raw = _call_llm(
            client,
            system_prompt=METADATA_EXTRACTION_PROMPT,
            user_message=user_message,
        )
        return _parse_and_validate_metadata(raw, source_text=chunk, filename=filename)
    except Exception:
        logger.exception("Map metadata extraction failed for chunk %d/%d", index, total)
        return None


def _extract_metadata_map_reduce(
    client,
    ocr_text: str,
    filename: str | None = None,
    preferred_title: str | None = None,
) -> dict:
    """Map-reduce metadata extraction for documents above the context budget."""
    chunks = _chunk_text(ocr_text, _cfg.LLM_MAP_CHUNK_CHARS)
    logger.info(
        "Long document (%d chars) — map-reduce metadata over %d chunk(s)",
        len(ocr_text),
        len(chunks),
    )
    partials = [
        metadata
        for i, chunk in enumerate(chunks, 1)
        if (metadata := _metadata_for_chunk(client, chunk, i, len(chunks), filename)) is not None
    ]
    if not partials:
        return finalize_metadata(
            _fallback_metadata(),
            text=ocr_text,
            filename=filename,
            preferred_title=preferred_title,
        )

    # Reduce step: let the LLM merge the partial metadata.
    try:
        raw = _call_llm(
            client,
            system_prompt=METADATA_MERGE_PROMPT,
            user_message=json.dumps(partials, ensure_ascii=False),
        )
        merged = _parse_and_validate_metadata(
            raw,
            source_text=ocr_text,
            filename=filename,
            preferred_title=preferred_title,
        )
        if merged is not None:
            return merged
    except Exception:
        logger.exception("Reduce metadata extraction failed")

    logger.warning("LLM merge failed — using heuristic metadata merge")
    return finalize_metadata(
        _merge_partial_metadata(partials),
        text=ocr_text,
        filename=filename,
        preferred_title=preferred_title,
    )


def extract_metadata(
    client: httpx.Client,
    ocr_text: str,
    images: list[str] | None = None,
    filename: str | None = None,
    preferred_title: str | None = None,
) -> dict:
    """Extract structured metadata from OCR text (text-only MiniCPM).

    For long documents the text is split into page-aware chunks, metadata is
    extracted per chunk, then merged (map-reduce). Makes one repair attempt
    if the first response is not valid JSON before returning a clean fallback.

    Args:
        client: Pre-configured :class:`httpx.Client` for the LLM provider.
        ocr_text: Text extracted via OCR / native PDF parsing.
        images: Ignored for the text-only llamacpp provider; forwarded to
            vision-capable providers only.

    Returns:
        Dictionary with the document metadata fields.
    """
    def _fallback() -> dict:
        return finalize_metadata(
            _fallback_metadata(),
            text=ocr_text,
            filename=filename,
            preferred_title=preferred_title,
        )

    if not ocr_text or not ocr_text.strip():
        return _fallback()

    if len(ocr_text) > _cfg.LLM_MAP_CHUNK_CHARS:
        return _extract_metadata_map_reduce(
            client,
            ocr_text,
            filename=filename,
            preferred_title=preferred_title,
        )

    truncated_text = ocr_text[:_MAX_OCR_CHARS]
    user_message = f"{OCR_TEXT_ONLY_NOTE}\n\n{truncated_text}"

    logger.info("Extracting metadata (attempt 1)…")
    try:
        raw_response = _call_llm(
            client,
            system_prompt=METADATA_EXTRACTION_PROMPT,
            user_message=user_message,
            images=images,
        )
        metadata = _parse_and_validate_metadata(
            raw_response,
            source_text=truncated_text,
            filename=filename,
            preferred_title=preferred_title,
        )
    except Exception:
        logger.exception("LLM call failed during metadata extraction (attempt 1)")
        metadata = None

    if metadata is not None:
        logger.info(
            "Metadata extracted successfully on first attempt (type=%s, titre='%s')",
            metadata["type"],
            metadata.get("titre", ""),
        )
        return metadata

    # One repair attempt, text-only.
    logger.warning("First attempt failed; retrying with correction prompt…")
    try:
        correction_user_msg = METADATA_CORRECTION_PROMPT.format(text=truncated_text)
        raw_response = _call_llm(
            client,
            system_prompt=METADATA_EXTRACTION_PROMPT,
            user_message=correction_user_msg,
        )
        metadata = _parse_and_validate_metadata(
            raw_response,
            source_text=truncated_text,
            filename=filename,
            preferred_title=preferred_title,
        )
    except Exception:
        logger.exception("LLM call failed during metadata extraction (attempt 2)")
        metadata = None

    if metadata is not None:
        logger.info("Metadata extracted on retry (type=%s)", metadata["type"])
        return metadata

    logger.error("Both metadata extraction attempts failed — returning default metadata")
    return _fallback()


# ---------------------------------------------------------------------------
# Folder-sync ingestion judge
# ---------------------------------------------------------------------------

_JUDGE_MAX_CHARS = 8000


def judge_document(
    client: httpx.Client,
    ocr_text: str,
    filename: str | None = None,
) -> dict:
    """Decide whether a synced file deserves to be archived.

    Returns ``{"keep": bool, "confidence": float, "reason": str}``. Any
    failure yields a low-confidence ``keep=False`` result so the caller can
    route the file to manual review instead of silently archiving it.
    """
    text = (ocr_text or "").strip()
    if not text:
        return {
            "keep": False,
            "confidence": 0.0,
            "reason": "Document vide ou texte illisible",
        }

    user_message = (
        f"Nom du fichier : {filename or 'inconnu'}\n\n"
        f"Texte extrait :\n{text[:_JUDGE_MAX_CHARS]}"
    )
    try:
        raw = _call_llm(
            client,
            system_prompt=JUDGE_PROMPT,
            user_message=user_message,
            temperature=0.0,
            max_tokens=400,
        )
        data = _extract_json(raw)
    except Exception:
        logger.exception("Judge LLM call failed")
        return {
            "keep": False,
            "confidence": 0.0,
            "reason": "Juge indisponible (erreur LLM)",
        }

    if not isinstance(data, dict) or "keep" not in data:
        logger.warning("Judge returned an unusable response: %r", raw[:300])
        return {
            "keep": False,
            "confidence": 0.0,
            "reason": "Réponse du juge illisible",
        }

    keep = data.get("keep")
    if isinstance(keep, str):
        keep = keep.strip().lower() in {"true", "oui", "yes", "1"}
    else:
        keep = bool(keep)

    try:
        confidence = float(data.get("confidence", 0.0))
    except (TypeError, ValueError):
        confidence = 0.0
    confidence = max(0.0, min(1.0, confidence))

    reason = str(data.get("reason") or "").strip()[:400]
    return {"keep": keep, "confidence": confidence, "reason": reason}


# ---------------------------------------------------------------------------
# Multi-document segmentation
# ---------------------------------------------------------------------------

def _sanitize_segments(raw_segments, pages_total: int) -> list[dict]:
    """Validate and normalise the segment list returned by the LLM."""
    if not isinstance(raw_segments, list) or not raw_segments:
        return []

    cleaned: list[dict] = []
    for item in raw_segments:
        if not isinstance(item, dict):
            continue
        pages = item.get("pages")
        if not isinstance(pages, (list, tuple)) or len(pages) != 2:
            continue
        try:
            start, end = int(pages[0]), int(pages[1])
        except (TypeError, ValueError):
            continue
        start = max(1, min(start, pages_total))
        end = max(1, min(end, pages_total))
        if start > end:
            start, end = end, start
        doc_type = item.get("type") if item.get("type") in VALID_DOC_TYPES else "autre"
        title = item.get("titre") or item.get("title") or None
        cleaned.append({
            "pages": [start, end],
            "type": doc_type,
            "titre": str(title).strip() if title else None,
        })

    cleaned.sort(key=lambda x: x["pages"][0])

    # Remove overlaps and cover every page exactly once.
    result: list[dict] = []
    expected = 1
    for segment in cleaned:
        start, end = segment["pages"]
        start = max(start, expected)
        if start > end:
            continue
        segment["pages"] = [start, end]
        result.append(segment)
        expected = end + 1

    if not result:
        return []
    # Extend the first/last segments so all pages are included.
    if result[0]["pages"][0] > 1:
        result[0]["pages"][0] = 1
    if result[-1]["pages"][1] < pages_total:
        result[-1]["pages"][1] = pages_total

    # Safety valve: never produce an absurd number of segments.
    if len(result) > max(1, pages_total):
        return []
    return result


def segment_documents(client: httpx.Client, pages: list[str]) -> list[dict]:
    """Ask MiniCPM whether a scanned file contains multiple documents.

    Returns a list of ``{"pages": [start, end], "type": str, "titre": str}``
    segments covering all pages. Falls back to a single document whenever
    the answer is missing, invalid or uncertain.
    """
    pages_total = len(pages)
    single = [{"pages": [1, pages_total], "type": None, "titre": None}]
    if pages_total <= 1 or not _cfg.SEGMENT_MULTI_DOC:
        return single
    if pages_total > 60:
        logger.info("Segmentation skipped for %d-page file (likely one document)", pages_total)
        return single

    # Very short OCR pages are unlikely to carry enough signal to split safely.
    non_empty = sum(1 for p in pages if len((p or "").strip()) >= 30)
    if non_empty < 2:
        return single

    try:
        raw = _call_llm(
            client,
            system_prompt=SEGMENTATION_PROMPT,
            user_message=segmentation_user_message(pages),
            max_tokens=2048,
        )
        parsed = _extract_json(raw, "[")
        segments = _sanitize_segments(parsed, pages_total)
    except Exception:
        logger.exception("Segmentation LLM call failed — keeping a single document")
        return single

    if len(segments) <= 1:
        logger.info("Segmentation: single document across %d page(s)", pages_total)
        return single

    logger.info(
        "Segmentation: %d documents detected across %d pages — %s",
        len(segments),
        pages_total,
        ", ".join(f"{s['pages'][0]}-{s['pages'][1]}" for s in segments),
    )
    return segments


def _build_rag_context(context_documents: list[dict]) -> str:
    """Build a RAG context string from a list of document dicts.

    Args:
        context_documents: List of document dicts.

    Returns:
        Formatted context string for the system prompt.
    """
    context_parts: list[str] = []
    for doc in context_documents:
        doc_type = doc.get("doc_type", "inconnu")
        emetteur = doc.get("emetteur", "inconnu")
        doc_date = doc.get("doc_date", "date inconnue")
        text_content = doc.get("text_content", "")
        truncated_content = text_content[:_MAX_RAG_DOC_CHARS]
        context_parts.append(
            f"[Document - {doc_type} - {emetteur} - {doc_date}]\n"
            f"{truncated_content}\n---"
        )
    return "\n\n".join(context_parts)


def chat_with_context(
    client: httpx.Client,
    user_message: str,
    context_documents: list[dict],
) -> str:
    """Answer a user question using RAG over provided document contexts.

    Single-turn version (no conversation history).

    Args:
        client: Pre-configured :class:`httpx.Client` for OpenRouter.
        user_message: The user's natural-language question.
        context_documents: List of document dicts, each expected to contain
            at least ``doc_type``, ``emetteur``, ``doc_date``, and
            ``text_content`` keys.

    Returns:
        The assistant's response text.
    """
    context_str = _build_rag_context(context_documents)
    system_prompt = RAG_CHAT_PROMPT.format(context=context_str)

    response = _call_llm(
        client,
        system_prompt=system_prompt,
        user_message=user_message,
    )

    logger.info("Chat response generated (%d chars)", len(response))
    return response


# Maximum number of conversation-history messages to include
_MAX_HISTORY_MESSAGES = 20


def chat_with_context_multiturn(
    client: httpx.Client,
    user_message: str,
    context_documents: list[dict],
    conversation_history: list[dict],
) -> str:
    """Answer a user question using RAG with multi-turn conversation memory.

    Sends the past conversation messages to the LLM so it can maintain
    coherence across the session.

    Args:
        client: Pre-configured :class:`httpx.Client` for OpenRouter.
        user_message: The user's latest question.
        context_documents: List of document dicts for RAG context.
        conversation_history: List of ``{role, content}`` dicts representing
            prior messages in the session (chronological order).

    Returns:
        The assistant's response text.
    """
    context_str = _build_rag_context(context_documents)
    system_prompt = RAG_CHAT_PROMPT.format(context=context_str)

    # Build the messages array: system + history + current user message
    messages: list[dict] = [{"role": "system", "content": system_prompt}]

    # Add conversation history (truncated to last N messages)
    history = conversation_history[-_MAX_HISTORY_MESSAGES:]
    for msg in history:
        messages.append({"role": msg["role"], "content": msg["content"]})

    # Add the current user message
    messages.append({"role": "user", "content": user_message})

    payload = {
        "model": _active_model(),
        "messages": messages,
        "temperature": _cfg.LLM_TEMPERATURE,
        "max_tokens": _cfg.LLM_MAX_TOKENS,
        "max_completion_tokens": _cfg.LLM_MAX_TOKENS,
    }

    response = client.post("/chat/completions", json=payload)
    response.raise_for_status()

    data = response.json()
    choice = data["choices"][0]
    content = choice["message"]["content"]

    finish_reason = choice.get("finish_reason", "unknown")
    if finish_reason == "length":
        logger.warning(
            "LLM response was truncated (finish_reason=length) — "
            "consider increasing max_tokens (currently %d)",
            _cfg.LLM_MAX_TOKENS,
        )

    usage = data.get("usage")
    if usage:
        logger.info(
            "Chat multiturn usage — prompt: %d tokens, completion: %d tokens, "
            "total: %d tokens, history_msgs: %d, finish: %s",
            usage.get("prompt_tokens", 0),
            usage.get("completion_tokens", 0),
            usage.get("total_tokens", 0),
            len(history),
            finish_reason,
        )

    logger.info(
        "Chat multiturn response generated (%d chars, %d history messages)",
        len(content), len(history),
    )
    return content


# ---------------------------------------------------------------------------
# Procedure analysis
# ---------------------------------------------------------------------------

def _parse_procedure_json(response_text: str) -> dict | None:
    """Parse and validate the LLM procedure analysis JSON response.

    Args:
        response_text: Raw text returned by the LLM.

    Returns:
        Validated procedure dict with name, description, required_documents,
        or None on failure.
    """
    text = response_text.strip()
    logger.debug("Raw procedure LLM response (%d chars):\n%s", len(text), text[:2000])

    # Strip markdown code fences
    fence_match = re.search(r'```(?:json)?\s*\n?(.*?)```', text, re.DOTALL)
    if fence_match:
        text = fence_match.group(1).strip()
        logger.debug("Stripped markdown code fence from procedure response")

    parsed: dict | None = None

    # Strategy 1: parse directly
    try:
        parsed = json.loads(text)
        logger.debug("Strategy 1 (direct parse) succeeded")
    except (json.JSONDecodeError, TypeError) as e:
        logger.debug("Strategy 1 (direct parse) failed: %s", e)

    # Strategy 2: extract between first { and last }
    if parsed is None:
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end != -1 and end > start:
            try:
                parsed = json.loads(text[start:end + 1])
                logger.debug("Strategy 2 (extract braces) succeeded")
            except (json.JSONDecodeError, TypeError) as e:
                logger.debug("Strategy 2 (extract braces) failed: %s", e)

    # Strategy 3: repair truncated JSON — append missing closing brackets
    if parsed is None:
        start = text.find("{")
        if start != -1:
            fragment = text[start:]
            for suffix in ["}", "]}", "\"]}",  "\"]}", "\"\n  ]\n}"]:
                try:
                    parsed = json.loads(fragment + suffix)
                    logger.info("Strategy 3 (JSON repair) succeeded with suffix: %r", suffix)
                    break
                except (json.JSONDecodeError, TypeError):
                    continue

    if not isinstance(parsed, dict):
        logger.warning("Failed to parse procedure analysis JSON")
        logger.info("Full raw LLM procedure response (%d chars):\n%s", len(response_text), response_text)
        return None

    # Validate required fields — name is optional (can be set by user), required_documents is mandatory
    if "required_documents" not in parsed:
        logger.warning("Procedure JSON missing 'required_documents' field. Keys found: %s", list(parsed.keys()))
        logger.info("Parsed JSON content: %s", json.dumps(parsed, ensure_ascii=False)[:1000])
        return None

    # Default name if missing
    if "name" not in parsed:
        parsed["name"] = "Nouvelle procédure"
        logger.debug("No 'name' in parsed JSON — using default")

    # Normalize required_documents
    if not isinstance(parsed["required_documents"], list):
        parsed["required_documents"] = []

    validated_docs: list[dict] = []
    for doc in parsed["required_documents"]:
        if not isinstance(doc, dict):
            continue
        doc_type = doc.get("doc_type", "autre")
        if doc_type not in VALID_DOC_TYPES:
            doc_type = "autre"
        validated_docs.append({
            "doc_type": doc_type,
            "label": doc.get("label", doc_type),
            "description": doc.get("description"),
        })

    parsed["required_documents"] = validated_docs
    return parsed


def analyze_procedure(
    client: httpx.Client,
    procedure_type: str,
    image_b64: str | None = None,
    manual_documents: list[str] | None = None,
    remarks: str | None = None,
) -> dict:
    """Analyze a procedure description/image and return structured JSON.

    Uses the LLM to identify the required documents for a given procedure
    type. Supports multimodal input (image of required documents list).

    Args:
        client: Pre-configured httpx.Client for OpenRouter.
        procedure_type: Category of procedure (administrative, bancaire, etc.).
        image_b64: Optional base64-encoded image of the documents list.
        manual_documents: Optional manually entered list of document descriptions.
        remarks: Additional context or remarks from the user.

    Returns:
        Dict with keys: name, description, required_documents.
    """
    # Build user message
    parts: list[str] = [f"Type de procédure : {procedure_type}"]

    if manual_documents:
        parts.append("\nDocuments listés par l'utilisateur :")
        for i, doc in enumerate(manual_documents, 1):
            parts.append(f"  {i}. {doc}")

    if remarks:
        parts.append(f"\nRemarques supplémentaires : {remarks}")

    if image_b64:
        parts.append("\nUne image listant les documents nécessaires est fournie ci-joint.")

    user_message = "\n".join(parts)
    system_prompt = PROCEDURE_ANALYSIS_PROMPT.format(procedure_type=procedure_type)

    images = [image_b64] if image_b64 else None

    logger.info("Analyzing procedure (type=%s, has_image=%s, manual_docs=%d)",
                procedure_type, image_b64 is not None,
                len(manual_documents) if manual_documents else 0)

    try:
        raw_response = _call_llm(
            client,
            system_prompt=system_prompt,
            user_message=user_message,
            images=images,
            max_tokens=8192,
        )
        result = _parse_procedure_json(raw_response)
    except Exception:
        logger.exception("LLM call failed during procedure analysis")
        result = None

    if result is not None:
        logger.info("Procedure analysis successful: '%s' with %d required documents",
                     result.get("name", ""), len(result.get("required_documents", [])))
        return result

    # Fallback
    logger.error("Procedure analysis failed — returning minimal fallback")
    return {
        "name": f"Procédure {procedure_type}",
        "description": "Procédure créée (analyse automatique échouée)",
        "required_documents": [],
    }


def match_document_for_procedure(
    client: httpx.Client,
    required_doc: dict,
    person_name: str,
    candidate_docs: list[dict],
) -> dict:
    """Use the LLM to select the best matching document from candidates.

    Args:
        client: Pre-configured httpx.Client for OpenRouter.
        required_doc: Dict with doc_type, label, description of the required document.
        person_name: Full name of the person.
        candidate_docs: List of document dicts to evaluate.

    Returns:
        Dict with selected_id (str or None), confidence (float), reason (str).
    """
    if not candidate_docs:
        return {"selected_id": None, "confidence": 0.0, "reason": "Aucun document candidat trouvé"}

    # Build candidates description for the LLM
    candidates_parts: list[str] = []
    for doc in candidate_docs:
        text_preview = (doc.get("text_content") or "")[:500]
        candidates_parts.append(
            f"--- Document ID: {doc['id']} ---\n"
            f"  Titre: {doc.get('title', 'N/A')}\n"
            f"  Fichier: {doc.get('filename', 'N/A')}\n"
            f"  Type: {doc.get('doc_type', 'N/A')}\n"
            f"  Émetteur: {doc.get('emetteur', 'N/A')}\n"
            f"  Destinataire: {doc.get('destinataire', 'N/A')}\n"
            f"  Date: {doc.get('doc_date', 'N/A')}\n"
            f"  Résumé: {doc.get('resume', 'N/A')}\n"
            f"  Contenu (extrait): {text_preview}\n"
        )

    candidates_str = "\n".join(candidates_parts)

    system_prompt = PROCEDURE_MATCH_PROMPT.format(
        doc_type=required_doc.get("doc_type", "autre"),
        label=required_doc.get("label", ""),
        person_name=person_name,
        candidates=candidates_str,
    )

    logger.info("Matching document for requirement '%s' (person=%s, %d candidates)",
                required_doc.get("label", ""), person_name, len(candidate_docs))

    try:
        raw_response = _call_llm(
            client,
            system_prompt=system_prompt,
            user_message=f"Trouve le meilleur document correspondant à : {required_doc.get('label', '')} pour {person_name}",
            max_tokens=8192,
        )

        # Parse JSON response
        text = raw_response.strip()
        fence_match = re.search(r'```(?:json)?\s*\n?(.*?)```', text, re.DOTALL)
        if fence_match:
            text = fence_match.group(1).strip()

        parsed = None
        try:
            parsed = json.loads(text)
        except (json.JSONDecodeError, TypeError):
            start = text.find("{")
            end = text.rfind("}")
            if start != -1 and end != -1 and end > start:
                try:
                    parsed = json.loads(text[start:end + 1])
                except (json.JSONDecodeError, TypeError):
                    pass

        if isinstance(parsed, dict):
            selected_id = parsed.get("selected_id")
            # Validate the selected ID exists in candidates
            valid_ids = {doc["id"] for doc in candidate_docs}
            if selected_id and selected_id not in valid_ids:
                logger.warning("LLM selected invalid document ID '%s'", selected_id)
                selected_id = None

            return {
                "selected_id": selected_id,
                "confidence": float(parsed.get("confidence", 0.5)),
                "reason": parsed.get("reason", "Sélection par IA"),
            }

    except Exception:
        logger.exception("LLM call failed during document matching")

    return {"selected_id": None, "confidence": 0.0, "reason": "Échec de l'analyse IA"}
