"""Document processing pipeline: OCR → image extraction → LLM multimodal metadata → embedding."""

import logging
import traceback
from pathlib import Path

import httpx
from sentence_transformers import SentenceTransformer

from ocr import extract_text, extract_images_as_base64
from llm import extract_metadata
from embeddings import generate_embedding, serialize_embedding
from database import (
    update_document_text,
    update_document_metadata,
    update_document_embedding,
    update_document_status,
    get_document,
)

logger = logging.getLogger(__name__)


def _save_metadata(doc_id: str, metadata: dict) -> None:
    """Persist LLM-extracted metadata (including title) to the database.

    Args:
        doc_id: UUID of the document record.
        metadata: Dict returned by :func:`llm.extract_metadata`.
    """
    update_document_metadata(
        doc_id,
        doc_type=metadata["type"],
        emetteur=metadata["emetteur"],
        doc_date=metadata["date"],
        montant=metadata.get("montant"),
        reference=metadata.get("reference"),
        destinataire=metadata.get("destinataire"),
        resume=metadata["resume"],
        tags=metadata.get("tags", []),
        title=metadata.get("titre"),
        date_expiration=metadata.get("date_expiration"),
        date_echeance=metadata.get("date_echeance"),
    )


def process_document(
    doc_id: str,
    file_path: str,
    llm: httpx.Client,
    embedding_model: SentenceTransformer,
) -> None:
    """Run the full document processing pipeline.

    Orchestrates four sequential stages — OCR text extraction, image
    extraction for vision, LLM-based multimodal metadata extraction,
    and embedding generation — persisting results to the database after
    each stage.  On any failure the document status is set to ``"error"``
    and the exception is logged (never re-raised, as this runs as a
    background task).

    Args:
        doc_id: UUID of the document record in the database.
        file_path: Path to the original document file on disk.
        llm: Pre-configured :class:`httpx.Client` for OpenRouter API calls.
        embedding_model: Loaded :class:`SentenceTransformer` instance.
    """
    logger.info("Starting processing pipeline for document %s (%s)", doc_id, file_path)

    text: str = ""
    images: list[str] = []

    # ── Step 1 — OCR / text extraction ──────────────────────────────────
    try:
        text = extract_text(file_path)
        update_document_text(doc_id, text)
        logger.info(
            "Step 1 complete: text extracted (%d chars) for doc %s",
            len(text), doc_id,
        )
        if len(text) < 10:
            logger.warning(
                "Extracted text is very short (%d chars) for doc %s — "
                "vision analysis will help compensate",
                len(text), doc_id,
            )
    except Exception:
        logger.error(
            "Step 1 failed (OCR) for doc %s:\n%s",
            doc_id, traceback.format_exc(),
        )
        update_document_status(doc_id, "error")
        return

    # ── Step 1b — Extract page images for vision analysis ───────────────
    try:
        images = extract_images_as_base64(file_path, max_pages=3)
        logger.info(
            "Step 1b complete: %d image(s) extracted for vision for doc %s",
            len(images), doc_id,
        )
    except Exception:
        logger.warning(
            "Step 1b failed (image extraction) for doc %s — "
            "continuing with text-only analysis:\n%s",
            doc_id, traceback.format_exc(),
        )
        images = []

    # ── Step 2 — LLM multimodal metadata extraction ─────────────────────
    try:
        metadata = extract_metadata(llm, text, images=images)
        _save_metadata(doc_id, metadata)
        logger.info(
            "Step 2 complete: metadata extracted (type=%s, title='%s') for doc %s",
            metadata["type"], metadata.get("titre", ""), doc_id,
        )
    except Exception:
        logger.error(
            "Step 2 failed (LLM metadata) for doc %s:\n%s",
            doc_id, traceback.format_exc(),
        )
        update_document_status(doc_id, "error")
        return

    # ── Step 3 — Embedding generation ───────────────────────────────────
    try:
        embedding = generate_embedding(embedding_model, text)
        update_document_embedding(doc_id, serialize_embedding(embedding))
        logger.info(
            "Step 3 complete: embedding generated (dim=%d) for doc %s",
            embedding.shape[0], doc_id,
        )
    except Exception:
        logger.error(
            "Step 3 failed (embedding) for doc %s:\n%s",
            doc_id, traceback.format_exc(),
        )
        update_document_status(doc_id, "error")
        return

    # ── Step 4 — Finalise ───────────────────────────────────────────────
    update_document_status(doc_id, "ready")
    logger.info("Document processing complete for doc %s — status set to 'ready'", doc_id)


def reprocess_document(
    doc_id: str,
    llm: httpx.Client,
    embedding_model: SentenceTransformer,
) -> None:
    """Re-run the processing pipeline for an existing document.

    If the document already has ``text_content``, the OCR step is skipped
    and only metadata extraction and embedding generation are performed.
    Image extraction is always performed from the original file to provide
    vision context to the LLM.

    Args:
        doc_id: UUID of the document record in the database.
        llm: Pre-configured :class:`httpx.Client` for OpenRouter API calls.
        embedding_model: Loaded :class:`SentenceTransformer` instance.
    """
    logger.info("Reprocessing document %s", doc_id)

    doc = get_document(doc_id)
    if doc is None:
        logger.error("Document %s not found in database — cannot reprocess", doc_id)
        return

    text: str = doc.get("text_content") or ""
    file_path: str = doc.get("filepath", "")
    images: list[str] = []

    # If no existing text, re-run OCR from the original file
    if len(text.strip()) == 0:
        if not file_path or not Path(file_path).exists():
            logger.error(
                "Cannot reprocess doc %s: no text_content and file not found at '%s'",
                doc_id, file_path,
            )
            update_document_status(doc_id, "error")
            return

        try:
            text = extract_text(file_path)
            update_document_text(doc_id, text)
            logger.info(
                "Reprocess OCR complete: extracted %d chars for doc %s",
                len(text), doc_id,
            )
        except Exception:
            logger.error(
                "Reprocess OCR failed for doc %s:\n%s",
                doc_id, traceback.format_exc(),
            )
            update_document_status(doc_id, "error")
            return
    else:
        logger.info(
            "Skipping OCR for doc %s — existing text_content (%d chars)",
            doc_id, len(text),
        )

    # ── Extract page images for vision analysis (always) ────────────────
    if file_path and Path(file_path).exists():
        try:
            images = extract_images_as_base64(file_path, max_pages=3)
            logger.info(
                "Reprocess image extraction: %d image(s) for doc %s",
                len(images), doc_id,
            )
        except Exception:
            logger.warning(
                "Reprocess image extraction failed for doc %s — "
                "continuing with text-only:\n%s",
                doc_id, traceback.format_exc(),
            )
            images = []
    else:
        logger.warning(
            "Original file not found at '%s' for doc %s — "
            "skipping vision analysis",
            file_path, doc_id,
        )

    # ── LLM multimodal metadata extraction ──────────────────────────────
    try:
        metadata = extract_metadata(llm, text, images=images)
        _save_metadata(doc_id, metadata)
        logger.info(
            "Reprocess metadata complete (type=%s, title='%s') for doc %s",
            metadata["type"], metadata.get("titre", ""), doc_id,
        )
    except Exception:
        logger.error(
            "Reprocess metadata failed for doc %s:\n%s",
            doc_id, traceback.format_exc(),
        )
        update_document_status(doc_id, "error")
        return

    # ── Embedding generation ────────────────────────────────────────────
    try:
        embedding = generate_embedding(embedding_model, text)
        update_document_embedding(doc_id, serialize_embedding(embedding))
        logger.info(
            "Reprocess embedding complete (dim=%d) for doc %s",
            embedding.shape[0], doc_id,
        )
    except Exception:
        logger.error(
            "Reprocess embedding failed for doc %s:\n%s",
            doc_id, traceback.format_exc(),
        )
        update_document_status(doc_id, "error")
        return

    # ── Finalise ────────────────────────────────────────────────────────
    update_document_status(doc_id, "ready")
    logger.info("Document reprocessing complete for doc %s — status set to 'ready'", doc_id)
