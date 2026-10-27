"""Folder-sync ingestion: validation, judge and materialisation.

The desktop agent scans folders on a PC and sends only files it has never
seen. This module owns the server-side half of that contract:

1. revalidate the extension and magic bytes (never trust the client);
2. OCR the file (page cache reused) or read a ``.txt`` directly;
3. ask the text-only LLM judge whether the file deserves archiving;
4. either create a normal document reusing the OCR text, reject the file, or
   park it as ``pending`` for manual review.

Everything is driven by the ``file_marks`` table, keyed by SHA-256, so a file
that was accepted or rejected is never processed again even if renamed.
"""

from __future__ import annotations

import hashlib
import logging
import os
import re
import shutil
import time
import uuid
from pathlib import Path

import httpx

import config
from database import (
    get_document,
    get_file_mark,
    insert_document,
    update_document_hash,
    update_file_mark,
    upsert_file_mark,
)
from llm import judge_document
from ocr import extract_pages
from pipeline import process_extracted_pages, split_pages

logger = logging.getLogger(__name__)

_SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]+")


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

def sha256_file(path: str | Path) -> str:
    """Return the SHA-256 hex digest of a file."""
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_filename(name: str) -> str:
    """Return a filesystem-safe basename for an uploaded candidate."""
    base = Path(name or "document").name
    cleaned = _SAFE_NAME.sub("_", base).strip("._") or "document"
    return cleaned[:180]


def _check_txt(data: bytes) -> tuple[bool, str]:
    if b"\x00" in data:
        return False, "Fichier texte contenant des octets nuls"
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("latin-1")
    if not text.strip():
        return False, "Fichier texte vide"
    control = sum(
        1 for ch in text if ord(ch) < 32 and ch not in "\n\r\t"
    )
    if control > max(8, len(text) // 20):
        return False, "Fichier texte binaire ou corrompu"
    return True, ""


def check_magic_bytes(filename: str, data: bytes) -> tuple[bool, str]:
    """Validate the extension + magic bytes of a candidate file.

    Returns ``(ok, reason)``. *data* must contain at least the file header
    (the whole file for ``.txt``).
    """
    ext = Path(filename or "").suffix.lower()
    if ext not in config.INGEST_ALLOWED_EXTENSIONS:
        return False, f"Extension non autorisée : {ext or '(aucune)'}"

    if len(data) == 0:
        return False, "Fichier vide"
    if len(data) < config.INGEST_MIN_SIZE_BYTES:
        return False, "Fichier trop petit (< 1 Ko)"
    if len(data) > config.INGEST_MAX_SIZE_BYTES:
        return False, "Fichier trop volumineux (> 50 Mo)"

    head = data[:16]
    if ext == ".pdf":
        if not head.startswith(b"%PDF"):
            return False, "Signature PDF invalide"
        return True, ""
    if ext == ".png":
        if not head.startswith(b"\x89PNG\r\n\x1a\n"):
            return False, "Signature PNG invalide"
        return True, ""
    if ext in {".jpg", ".jpeg"}:
        if not head.startswith(b"\xff\xd8\xff"):
            return False, "Signature JPEG invalide"
        return True, ""
    if ext == ".bmp":
        if not head.startswith(b"BM"):
            return False, "Signature BMP invalide"
        return True, ""
    if ext == ".txt":
        return _check_txt(data)

    return False, f"Extension non autorisée : {ext}"


def validate_candidate_path(path: str | Path, filename: str | None = None) -> tuple[bool, str]:
    """Validate a file on disk (extension, size and magic bytes)."""
    path = Path(path)
    if not path.exists():
        return False, "Fichier introuvable"
    try:
        size = path.stat().st_size
    except OSError as exc:
        return False, f"Fichier inaccessible : {exc}"
    if size > config.INGEST_MAX_SIZE_BYTES:
        return False, "Fichier trop volumineux (> 50 Mo)"
    # Text validation needs the full payload; other formats only the header.
    to_read = size if (filename or path.name).lower().endswith(".txt") else min(size, 4096)
    with open(path, "rb") as fh:
        data = fh.read(to_read)
    ok, reason = check_magic_bytes(filename or path.name, data)
    return ok, reason


# ---------------------------------------------------------------------------
# Text extraction (OCR reuse)
# ---------------------------------------------------------------------------

def join_pages(pages: list[str]) -> str:
    """Join page texts with explicit page markers (1-based)."""
    return "\n\n".join(
        f"--- Page {i + 1} ---\n\n{text}" for i, text in enumerate(pages)
    )


def _read_text_file(path: Path) -> str:
    data = path.read_bytes()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def extract_candidate_pages(path: str | Path) -> list[str]:
    """Extract page texts from a validated candidate."""
    path = Path(path)
    if path.suffix.lower() == ".txt":
        return [_read_text_file(path)]
    return extract_pages(str(path))


# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

def decide_verdict(judge: dict, threshold: float | None = None) -> tuple[str, str]:
    """Map a judge result to ``accepted`` / ``rejected`` / ``pending``."""
    threshold = config.INGEST_JUDGE_CONFIDENCE if threshold is None else threshold
    confidence = float(judge.get("confidence") or 0.0)
    keep = bool(judge.get("keep"))
    reason = str(judge.get("reason") or "").strip() or "Aucune raison fournie"
    if confidence < threshold:
        return "pending", f"Confiance faible ({confidence:.2f}) — {reason}"
    return ("accepted" if keep else "rejected"), reason


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def _store_path_for(sha256: str, filename: str) -> str:
    return os.path.join(config.INGEST_DIR, f"{sha256[:16]}_{safe_filename(filename)}")


def register_candidate(
    *,
    sha256: str,
    filename: str,
    machine: str,
    origin_path: str,
    stored_path: str,
) -> dict:
    """Record a new candidate as pending before it is queued."""
    return upsert_file_mark(
        sha256,
        verdict="pending",
        source=machine,
        origin_path=origin_path,
        filename=safe_filename(filename),
        stored_path=stored_path,
        reason="En attente de traitement",
    )


def _delete_stored(mark: dict) -> None:
    stored = mark.get("stored_path")
    if stored:
        try:
            os.remove(stored)
        except OSError:
            logger.debug("Could not remove candidate file %s", stored, exc_info=True)


def _materialize(
    sha256: str,
    mark: dict,
    llm: httpx.Client,
    embedding_model,
    *,
    pages: list[str] | None = None,
    ocr_seconds: float | None = None,
) -> str | None:
    """Create a real document from an accepted mark and run the pipeline."""
    if mark.get("doc_id"):
        existing = get_document(mark["doc_id"])
        if existing is not None:
            return existing["id"]

    stored = mark.get("stored_path")
    if not stored or not Path(stored).exists():
        update_file_mark(
            sha256,
            verdict="error",
            reason="Fichier candidat absent du serveur",
        )
        return None

    filename = safe_filename(mark.get("filename") or Path(stored).name)
    doc_id = str(uuid.uuid4())
    dest = os.path.join(config.ORIGINALS_DIR, f"{doc_id}_{filename}")
    try:
        shutil.move(stored, dest)
    except OSError as exc:
        logger.exception("Could not move candidate %s into originals", sha256[:8])
        update_file_mark(sha256, verdict="error", reason=f"Déplacement impossible : {exc}")
        return None

    insert_document(doc_id, filename, dest)
    update_document_hash(doc_id, sha256)

    if pages is None:
        text = mark.get("text_content") or ""
        pages = split_pages(text) if text.strip() else None
    if pages is None:
        started = time.perf_counter()
        try:
            pages = extract_candidate_pages(dest)
            ocr_seconds = round(time.perf_counter() - started, 3)
        except Exception as exc:
            logger.exception("OCR failed while accepting candidate %s", sha256[:8])
            update_file_mark(
                sha256,
                verdict="error",
                doc_id=doc_id,
                reason=f"OCR impossible : {type(exc).__name__}",
                stored_path=None,
            )
            return doc_id

    update_file_mark(
        sha256,
        verdict="accepted",
        doc_id=doc_id,
        stored_path=None,
        text_content=None,
        reason=mark.get("reason") or "Accepté par le juge",
    )
    try:
        process_extracted_pages(
            doc_id,
            dest,
            pages,
            llm,
            embedding_model,
            ocr_label="ingest",
            ocr_seconds=ocr_seconds,
        )
    except Exception as exc:
        logger.exception("Pipeline failed after accepting candidate %s", sha256[:8])
        update_file_mark(
            sha256,
            verdict="error",
            doc_id=doc_id,
            reason=f"Pipeline : {type(exc).__name__}",
        )
    return doc_id


def process_candidate(
    sha256: str,
    llm: httpx.Client,
    embedding_model,
) -> None:
    """Run validation → OCR → judge for a pending candidate."""
    mark = get_file_mark(sha256)
    if mark is None:
        logger.warning("Candidate %s has no mark — ignoring", sha256[:8])
        return
    if mark.get("verdict") in {"accepted", "rejected"}:
        logger.info("Candidate %s already %s — skipping", sha256[:8], mark["verdict"])
        return

    stored = mark.get("stored_path")
    if not stored or not Path(stored).exists():
        update_file_mark(sha256, verdict="error", reason="Fichier candidat absent")
        return

    ok, reason = validate_candidate_path(stored, mark.get("filename"))
    if not ok:
        _delete_stored(mark)
        update_file_mark(
            sha256,
            verdict="rejected",
            reason=reason,
            stored_path=None,
            text_content=None,
        )
        logger.info("Candidate %s rejected by server validation: %s", sha256[:8], reason)
        return

    started = time.perf_counter()
    try:
        pages = extract_candidate_pages(stored)
    except Exception as exc:
        logger.exception("OCR failed for candidate %s", sha256[:8])
        update_file_mark(
            sha256,
            verdict="error",
            reason=f"OCR impossible : {type(exc).__name__}",
        )
        return
    ocr_seconds = round(time.perf_counter() - started, 3)
    text = join_pages(pages)

    if llm is None:
        update_file_mark(
            sha256,
            verdict="pending",
            text_content=text,
            reason="Juge indisponible : LLM non chargé",
        )
        return

    judge = judge_document(llm, text, filename=mark.get("filename"))
    verdict, verdict_reason = decide_verdict(judge)
    confidence = float(judge.get("confidence") or 0.0)

    if verdict == "accepted":
        update_file_mark(
            sha256,
            verdict="pending",
            text_content=text,
            reason=verdict_reason,
            confidence=confidence,
        )
        _materialize(
            sha256,
            {**mark, "text_content": text, "reason": verdict_reason},
            llm,
            embedding_model,
            pages=pages,
            ocr_seconds=ocr_seconds,
        )
        logger.info("Candidate %s accepted (%s)", sha256[:8], verdict_reason)
        return

    if verdict == "rejected":
        _delete_stored(mark)
        update_file_mark(
            sha256,
            verdict="rejected",
            reason=verdict_reason,
            confidence=confidence,
            stored_path=None,
            text_content=None,
        )
        logger.info("Candidate %s rejected (%s)", sha256[:8], verdict_reason)
        return

    update_file_mark(
        sha256,
        verdict="pending",
        text_content=text,
        reason=verdict_reason,
        confidence=confidence,
    )
    logger.info("Candidate %s pending manual review (%s)", sha256[:8], verdict_reason)


def accept_mark(
    sha256: str,
    llm: httpx.Client,
    embedding_model,
) -> dict | None:
    """Manually accept a pending mark and materialise the document."""
    mark = get_file_mark(sha256)
    if mark is None:
        return None
    if mark.get("verdict") == "accepted" and mark.get("doc_id"):
        return mark
    if not mark.get("stored_path"):
        update_file_mark(
            sha256,
            verdict="error",
            reason="Fichier candidat absent : impossible d'accepter",
        )
        return get_file_mark(sha256)
    pages = None
    text = mark.get("text_content") or ""
    if text.strip():
        pages = split_pages(text)
    _materialize(sha256, mark, llm, embedding_model, pages=pages)
    return get_file_mark(sha256)


def reject_mark(sha256: str, reason: str = "Refusé manuellement") -> dict | None:
    """Manually reject a mark and delete its temporary file."""
    mark = get_file_mark(sha256)
    if mark is None:
        return None
    _delete_stored(mark)
    update_file_mark(
        sha256,
        verdict="rejected",
        reason=reason,
        stored_path=None,
        text_content=None,
    )
    return get_file_mark(sha256)


def reevaluate_mark(
    sha256: str,
    llm: httpx.Client,
    embedding_model,
) -> dict:
    """Force a new judge pass.

    * pending/rejected with a stored file → re-run the full judge;
    * accepted document → judge its stored text again;
    * rejected without a file → drop the mark so the agent resends it.
    """
    mark = get_file_mark(sha256)
    if mark is None:
        return {"action": "unknown", "sha256": sha256}

    if mark.get("stored_path") and Path(mark["stored_path"]).exists():
        update_file_mark(sha256, verdict="pending", reason="Réévaluation demandée")
        process_candidate(sha256, llm, embedding_model)
        return {"action": "reevaluated", "sha256": sha256}

    if mark.get("doc_id"):
        doc = get_document(mark["doc_id"])
        if doc is not None and llm is not None:
            judge = judge_document(llm, doc.get("text_content") or "", doc.get("filename"))
            reason = str(judge.get("reason") or "")
            # The document is already archived: refresh the explanation but
            # never delete a file that the user may have validated manually.
            update_file_mark(
                sha256,
                verdict="accepted",
                reason=reason or mark.get("reason") or "Document déjà archivé",
                confidence=float(judge.get("confidence") or 0.0),
            )
            return {"action": "reevaluated", "sha256": sha256, "verdict": "accepted"}

    # No file and no document: let the agent resend the file.
    from database import delete_file_mark

    delete_file_mark(sha256)
    return {"action": "resend_required", "sha256": sha256}
