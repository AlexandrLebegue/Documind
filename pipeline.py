"""Document processing pipeline: OCR → segmentation → text-only LLM → embedding."""

from __future__ import annotations

import logging
import time
import traceback
import uuid
from pathlib import Path

import httpx

from config import OCR_BACKEND
from ocr import extract_pages
from llm import extract_metadata, segment_documents
from embeddings import generate_embedding, serialize_embedding
from database import (
    update_document_text,
    update_document_metadata,
    update_document_embedding,
    update_document_status,
    update_document_progress,
    update_document_fields,
    insert_document,
    get_document,
    get_child_documents,
    delete_document as db_delete_document,
)

logger = logging.getLogger(__name__)


def _save_metadata(doc_id: str, metadata: dict) -> None:
    """Persist LLM-extracted metadata (including title) to the database."""
    update_document_metadata(
        doc_id,
        doc_type=metadata.get("type", "autre"),
        emetteur=metadata.get("emetteur", ""),
        doc_date=metadata.get("date", ""),
        montant=metadata.get("montant"),
        reference=metadata.get("reference"),
        destinataire=metadata.get("destinataire"),
        resume=metadata.get("resume", ""),
        tags=metadata.get("tags", []),
        title=metadata.get("titre"),
        date_expiration=metadata.get("date_expiration"),
        date_echeance=metadata.get("date_echeance"),
    )


def _join_pages(pages: list[str], offset: int = 0) -> str:
    """Join page texts with explicit page markers (1-based, *offset* added)."""
    return "\n\n".join(
        f"--- Page {offset + i + 1} ---\n\n{text}"
        for i, text in enumerate(pages)
    )


def _split_page_markers(text: str) -> list[str]:
    """Parse a stored text blob back into page texts."""
    import re

    if not text:
        return []
    parts = re.split(r"--- Page \d+ ---\s*", text)
    pages = [p.strip() for p in parts[1:]] if parts and parts[0].strip() == "" else []
    return pages or [text.strip()]


def _mark_error(doc_id: str, stage: str, exc: BaseException | None = None) -> None:
    """Set a document to error status and keep a short, non-sensitive reason."""
    message = f"{stage} failed"
    if exc is not None:
        message = f"{stage}: {type(exc).__name__}: {str(exc)[:300]}"
    try:
        update_document_status(doc_id, "error")
        update_document_fields(doc_id, error_message=message)
    except Exception:
        logger.debug("Could not persist error state", exc_info=True)


def _segment_filename(original: str, start: int, end: int) -> str:
    path = Path(original)
    suffix = path.suffix or ".pdf"
    return f"{path.stem} (p.{start}-{end}){suffix}"


def _process_segment(
    doc_id: str,
    file_path: str,
    pages: list[str],
    page_start: int,
    llm: httpx.Client,
    embedding_model,
    segment_title: str | None = None,
    ocr_backend: str = OCR_BACKEND,
) -> bool:
    """Run metadata + embedding for one document (or one segment).

    Returns True on success, False if the document was marked as errored.
    """
    started = time.perf_counter()
    text = _join_pages(pages, offset=page_start - 1)
    metadata_started = time.perf_counter()
    try:
        update_document_text(doc_id, text)
        update_document_fields(
            doc_id,
            page_start=page_start,
            page_end=page_start + len(pages) - 1,
            pages_done=len(pages),
            pages_total=len(pages),
            ocr_backend=ocr_backend,
        )
        metadata = extract_metadata(
            llm,
            text,
            filename=Path(file_path).name,
            preferred_title=segment_title,
        )
        _save_metadata(doc_id, metadata)
        update_document_fields(
            doc_id,
            llm_seconds=round(time.perf_counter() - metadata_started, 3),
        )
        logger.info(
            "Metadata ready for %s (type=%s, titre='%s')",
            doc_id[:8],
            metadata.get("type"),
            metadata.get("titre", ""),
        )
    except Exception as exc:
        logger.error(
            "Metadata step failed for doc %s:\n%s", doc_id, traceback.format_exc()
        )
        _mark_error(doc_id, "metadata", exc)
        return False

    try:
        embedding = generate_embedding(embedding_model, text)
        update_document_embedding(doc_id, serialize_embedding(embedding))
    except Exception as exc:
        logger.error(
            "Embedding step failed for doc %s:\n%s", doc_id, traceback.format_exc()
        )
        _mark_error(doc_id, "embedding", exc)
        return False

    update_document_fields(
        doc_id,
        total_seconds=round(time.perf_counter() - started, 3),
        error_message=None,
    )
    update_document_status(doc_id, "ready")
    logger.info("Document %s ready (%d page(s))", doc_id[:8], len(pages))
    return True


def _delete_previous_children(doc_id: str) -> None:
    for child in get_child_documents(doc_id):
        logger.info("Removing previous segment %s", child["id"][:8])
        db_delete_document(child["id"])


def process_document(
    doc_id: str,
    file_path: str,
    llm: httpx.Client,
    embedding_model,
) -> None:
    """Run the full pipeline for a freshly uploaded document.

    OCR page by page (OvisOCR3 / Tesseract), persist progress per page,
    segment multi-document scans, then extract metadata and embeddings for
    each resulting document. Failures set the document status to ``error``.
    """
    logger.info("Starting processing pipeline for document %s (%s)", doc_id, file_path)
    doc = get_document(doc_id)
    if doc is None:
        logger.error("Document %s not found in database", doc_id)
        return
    if llm is None:
        logger.error("No LLM client available — cannot process %s", doc_id)
        _mark_error(doc_id, "llm_client")
        return

    def _progress(done: int, total: int) -> None:
        try:
            update_document_progress(doc_id, done, total, OCR_BACKEND)
        except Exception:
            logger.debug("Could not persist OCR progress", exc_info=True)

    overall_started = time.perf_counter()
    ocr_started = time.perf_counter()
    ocr_info: dict = {}
    try:
        pages = extract_pages(file_path, progress_cb=_progress, info=ocr_info)
    except Exception as exc:
        logger.error(
            "OCR failed for doc %s:\n%s", doc_id, traceback.format_exc()
        )
        _mark_error(doc_id, "ocr", exc)
        return

    ocr_seconds = round(time.perf_counter() - ocr_started, 3)
    if not pages:
        pages = [""]
    total = len(pages)
    ocr_label = "+".join(sorted(ocr_info.get("backends", []))) or OCR_BACKEND
    update_document_progress(doc_id, total, total, ocr_label)
    update_document_fields(doc_id, ocr_seconds=ocr_seconds, ocr_backend=ocr_label)

    try:
        segments = segment_documents(llm, pages)
    except Exception:
        logger.warning("Segmentation failed — keeping a single document", exc_info=True)
        segments = [{"pages": [1, total], "type": None, "titre": None}]

    if len(segments) > 1:
        _delete_previous_children(doc_id)

        # The original row becomes a lightweight source container; the OCR
        # text lives on the child documents to avoid duplicate search hits.
        update_document_fields(
            doc_id,
            title=f"{Path(doc['filename']).stem} (source, {len(segments)} documents)",
            doc_type="autre",
            resume=f"Scan contenant {len(segments)} documents distincts",
            text_content="",
            status="segmented",
            pages_done=total,
            pages_total=total,
            ocr_backend=ocr_label,
        )

        for segment in segments:
            start, end = segment["pages"]
            child_pages = pages[start - 1:end]
            child_id = str(uuid.uuid4())
            child_name = _segment_filename(doc["filename"], start, end)
            insert_document(
                child_id,
                child_name,
                file_path,
                parent_id=doc_id,
                page_start=start,
                page_end=end,
            )
            _process_segment(
                child_id,
                file_path,
                child_pages,
                page_start=start,
                llm=llm,
                embedding_model=embedding_model,
                segment_title=segment.get("titre"),
                ocr_backend=ocr_label,
            )
        children = get_child_documents(doc_id)
        update_document_fields(
            doc_id,
            llm_seconds=round(sum(c.get("llm_seconds") or 0 for c in children), 3),
            total_seconds=round(time.perf_counter() - overall_started, 3),
        )
        logger.info(
            "Segmented document %s into %d document(s)", doc_id[:8], len(segments)
        )
        return

    _process_segment(
        doc_id,
        file_path,
        pages,
        page_start=1,
        llm=llm,
        embedding_model=embedding_model,
        ocr_backend=ocr_label,
    )
    update_document_fields(
        doc_id,
        ocr_seconds=ocr_seconds,
        total_seconds=round(time.perf_counter() - overall_started, 3),
    )


def reprocess_document(
    doc_id: str,
    llm: httpx.Client,
    embedding_model,
) -> None:
    """Re-run the pipeline for an existing document.

    Documents with existing text skip OCR and only refresh metadata +
    embedding. Segment documents reprocess their own page range. A source
    document with children is fully re-segmented (old children are removed).
    """
    logger.info("Reprocessing document %s", doc_id)
    doc = get_document(doc_id)
    if doc is None:
        logger.error("Document %s not found in database — cannot reprocess", doc_id)
        return

    file_path = doc.get("filepath", "")
    text = (doc.get("text_content") or "").strip()

    # Segment child with existing text: metadata + embedding only.
    if doc.get("parent_id") and text:
        start = int(doc.get("page_start") or 1)
        _process_segment(
            doc_id,
            file_path,
            _split_page_markers(text),
            page_start=start,
            llm=llm,
            embedding_model=embedding_model,
            ocr_backend=doc.get("ocr_backend") or OCR_BACKEND,
        )
        return

    # Normal document with existing text: metadata + embedding only.
    if text and doc.get("status") != "segmented":
        _process_segment(
            doc_id,
            file_path,
            _split_page_markers(text),
            page_start=int(doc.get("page_start") or 1),
            llm=llm,
            embedding_model=embedding_model,
        )
        return

    if not file_path or not Path(file_path).exists():
        logger.error(
            "Cannot reprocess doc %s: file not found at '%s'", doc_id, file_path
        )
        _mark_error(doc_id, "file_missing")
        return

    # Re-OCR from the original file (OCR page cache makes this cheap).
    ocr_info: dict = {}
    ocr_label = OCR_BACKEND

    def _progress(done: int, total: int) -> None:
        try:
            update_document_progress(doc_id, done, total, ocr_label)
        except Exception:
            logger.debug("Could not persist OCR progress", exc_info=True)

    try:
        pages = extract_pages(file_path, progress_cb=_progress, info=ocr_info)
        ocr_label = "+".join(sorted(ocr_info.get("backends", []))) or OCR_BACKEND
    except Exception as exc:
        logger.error("Reprocess OCR failed for doc %s:\n%s", doc_id, traceback.format_exc())
        _mark_error(doc_id, "ocr", exc)
        return

    if doc.get("parent_id"):
        start = int(doc.get("page_start") or 1)
        end = int(doc.get("page_end") or len(pages))
        _process_segment(
            doc_id,
            file_path,
            pages[start - 1:end],
            page_start=start,
            llm=llm,
            embedding_model=embedding_model,
            ocr_backend=ocr_label,
        )
        return

    # Source document: rerun the full pipeline (segmentation included).
    process_document(doc_id, file_path, llm, embedding_model)
