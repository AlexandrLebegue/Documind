"""DocuMind — FastAPI application entry point."""

import mimetypes
import uuid
import json
import logging
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, UploadFile, File, HTTPException, Query
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware

import config as _config_module
from config import (
    ORIGINALS_DIR, MAX_UPLOAD_SIZE_MB,
    SUPPORTED_EXTENSIONS, HOST, PORT, RAG_TOP_K_DOCS,
    load_settings, save_settings, DATA_DIR,
)
from database import (
    init_db, insert_document, get_document, list_documents, count_documents,
    update_document_fields, delete_document, insert_chat_message,
    get_chat_history, get_stats,
    create_chat_session, get_chat_session, list_chat_sessions,
    count_chat_sessions, update_chat_session_title,
    update_chat_session_timestamp, delete_chat_session,
    get_session_messages_for_llm,
    insert_procedure, get_procedure, list_procedures, count_procedures,
    delete_procedure as db_delete_procedure,
    update_procedure as db_update_procedure,
    insert_procedure_execution, get_procedure_execution,
    search_documents_by_type_and_name,
    get_expiring_documents, get_upcoming_echeances,
    get_documents_for_gap_detection,
    dismiss_alert as db_dismiss_alert, undismiss_alert as db_undismiss_alert,
    get_dismissed_alert_keys,
)
from models import (
    DocumentResponse, DocumentListResponse, DocumentUpdateRequest,
    SearchRequest, SearchResponse, SearchResultItem,
    ChatRequest, ChatResponse, ChatHistoryResponse,
    ChatSessionResponse, ChatSessionListResponse,
    ChatSessionCreateRequest, ChatSessionUpdateRequest,
    StatsResponse, UploadResponse, HealthResponse,
    ProcedureCreateRequest, ProcedureUpdateRequest, ProcedureResponse, ProcedureListResponse,
    ProcedureRequiredDocument, ProcedureExecuteRequest,
    ProcedureExecutionResponse, MatchedDocument,
    SettingsResponse, SettingsUpdateRequest,
    AlertItem, AlertsResponse,
    RenewalSuggestion, RenewalSuggestionsResponse,
    GapAlert, GapAlertsResponse,
    AgentChatRequest, AgentChatResponse, ToolCallLog,
    QueueStatusResponse,
)
from processing_queue import get_queue
from pipeline import process_document, reprocess_document
from search import hybrid_search, load_embeddings_cache, refresh_embeddings_cache
from llm import init_llm_client, chat_with_context, chat_with_context_multiturn, analyze_procedure, match_document_for_procedure
from embeddings import load_embedding_model
from agent import run_agent
from update import check_for_update, apply_update, install_dependencies, restart_server

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------

def _app_version() -> str:
    """Return the current app version: git SHA in Docker, git describe locally."""
    sha_file = Path(__file__).parent / ".git_sha"
    if sha_file.exists():
        return sha_file.read_text().strip()[:8]
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, cwd=Path(__file__).parent,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return "unknown"


_VERSION = _app_version()


# ---------------------------------------------------------------------------
# In-memory log buffer (captured from root logger)
# ---------------------------------------------------------------------------

import collections
import threading

_LOG_BUFFER: collections.deque[str] = collections.deque(maxlen=2000)
_LOG_LOCK = threading.Lock()


class _BufferHandler(logging.Handler):
    def emit(self, record: logging.LogRecord) -> None:
        line = self.format(record)
        with _LOG_LOCK:
            _LOG_BUFFER.append(line)

# ---------------------------------------------------------------------------
# Frontend build helper
# ---------------------------------------------------------------------------

FRONTEND_DIR = Path(__file__).parent / "frontend"
STATIC_DIR = Path(__file__).parent / "static"


def build_frontend() -> None:
    """Build the Next.js frontend and copy the output to ``static/``.

    This runs ``npm install`` (if *node_modules* is absent) followed by
    ``npm run build`` inside the ``frontend/`` directory, then copies the
    generated ``frontend/out/`` tree into ``static/`` so FastAPI can serve it.

    The function is designed for **local development** so that a single
    ``python main.py`` command is all that is needed.  In Docker the
    ``--skip-build`` flag should be used because the frontend is
    pre-built during the image build stage.
    """
    if not FRONTEND_DIR.exists():
        logger.warning(
            "frontend/ directory not found at %s — skipping frontend build",
            FRONTEND_DIR,
        )
        return

    # Resolve npm executable (npm.cmd on Windows, npm elsewhere)
    npm = "npm.cmd" if sys.platform == "win32" else "npm"

    # 1. npm install (always run to ensure deps are up-to-date)
    logger.info("Installing frontend dependencies (npm install)…")
    result = subprocess.run(
        [npm, "install"],
        cwd=str(FRONTEND_DIR),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.error("npm install failed:\n%s", result.stderr)
        raise RuntimeError("npm install failed — see logs above")
    logger.info("Frontend dependencies installed")

    # 2. npm run build
    logger.info("Building frontend (npm run build)…")
    result = subprocess.run(
        [npm, "run", "build"],
        cwd=str(FRONTEND_DIR),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.error("npm run build failed:\n%s", result.stderr)
        raise RuntimeError("npm run build failed — see logs above")
    logger.info("Frontend built successfully")

    # 3. Copy frontend/out → static/
    out_dir = FRONTEND_DIR / "out"
    if not out_dir.exists():
        raise RuntimeError(
            f"Expected build output at {out_dir} but directory does not exist. "
            "Check that next.config.mjs has output: 'export'."
        )

    if STATIC_DIR.exists():
        shutil.rmtree(STATIC_DIR)
    shutil.copytree(str(out_dir), str(STATIC_DIR))
    logger.info("Frontend assets copied to %s", STATIC_DIR)


# ---------------------------------------------------------------------------
# Helper — parse a raw DB dict into a DocumentResponse
# ---------------------------------------------------------------------------

def _parse_document(doc_dict: dict) -> DocumentResponse:
    """Convert a raw database dict into a :class:`DocumentResponse`.

    Handles three concerns that differ between storage and API:

    1. ``tags`` may be a JSON string — it is parsed to ``list[str]``.
    2. The ``embedding`` column (raw binary blob) is stripped.
    3. All remaining fields are forwarded to the Pydantic model.

    Args:
        doc_dict: Row dict as returned by ``database.get_document()`` or
            similar functions.

    Returns:
        A validated :class:`DocumentResponse` instance.
    """
    data = dict(doc_dict)

    # Parse tags from JSON string if necessary
    tags = data.get("tags")
    if isinstance(tags, str):
        try:
            data["tags"] = json.loads(tags)
        except (json.JSONDecodeError, TypeError):
            data["tags"] = []

    # Remove binary embedding — not for the HTTP layer
    data.pop("embedding", None)

    return DocumentResponse(**data)


# ---------------------------------------------------------------------------
# Background task helpers
# ---------------------------------------------------------------------------

async def _enqueue_process(doc_id: str, file_path: str, filename: str, app: FastAPI) -> None:
    """Enqueue a document processing job in the FIFO queue."""
    import asyncio

    async def _job():
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: process_document(doc_id, file_path, app.state.llm, app.state.embedding_model),
        )
        app.state.embeddings_cache = refresh_embeddings_cache(app.state.embeddings_cache)

    await get_queue().enqueue(label=filename, fn=_job)


async def _enqueue_reprocess(doc_id: str, filename: str, app: FastAPI) -> None:
    """Enqueue a document reprocessing job in the FIFO queue."""
    import asyncio

    async def _job():
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: reprocess_document(doc_id, app.state.llm, app.state.embedding_model),
        )
        app.state.embeddings_cache = refresh_embeddings_cache(app.state.embeddings_cache)

    await get_queue().enqueue(label=f"Retraitement — {filename}", fn=_job)


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application startup and shutdown.

    Startup sequence:
        1. Initialize the SQLite database (schema + triggers).
        2. Create the OpenRouter LLM client.
        3. Load the sentence-transformer embedding model.
        4. Populate the in-memory embeddings cache.
    """
    # Startup
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )
    # Attach in-memory log buffer (feeds /api/logs SSE)
    _buf_handler = _BufferHandler()
    _buf_handler.setFormatter(logging.Formatter("%(asctime)s [%(name)s] %(levelname)s: %(message)s"))
    logging.getLogger().addHandler(_buf_handler)
    logger.info("DocuMind starting up...")

    # 1. Initialize database
    init_db()
    logger.info("Database initialized")

    # 2. Create OpenRouter LLM client
    try:
        app.state.llm = init_llm_client()
        logger.info("OpenRouter LLM client ready")
    except ValueError as exc:
        app.state.llm = None
        logger.warning("LLM client not available: %s", exc)

    # 3. Load embedding model
    try:
        app.state.embedding_model = load_embedding_model()
        logger.info("Embedding model loaded")
    except Exception as exc:
        app.state.embedding_model = None
        logger.warning("Embedding model failed to load: %s", exc)

    # 4. Load embeddings cache
    app.state.embeddings_cache = load_embeddings_cache()
    logger.info("Embeddings cache loaded: %d documents", len(app.state.embeddings_cache))

    # 5. Sync crontab with saved NAS settings (idempotent, no-op on Windows)
    try:
        from nas_sync import apply_cron_schedule
        cron_result = apply_cron_schedule()
        logger.info("Cron schedule on startup: %s", cron_result)
    except Exception as exc:
        logger.warning("Could not apply cron schedule on startup: %s", exc)

    # 6. Start the single-worker processing queue
    pq = get_queue()
    pq.start()
    logger.info("Processing queue started")

    yield

    # Shutdown: stop the queue worker

    # Shutdown
    get_queue().stop()
    if app.state.llm is not None:
        app.state.llm.close()
        logger.info("OpenRouter LLM client closed")
    logger.info("DocuMind shutting down...")


# ---------------------------------------------------------------------------
# App initialization
# ---------------------------------------------------------------------------

app = FastAPI(
    title="DocuMind",
    description="Document management with OCR + AI (OpenRouter LLM)",
    version="0.2.0",
    lifespan=lifespan,
)

# CORS for development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# API Endpoints
# ---------------------------------------------------------------------------


@app.get(
    "/api/health",
    response_model=HealthResponse,
    summary="Health check",
    description="Returns the service health status including whether the LLM "
    "and embedding model are loaded and the total document count.",
)
async def health_check() -> HealthResponse:
    """Return current health / readiness status."""
    stats = get_stats()
    return HealthResponse(
        status="ok",
        llm_loaded=app.state.llm is not None,
        embedding_model_loaded=app.state.embedding_model is not None,
        total_documents=stats["total_documents"],
        version=_VERSION,
    )


# ── Upload ─────────────────────────────────────────────────────────────────


@app.post(
    "/api/documents/upload",
    response_model=UploadResponse,
    status_code=201,
    summary="Upload a document",
    description="Upload a PDF or image file. The document is saved to disk, "
    "a database record is created, and an asynchronous pipeline "
    "(OCR → LLM metadata → embedding) is started in the background.",
)
async def upload_document(
    file: UploadFile = File(...),
) -> UploadResponse:
    """Accept a file upload and start background processing."""
    # Validate extension
    ext = Path(file.filename or "").suffix.lower()
    if ext not in SUPPORTED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{ext}'. Supported: {', '.join(sorted(SUPPORTED_EXTENSIONS))}",
        )

    # Read content and validate size
    content = await file.read()
    max_bytes = MAX_UPLOAD_SIZE_MB * 1024 * 1024
    if len(content) > max_bytes:
        raise HTTPException(
            status_code=400,
            detail=f"File size ({len(content) / (1024 * 1024):.1f} MB) exceeds "
            f"maximum allowed size ({MAX_UPLOAD_SIZE_MB} MB).",
        )

    # Generate document ID and save file
    doc_id = str(uuid.uuid4())
    safe_filename = file.filename or "document"
    file_path = os.path.join(ORIGINALS_DIR, f"{doc_id}_{safe_filename}")

    with open(file_path, "wb") as f:
        f.write(content)

    logger.info("File saved: %s (%d bytes)", file_path, len(content))

    # Insert database record
    insert_document(doc_id, safe_filename, file_path)

    # Verify LLM and embedding model availability
    if app.state.llm is None or app.state.embedding_model is None:
        raise HTTPException(
            status_code=503,
            detail="LLM or embedding model not loaded. Cannot process documents.",
        )

    # Enqueue processing (single-worker FIFO — prevents OOM on bulk uploads)
    await _enqueue_process(doc_id, file_path, safe_filename, app)
    pos = get_queue().snapshot()["total_pending"] + get_queue().snapshot()["total_active"]
    logger.info("Document %s enqueued (queue size ~%d)", doc_id, pos)

    return UploadResponse(
        id=doc_id,
        filename=safe_filename,
        status="queued",
        message="Document ajouté à la file de traitement",
    )


# ── Document CRUD ──────────────────────────────────────────────────────────


@app.get(
    "/api/documents",
    response_model=DocumentListResponse,
    summary="List documents",
    description="Return a filtered, paginated list of documents. Supports "
    "filtering by type, issuer, date range, and full-text query.",
)
async def list_docs(
    doc_type: Optional[str] = Query(None, description="Filter by document type"),
    emetteur: Optional[str] = Query(None, description="Filter by issuer/sender"),
    date_from: Optional[str] = Query(None, description="Filter doc_date >= this value"),
    date_to: Optional[str] = Query(None, description="Filter doc_date <= this value"),
    q: Optional[str] = Query(None, description="Full-text search query"),
    limit: int = Query(50, ge=1, le=200, description="Max results"),
    offset: int = Query(0, ge=0, description="Pagination offset"),
) -> DocumentListResponse:
    """Retrieve a paginated, optionally filtered list of documents."""
    rows = list_documents(
        doc_type=doc_type,
        emetteur=emetteur,
        date_from=date_from,
        date_to=date_to,
        q=q,
        limit=limit,
        offset=offset,
    )
    total = count_documents(
        doc_type=doc_type,
        emetteur=emetteur,
        date_from=date_from,
        date_to=date_to,
        q=q,
    )
    documents = [_parse_document(row) for row in rows]
    return DocumentListResponse(
        documents=documents,
        total=total,
        limit=limit,
        offset=offset,
    )


@app.get(
    "/api/documents/{doc_id}",
    response_model=DocumentResponse,
    summary="Get a document",
    description="Retrieve a single document by its UUID, including all "
    "metadata fields extracted by the processing pipeline.",
)
async def get_doc(doc_id: str) -> DocumentResponse:
    """Fetch a single document by ID."""
    doc = get_document(doc_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{doc_id}' not found")
    return _parse_document(doc)


@app.put(
    "/api/documents/{doc_id}",
    response_model=DocumentResponse,
    summary="Update a document",
    description="Partially update a document's metadata. Only non-null "
    "fields in the request body are applied.",
)
async def update_doc(doc_id: str, body: DocumentUpdateRequest) -> DocumentResponse:
    """Apply a partial metadata update to a document."""
    doc = get_document(doc_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{doc_id}' not found")

    update_dict = body.model_dump(exclude_none=True)
    if not update_dict:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    # Serialize tags to JSON string for storage
    if "tags" in update_dict and isinstance(update_dict["tags"], list):
        update_dict["tags"] = json.dumps(update_dict["tags"], ensure_ascii=False)

    update_document_fields(doc_id, **update_dict)
    logger.info("Document %s updated: %s", doc_id, list(update_dict.keys()))

    updated = get_document(doc_id)
    return _parse_document(updated)


@app.delete(
    "/api/documents/{doc_id}",
    summary="Delete a document",
    description="Permanently delete a document record and its file from disk. "
    "The embeddings cache is refreshed afterwards.",
)
async def delete_doc(doc_id: str) -> JSONResponse:
    """Delete a document and refresh the embeddings cache."""
    doc = get_document(doc_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{doc_id}' not found")

    delete_document(doc_id)
    app.state.embeddings_cache = refresh_embeddings_cache(app.state.embeddings_cache)
    logger.info("Document %s deleted", doc_id)

    return JSONResponse(content={"message": "Document deleted successfully"})


@app.post(
    "/api/documents/{doc_id}/reprocess",
    summary="Reprocess a document",
    description="Re-run the processing pipeline (OCR → LLM → embedding) for "
    "an existing document in the background.",
)
async def reprocess_doc(
    doc_id: str,
) -> JSONResponse:
    """Trigger reprocessing of an existing document."""
    doc = get_document(doc_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{doc_id}' not found")

    if app.state.llm is None or app.state.embedding_model is None:
        raise HTTPException(
            status_code=503,
            detail="LLM or embedding model not loaded. Cannot reprocess.",
        )

    await _enqueue_reprocess(doc_id, doc["filename"], app)
    logger.info("Reprocessing queued for document %s", doc_id)

    return JSONResponse(content={"message": "Reprocessing queued", "id": doc_id})


# ── File serving ───────────────────────────────────────────────────────────


@app.get(
    "/api/documents/{doc_id}/file",
    summary="Serve original document file",
    description="Return the original uploaded file (PDF, image) for preview "
    "or download. The correct MIME type is inferred from the filename.",
)
async def get_document_file(doc_id: str):
    """Serve the original file from disk."""
    doc = get_document(doc_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{doc_id}' not found")

    filepath = doc["filepath"]
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="File not found on disk")

    # Determine MIME type from the original filename
    media_type, _ = mimetypes.guess_type(doc["filename"])
    if media_type is None:
        media_type = "application/octet-stream"

    return FileResponse(
        path=filepath,
        filename=doc["filename"],
        media_type=media_type,
        content_disposition_type="inline",
    )


# ── Search ─────────────────────────────────────────────────────────────────


@app.post(
    "/api/search",
    response_model=SearchResponse,
    summary="Hybrid search",
    description="Search documents using a hybrid strategy that combines "
    "FTS5 full-text matching and semantic similarity, with "
    "weighted score fusion.",
)
async def search_documents(body: SearchRequest) -> SearchResponse:
    """Run hybrid search across all documents."""
    if app.state.embedding_model is None:
        raise HTTPException(
            status_code=503,
            detail="Embedding model not loaded. Search unavailable.",
        )

    results = hybrid_search(
        query=body.query,
        embedding_model=app.state.embedding_model,
        embeddings_cache=app.state.embeddings_cache,
    )

    items: list[SearchResultItem] = []
    for r in results:
        doc_response = _parse_document(r["document"])
        items.append(
            SearchResultItem(
                document=doc_response,
                score=r["score"],
                match_type=r["match_type"],
            )
        )

    logger.info("Search for '%s' returned %d results", body.query, len(items))
    return SearchResponse(results=items, query=body.query)


# ── Chat sessions ──────────────────────────────────────────────────────────


@app.get(
    "/api/chat/sessions",
    response_model=ChatSessionListResponse,
    summary="List chat sessions",
    description="Return a paginated list of chat sessions ordered by most "
    "recently active first.",
)
async def list_sessions(
    limit: int = Query(50, ge=1, le=200, description="Max sessions"),
    offset: int = Query(0, ge=0, description="Pagination offset"),
) -> ChatSessionListResponse:
    """Retrieve a paginated list of chat sessions."""
    sessions = list_chat_sessions(limit=limit, offset=offset)
    total = count_chat_sessions()
    return ChatSessionListResponse(sessions=sessions, total=total)


@app.post(
    "/api/chat/sessions",
    response_model=ChatSessionResponse,
    status_code=201,
    summary="Create a chat session",
    description="Create a new empty chat session.",
)
async def create_session(body: ChatSessionCreateRequest) -> ChatSessionResponse:
    """Create an empty chat session."""
    session_id = str(uuid.uuid4())
    title = body.title or "Nouvelle conversation"
    create_chat_session(session_id, title)
    session = get_chat_session(session_id)
    return ChatSessionResponse(**session)


@app.get(
    "/api/chat/sessions/{session_id}",
    response_model=ChatSessionResponse,
    summary="Get a chat session",
    description="Retrieve a single chat session by its UUID.",
)
async def get_session(session_id: str) -> ChatSessionResponse:
    """Fetch a single chat session."""
    session = get_chat_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found")
    return ChatSessionResponse(**session)


@app.put(
    "/api/chat/sessions/{session_id}",
    response_model=ChatSessionResponse,
    summary="Rename a chat session",
    description="Update the title of an existing chat session.",
)
async def rename_session(
    session_id: str,
    body: ChatSessionUpdateRequest,
) -> ChatSessionResponse:
    """Rename a chat session."""
    session = get_chat_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found")
    update_chat_session_title(session_id, body.title)
    updated = get_chat_session(session_id)
    return ChatSessionResponse(**updated)


@app.delete(
    "/api/chat/sessions/{session_id}",
    summary="Delete a chat session",
    description="Permanently delete a chat session and all its messages.",
)
async def delete_session(session_id: str) -> JSONResponse:
    """Delete a chat session and all messages (cascade)."""
    session = get_chat_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found")
    delete_chat_session(session_id)
    logger.info("Chat session %s deleted", session_id)
    return JSONResponse(content={"message": "Session deleted successfully"})


# ── Chat ───────────────────────────────────────────────────────────────────


@app.post(
    "/api/chat",
    response_model=ChatResponse,
    summary="Chat with documents (RAG)",
    description="Ask a question about your documents. The system retrieves "
    "relevant documents via hybrid search and generates an answer "
    "using the LLM via OpenRouter with RAG context. Supports "
    "multi-turn conversations via session_id.",
)
async def chat(body: ChatRequest) -> ChatResponse:
    """Answer a user question using RAG over the document collection."""
    if app.state.llm is None:
        raise HTTPException(
            status_code=503,
            detail="LLM not loaded. Chat unavailable.",
        )

    # Resolve or create session
    session_id = body.session_id
    if session_id:
        # Verify session exists
        session = get_chat_session(session_id)
        if session is None:
            raise HTTPException(
                status_code=404,
                detail=f"Chat session '{session_id}' not found",
            )
    else:
        # Auto-create a new session with title from the first message
        session_id = str(uuid.uuid4())
        title = body.message[:50].strip()
        if len(body.message) > 50:
            title += "…"
        create_chat_session(session_id, title)
        logger.info("Auto-created chat session %s: '%s'", session_id, title)

    # Store user message
    insert_chat_message(str(uuid.uuid4()), body.message, "user", session_id)

    # Retrieve relevant documents via hybrid search
    context_results: list[dict] = []
    if app.state.embedding_model is not None and app.state.embeddings_cache:
        context_results = hybrid_search(
            query=body.message,
            embedding_model=app.state.embedding_model,
            embeddings_cache=app.state.embeddings_cache,
            top_k=RAG_TOP_K_DOCS,
        )

    # Build context document list for the LLM
    context_docs: list[dict] = [r["document"] for r in context_results]

    # Retrieve conversation history for multi-turn
    conversation_history = get_session_messages_for_llm(session_id, limit=20)

    # Generate response using multi-turn if we have history, else single-turn
    if len(conversation_history) > 1:
        reply = chat_with_context_multiturn(
            app.state.llm, body.message, context_docs, conversation_history,
        )
    else:
        reply = chat_with_context(app.state.llm, body.message, context_docs)

    # Collect source document IDs
    source_doc_ids: list[str] = [doc["id"] for doc in context_docs]

    # Store assistant reply
    insert_chat_message(str(uuid.uuid4()), reply, "assistant", session_id, source_doc_ids)

    # Touch session timestamp
    update_chat_session_timestamp(session_id)

    logger.info(
        "Chat reply generated (%d chars) with %d source documents in session %s",
        len(reply), len(source_doc_ids), session_id,
    )
    return ChatResponse(
        reply=reply,
        source_document_ids=source_doc_ids,
        session_id=session_id,
    )


@app.post(
    "/api/agent/chat",
    response_model=AgentChatResponse,
    summary="Agentic chat with web access",
    description="Ask the agent a question. The agent can search the web, scrape pages, "
    "verify links, and crawl sites to answer — in addition to the local document base. "
    "Supports multi-turn conversations via session_id.",
)
async def agent_chat(body: AgentChatRequest) -> AgentChatResponse:
    """Agentic chat endpoint with web tools and multi-turn support."""
    if app.state.llm is None:
        raise HTTPException(
            status_code=503,
            detail="LLM not loaded. Agent chat unavailable.",
        )

    # Resolve or create session
    session_id = body.session_id
    if session_id:
        session = get_chat_session(session_id)
        if session is None:
            raise HTTPException(
                status_code=404,
                detail=f"Chat session '{session_id}' not found",
            )
    else:
        session_id = str(uuid.uuid4())
        title = body.message[:50].strip()
        if len(body.message) > 50:
            title += "…"
        create_chat_session(session_id, title)
        logger.info("Agent: auto-created session %s: '%s'", session_id, title)

    # Store user message
    insert_chat_message(str(uuid.uuid4()), body.message, "user", session_id)

    # Retrieve conversation history for multi-turn
    conversation_history = get_session_messages_for_llm(session_id, limit=20)

    # Run the agentic loop
    try:
        reply, tool_calls_log = await run_agent(
            llm_client=app.state.llm,
            user_message=body.message,
            context_procedure=body.context_procedure,
            conversation_history=conversation_history,
        )
    except Exception as exc:
        logger.error("Agent run failed: %s", exc)
        raise HTTPException(status_code=500, detail=f"Agent error: {exc}") from exc

    # Store assistant reply with tool calls
    tool_calls_dicts = [tc for tc in tool_calls_log]
    insert_chat_message(
        str(uuid.uuid4()), reply, "assistant", session_id,
        tool_calls=tool_calls_dicts if tool_calls_dicts else None,
    )
    update_chat_session_timestamp(session_id)

    logger.info(
        "Agent reply (%d chars, %d tool calls) in session %s",
        len(reply), len(tool_calls_log), session_id,
    )
    return AgentChatResponse(
        reply=reply,
        session_id=session_id,
        tool_calls_log=[ToolCallLog(**tc) for tc in tool_calls_log],
    )


@app.post("/api/agent/chat/stream")
async def agent_chat_stream(body: AgentChatRequest) -> StreamingResponse:
    """Streaming SSE version of agent chat — emits tool_start, tool_done, and done events."""
    if app.state.llm is None:
        raise HTTPException(status_code=503, detail="LLM not loaded.")

    # Resolve or create session
    session_id = body.session_id
    if session_id:
        session = get_chat_session(session_id)
        if session is None:
            raise HTTPException(status_code=404, detail=f"Chat session '{session_id}' not found")
    else:
        session_id = str(uuid.uuid4())
        title = body.message[:50].strip() + ("…" if len(body.message) > 50 else "")
        create_chat_session(session_id, title)
        logger.info("Agent stream: auto-created session %s: '%s'", session_id, title)

    insert_chat_message(str(uuid.uuid4()), body.message, "user", session_id)
    conversation_history = get_session_messages_for_llm(session_id, limit=20)

    async def event_stream():
        # Send session_id first so the frontend can track it immediately
        yield f"data: {json.dumps({'type': 'session', 'session_id': session_id})}\n\n"

        tool_calls_log: list[dict] = []

        async def on_tool_start(name: str, args: dict) -> None:
            event = json.dumps({"type": "tool_start", "tool": name, "args": args})
            yield_queue.append(f"data: {event}\n\n")

        async def on_tool_done(name: str, args: dict, result: str) -> None:
            event = json.dumps({
                "type": "tool_done",
                "tool": name,
                "args": args,
                "result_preview": result[:300],
            })
            yield_queue.append(f"data: {event}\n\n")

        # Use a queue to bridge callbacks → async generator
        yield_queue: list[str] = []

        import asyncio

        async def run():
            return await run_agent(
                llm_client=app.state.llm,
                user_message=body.message,
                context_procedure=body.context_procedure,
                conversation_history=conversation_history,
                on_tool_start=on_tool_start,
                on_tool_done=on_tool_done,
            )

        task = asyncio.create_task(run())

        while not task.done():
            await asyncio.sleep(0.05)
            while yield_queue:
                yield yield_queue.pop(0)

        # Drain any remaining events
        while yield_queue:
            yield yield_queue.pop(0)

        try:
            reply, tool_calls_log = task.result()
        except Exception as exc:
            logger.error("Agent stream failed: %s", exc)
            yield f"data: {json.dumps({'type': 'error', 'message': str(exc)})}\n\n"
            return

        insert_chat_message(
            str(uuid.uuid4()), reply, "assistant", session_id,
            tool_calls=tool_calls_log if tool_calls_log else None,
        )
        update_chat_session_timestamp(session_id)

        yield f"data: {json.dumps({'type': 'done', 'reply': reply, 'session_id': session_id, 'tool_calls_log': tool_calls_log})}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream", headers={
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
    })


@app.get(
    "/api/chat/history",
    response_model=ChatHistoryResponse,
    summary="Chat history",
    description="Retrieve past chat messages for a specific session, "
    "ordered by most recent first.",
)
async def chat_history(
    session_id: str = Query(..., description="Chat session UUID"),
    limit: int = Query(50, ge=1, le=200, description="Max messages"),
    offset: int = Query(0, ge=0, description="Pagination offset"),
) -> ChatHistoryResponse:
    """Return paginated chat history for a session."""
    session = get_chat_session(session_id)
    if session is None:
        raise HTTPException(
            status_code=404,
            detail=f"Chat session '{session_id}' not found",
        )
    messages = get_chat_history(session_id=session_id, limit=limit, offset=offset)
    return ChatHistoryResponse(messages=messages)


# ── Stats ──────────────────────────────────────────────────────────────────


@app.get(
    "/api/stats",
    response_model=StatsResponse,
    summary="Collection statistics",
    description="Return aggregate statistics about the document collection "
    "including counts by type and month, and the most recent documents.",
)
async def stats() -> StatsResponse:
    """Return aggregate statistics about the document collection."""
    data = get_stats()

    # Parse recent documents through the helper
    recent = [_parse_document(doc) for doc in data.get("recent_documents", [])]

    return StatsResponse(
        total_documents=data["total_documents"],
        count_by_type=data.get("count_by_type", {}),
        count_by_month=data.get("count_by_month", {}),
        recent_documents=recent,
        expiring_soon_count=data.get("expiring_soon_count", 0),
        overdue_count=data.get("overdue_count", 0),
    )


# ── Alerts & Expiry Tracking ──────────────────────────────────────────────


def _compute_urgency(days_remaining: int) -> str:
    """Return urgency level based on days remaining."""
    if days_remaining <= 7:
        return "critical"
    elif days_remaining <= 30:
        return "warning"
    return "info"


@app.get(
    "/api/alerts",
    response_model=AlertsResponse,
    summary="Get document alerts",
    description="Return documents that are expiring soon, overdue, or have "
    "upcoming payment deadlines. Sorted by urgency.",
)
async def get_alerts(
    days_ahead: int = Query(90, ge=1, le=365, description="Look-ahead window in days"),
    urgency: Optional[str] = Query(None, description="Filter by urgency: critical, warning, info"),
    limit: int = Query(50, ge=1, le=200, description="Max results"),
) -> AlertsResponse:
    """Return alerts for expiring/overdue documents and upcoming payments."""
    today = datetime.now(timezone.utc).date()
    alerts: list[AlertItem] = []

    # Load dismissed alert keys to filter them out
    dismissed_keys = get_dismissed_alert_keys()

    # Fetch expiring documents
    expiring_docs = get_expiring_documents(days_ahead=days_ahead, limit=limit)
    for doc_dict in expiring_docs:
        exp_date_str = doc_dict.get("date_expiration")
        if not exp_date_str:
            continue
        try:
            exp_date = datetime.strptime(exp_date_str, "%Y-%m-%d").date()
        except ValueError:
            continue
        days_rem = (exp_date - today).days
        urg = _compute_urgency(days_rem)
        if urgency and urg != urgency:
            continue
        # Skip dismissed alerts
        if (doc_dict["id"], "expiration") in dismissed_keys:
            continue
        alerts.append(AlertItem(
            document=_parse_document(doc_dict),
            alert_type="expiration",
            target_date=exp_date_str,
            days_remaining=days_rem,
            urgency=urg,
        ))

    # Fetch upcoming payment deadlines
    echeance_docs = get_upcoming_echeances(days_ahead=days_ahead, limit=limit)
    for doc_dict in echeance_docs:
        ech_date_str = doc_dict.get("date_echeance")
        if not ech_date_str:
            continue
        try:
            ech_date = datetime.strptime(ech_date_str, "%Y-%m-%d").date()
        except ValueError:
            continue
        days_rem = (ech_date - today).days
        urg = _compute_urgency(days_rem)
        if urgency and urg != urgency:
            continue
        # Avoid duplicate if same doc already in alerts
        existing_ids = {a.document.id for a in alerts}
        # Skip dismissed alerts
        if (doc_dict["id"], "echeance") in dismissed_keys:
            continue
        if doc_dict["id"] not in existing_ids:
            alerts.append(AlertItem(
                document=_parse_document(doc_dict),
                alert_type="echeance",
                target_date=ech_date_str,
                days_remaining=days_rem,
                urgency=urg,
            ))

    # Sort: critical first (lowest days_remaining), then warning, then info
    urgency_order = {"critical": 0, "warning": 1, "info": 2}
    alerts.sort(key=lambda a: (urgency_order.get(a.urgency, 3), a.days_remaining))

    # Compute summary counts
    expiring_count = sum(
        1 for a in alerts
        if a.alert_type == "expiration" and 0 <= a.days_remaining <= 30
    )
    overdue_count = sum(
        1 for a in alerts
        if a.days_remaining < 0
    )
    upcoming_payments = sum(
        1 for a in alerts
        if a.alert_type == "echeance" and 0 <= a.days_remaining <= 30
    )

    return AlertsResponse(
        alerts=alerts[:limit],
        total=len(alerts),
        expiring_count=expiring_count,
        overdue_count=overdue_count,
        upcoming_payments=upcoming_payments,
    )


@app.post(
    "/api/alerts/{doc_id}/dismiss",
    summary="Dismiss an alert",
    description="Dismiss an alert for a specific document so it no longer appears "
    "in the alerts list. Can be undone.",
)
async def dismiss_alert_endpoint(
    doc_id: str,
    alert_type: str = Query("expiration", description="Alert type: 'expiration' or 'echeance'"),
) -> JSONResponse:
    """Dismiss an alert for a document."""
    if alert_type not in ("expiration", "echeance"):
        raise HTTPException(status_code=400, detail="alert_type must be 'expiration' or 'echeance'")
    doc = get_document(doc_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document '{doc_id}' not found")
    db_dismiss_alert(doc_id, alert_type)
    logger.info("Alert dismissed: doc=%s, type=%s", doc_id, alert_type)
    return JSONResponse(content={"message": "Alert dismissed", "doc_id": doc_id, "alert_type": alert_type})


@app.delete(
    "/api/alerts/{doc_id}/dismiss",
    summary="Un-dismiss an alert",
    description="Re-enable a previously dismissed alert.",
)
async def undismiss_alert_endpoint(
    doc_id: str,
    alert_type: str = Query("expiration", description="Alert type: 'expiration' or 'echeance'"),
) -> JSONResponse:
    """Un-dismiss an alert for a document."""
    if alert_type not in ("expiration", "echeance"):
        raise HTTPException(status_code=400, detail="alert_type must be 'expiration' or 'echeance'")
    db_undismiss_alert(doc_id, alert_type)
    logger.info("Alert un-dismissed: doc=%s, type=%s", doc_id, alert_type)
    return JSONResponse(content={"message": "Alert restored", "doc_id": doc_id, "alert_type": alert_type})


@app.get(
    "/api/alerts/suggestions",
    response_model=RenewalSuggestionsResponse,
    summary="Get renewal suggestions",
    description="For expired or expiring documents, suggest matching procedures "
    "that could be used to renew them.",
)
async def get_renewal_suggestions() -> RenewalSuggestionsResponse:
    """Find expired/expiring documents and suggest matching procedures."""
    suggestions: list[RenewalSuggestion] = []

    # Get documents expiring within 30 days or already expired
    expiring_docs = get_expiring_documents(days_ahead=30, limit=20)
    procedures_list = list_procedures(limit=100, offset=0)

    for doc_dict in expiring_docs:
        exp_date_str = doc_dict.get("date_expiration")
        if not exp_date_str:
            continue

        doc_response = _parse_document(doc_dict)
        doc_type = doc_dict.get("doc_type", "autre")

        # Try to find a procedure that requires this doc_type
        suggested_proc = None
        for proc in procedures_list:
            req_docs = proc.get("required_documents", [])
            if isinstance(req_docs, str):
                try:
                    req_docs = json.loads(req_docs)
                except (json.JSONDecodeError, TypeError):
                    req_docs = []
            for rd in req_docs:
                if isinstance(rd, dict) and rd.get("doc_type") == doc_type:
                    suggested_proc = _parse_procedure(proc)
                    break
            if suggested_proc:
                break

        today = datetime.now(timezone.utc).date()
        try:
            exp_date = datetime.strptime(exp_date_str, "%Y-%m-%d").date()
            days_rem = (exp_date - today).days
        except ValueError:
            days_rem = 0

        if days_rem < 0:
            reason = f"Ce document a expiré le {exp_date_str} (il y a {abs(days_rem)} jours)"
        else:
            reason = f"Ce document expire le {exp_date_str} (dans {days_rem} jours)"

        suggestions.append(RenewalSuggestion(
            document=doc_response,
            suggested_procedure=suggested_proc,
            reason=reason,
        ))

    return RenewalSuggestionsResponse(suggestions=suggestions)


@app.get(
    "/api/alerts/gaps",
    response_model=GapAlertsResponse,
    summary="Detect missing recurring documents",
    description="Analyze document date patterns to detect gaps in recurring "
    "documents like payslips or monthly invoices.",
)
async def detect_gaps() -> GapAlertsResponse:
    """Detect gaps in recurring document series (payslips, invoices, etc.)."""
    gaps: list[GapAlert] = []

    # Only analyze recurring document types
    recurring_types = ["fiche_de_paie", "facture", "quittance", "releve_bancaire"]

    for doc_type in recurring_types:
        docs = get_documents_for_gap_detection(doc_type, limit=200)
        if len(docs) < 2:
            continue

        # Group by destinataire
        by_person: dict[str, list[str]] = {}
        for doc in docs:
            person = doc.get("destinataire") or "inconnu"
            date_str = doc.get("doc_date", "")
            if date_str and len(date_str) >= 7:
                month = date_str[:7]  # YYYY-MM
                by_person.setdefault(person, []).append(month)

        for person, months in by_person.items():
            if len(months) < 2:
                continue
            unique_months = sorted(set(months))

            # Find gaps between consecutive months
            for i in range(len(unique_months) - 1):
                try:
                    current = datetime.strptime(unique_months[i], "%Y-%m")
                    nxt = datetime.strptime(unique_months[i + 1], "%Y-%m")
                    # Calculate months between
                    diff_months = (nxt.year - current.year) * 12 + (nxt.month - current.month)
                    if diff_months > 1:
                        # There's a gap — report each missing month
                        for m in range(1, diff_months):
                            missing_date = current.replace(day=1) + timedelta(days=32 * m)
                            missing_month = missing_date.strftime("%Y-%m")
                            type_labels = {
                                "fiche_de_paie": "fiche de paie",
                                "facture": "facture",
                                "quittance": "quittance",
                                "releve_bancaire": "relevé bancaire",
                            }
                            label = type_labels.get(doc_type, doc_type)
                            dest = f" pour {person}" if person != "inconnu" else ""
                            gaps.append(GapAlert(
                                doc_type=doc_type,
                                destinataire=person if person != "inconnu" else None,
                                expected_date=missing_month,
                                last_seen_date=unique_months[i],
                                message=f"{label.capitalize()}{dest} manquante pour {missing_month}",
                            ))
                except ValueError:
                    continue

    return GapAlertsResponse(gaps=gaps, total=len(gaps))


# ── Procedures ─────────────────────────────────────────────────────────────


def _parse_procedure(proc_dict: dict) -> ProcedureResponse:
    """Convert a raw database dict into a ProcedureResponse."""
    data = dict(proc_dict)
    # Ensure required_documents is a list of ProcedureRequiredDocument
    req_docs = data.get("required_documents", [])
    if isinstance(req_docs, str):
        try:
            import json as _json
            req_docs = _json.loads(req_docs)
        except (json.JSONDecodeError, TypeError):
            req_docs = []
    data["required_documents"] = [
        ProcedureRequiredDocument(**doc) if isinstance(doc, dict) else doc
        for doc in req_docs
    ]
    return ProcedureResponse(**data)


@app.post(
    "/api/procedures",
    response_model=ProcedureResponse,
    status_code=201,
    summary="Create a procedure",
    description="Create a new procedure by analyzing the provided description "
    "and/or image using the LLM. Returns the structured procedure "
    "with identified required documents.",
)
async def create_procedure(body: ProcedureCreateRequest) -> ProcedureResponse:
    """Create a new procedure via AI analysis."""
    if app.state.llm is None:
        raise HTTPException(
            status_code=503,
            detail="LLM not loaded. Cannot analyze procedure.",
        )

    # Call AI to analyze the procedure
    analysis = analyze_procedure(
        client=app.state.llm,
        procedure_type=body.procedure_type,
        image_b64=body.image_base64,
        manual_documents=body.manual_documents,
        remarks=body.remarks,
    )

    proc_id = str(uuid.uuid4())
    insert_procedure(
        proc_id=proc_id,
        name=body.name if body.name else analysis["name"],
        procedure_type=body.procedure_type,
        description=analysis.get("description"),
        required_documents=analysis.get("required_documents", []),
        remarks=body.remarks,
    )

    proc = get_procedure(proc_id)
    logger.info("Procedure %s created: '%s' (%d required documents)",
                proc_id, analysis["name"],
                len(analysis.get("required_documents", [])))
    return _parse_procedure(proc)


@app.get(
    "/api/procedures",
    response_model=ProcedureListResponse,
    summary="List procedures",
    description="Return a paginated list of all procedures.",
)
async def list_procs(
    limit: int = Query(50, ge=1, le=200, description="Max results"),
    offset: int = Query(0, ge=0, description="Pagination offset"),
) -> ProcedureListResponse:
    """Retrieve a paginated list of procedures."""
    rows = list_procedures(limit=limit, offset=offset)
    total = count_procedures()
    procedures = [_parse_procedure(row) for row in rows]
    return ProcedureListResponse(
        procedures=procedures,
        total=total,
        limit=limit,
        offset=offset,
    )


@app.get(
    "/api/procedures/{proc_id}",
    response_model=ProcedureResponse,
    summary="Get a procedure",
    description="Retrieve a single procedure with its list of required documents.",
)
async def get_proc(proc_id: str) -> ProcedureResponse:
    """Fetch a single procedure by ID."""
    proc = get_procedure(proc_id)
    if proc is None:
        raise HTTPException(status_code=404, detail=f"Procedure '{proc_id}' not found")
    return _parse_procedure(proc)


@app.put(
    "/api/procedures/{proc_id}",
    response_model=ProcedureResponse,
    summary="Update a procedure",
    description="Partially update a procedure's metadata and required documents. "
    "Only non-null fields in the request body are applied.",
)
async def update_proc(proc_id: str, body: ProcedureUpdateRequest) -> ProcedureResponse:
    """Apply a partial update to an existing procedure."""
    proc = get_procedure(proc_id)
    if proc is None:
        raise HTTPException(status_code=404, detail=f"Procedure '{proc_id}' not found")

    update_dict = body.model_dump(exclude_none=True)
    if not update_dict:
        raise HTTPException(status_code=400, detail="No fields provided for update")

    # Convert required_documents from list of Pydantic models to list of dicts
    if "required_documents" in update_dict:
        update_dict["required_documents"] = [
            rd.model_dump() if hasattr(rd, "model_dump") else rd
            for rd in update_dict["required_documents"]
        ]

    db_update_procedure(proc_id, **update_dict)
    logger.info("Procedure %s updated: %s", proc_id, list(update_dict.keys()))

    updated = get_procedure(proc_id)
    return _parse_procedure(updated)


@app.delete(
    "/api/procedures/{proc_id}",
    summary="Delete a procedure",
    description="Permanently delete a procedure and all its executions.",
)
async def delete_proc(proc_id: str) -> JSONResponse:
    """Delete a procedure."""
    proc = get_procedure(proc_id)
    if proc is None:
        raise HTTPException(status_code=404, detail=f"Procedure '{proc_id}' not found")
    db_delete_procedure(proc_id)
    logger.info("Procedure %s deleted", proc_id)
    return JSONResponse(content={"message": "Procedure deleted successfully"})


@app.post(
    "/api/procedures/{proc_id}/execute",
    response_model=ProcedureExecutionResponse,
    summary="Execute a procedure",
    description="Execute a procedure by searching for matching documents for "
    "the given person. Uses hybrid search and AI-powered matching "
    "to find the best document for each requirement.",
)
async def execute_procedure(
    proc_id: str,
    body: ProcedureExecuteRequest,
) -> ProcedureExecutionResponse:
    """Execute a procedure: search and match documents for each requirement."""
    proc = get_procedure(proc_id)
    if proc is None:
        raise HTTPException(status_code=404, detail=f"Procedure '{proc_id}' not found")

    if app.state.llm is None:
        raise HTTPException(
            status_code=503,
            detail="LLM not loaded. Cannot execute procedure.",
        )

    required_docs = proc.get("required_documents", [])
    matched_results: list[dict] = []

    for req_doc in required_docs:
        doc_type = req_doc.get("doc_type", "autre")
        label = req_doc.get("label", doc_type)

        # Step 1: Search candidates by type and person name in DB
        candidates = search_documents_by_type_and_name(
            doc_type=doc_type,
            person_name=body.person_name,
            limit=10,
        )

        # Step 2: Also try hybrid search for broader coverage
        if app.state.embedding_model is not None and app.state.embeddings_cache:
            try:
                search_query = f"{label} {body.person_name}"
                hybrid_results = hybrid_search(
                    query=search_query,
                    embedding_model=app.state.embedding_model,
                    embeddings_cache=app.state.embeddings_cache,
                    top_k=10,
                )
                # Add hybrid results that match the doc_type and aren't already in candidates
                existing_ids = {c["id"] for c in candidates}
                for result in hybrid_results:
                    doc = result["document"]
                    if doc["id"] not in existing_ids and doc.get("doc_type") == doc_type:
                        candidates.append(doc)
                        existing_ids.add(doc["id"])
            except Exception:
                logger.warning("Hybrid search failed for '%s' — using DB results only", label)

        # Step 3: Use AI to select the best match
        selected_doc = None
        if candidates:
            match_result = match_document_for_procedure(
                client=app.state.llm,
                required_doc=req_doc,
                person_name=body.person_name,
                candidate_docs=candidates,
            )

            selected_id = match_result.get("selected_id")
            if selected_id:
                # Find the selected document in candidates
                for c in candidates:
                    if c["id"] == selected_id:
                        selected_doc = c
                        break

        if selected_doc:
            doc_response = _parse_document(selected_doc)
            matched_results.append({
                "required_doc_type": doc_type,
                "required_label": label,
                "found": True,
                "document": doc_response.model_dump(),
            })
        else:
            matched_results.append({
                "required_doc_type": doc_type,
                "required_label": label,
                "found": False,
                "document": None,
            })

    # Save execution
    exec_id = str(uuid.uuid4())
    insert_procedure_execution(
        exec_id=exec_id,
        procedure_id=proc_id,
        person_name=body.person_name,
        matched_documents=matched_results,
        status="completed",
    )

    logger.info("Procedure %s executed for '%s': %d/%d documents found",
                proc_id, body.person_name,
                sum(1 for m in matched_results if m["found"]),
                len(matched_results))

    # Build response
    matched_models = []
    for m in matched_results:
        doc_resp = None
        if m["document"]:
            doc_resp = DocumentResponse(**m["document"])
        matched_models.append(MatchedDocument(
            required_doc_type=m["required_doc_type"],
            required_label=m["required_label"],
            found=m["found"],
            document=doc_resp,
        ))

    execution = get_procedure_execution(exec_id)
    return ProcedureExecutionResponse(
        id=exec_id,
        procedure_id=proc_id,
        person_name=body.person_name,
        matched_documents=matched_models,
        status="completed",
        created_at=execution["created_at"],
    )


# ---------------------------------------------------------------------------
# Settings endpoints
# ---------------------------------------------------------------------------


def _mask_api_key(key: str) -> str:
    """Return a masked version of an API key, showing only the last 4 chars."""
    if not key or len(key) <= 4:
        return "****"
    return "*" * (len(key) - 4) + key[-4:]


@app.get(
    "/api/settings",
    response_model=SettingsResponse,
    tags=["settings"],
    summary="Get current application settings",
)
async def get_settings():
    """Return current settings. The API key is masked for security."""
    saved = load_settings()
    return SettingsResponse(
        version=_VERSION,
        ai_provider=_config_module.AI_PROVIDER,
        openrouter_api_key=_mask_api_key(_config_module.OPENROUTER_API_KEY),
        openrouter_model=_config_module.OPENROUTER_MODEL,
        openrouter_base_url=_config_module.OPENROUTER_BASE_URL,
        ollama_base_url=_config_module.OLLAMA_BASE_URL,
        ollama_model=_config_module.OLLAMA_MODEL,
        llamacpp_base_url=_config_module.LLAMACPP_BASE_URL,
        llamacpp_model=_config_module.LLAMACPP_MODEL,
        data_dir=DATA_DIR,
        nas_sync_enabled=saved.get("nas_sync_enabled", False),
        nas_host=saved.get("nas_host", "192.168.1.100"),
        nas_share=saved.get("nas_share", "NAS_Commun_Vol2"),
        nas_path=saved.get("nas_path", "DOCUMIND/originals"),
        nas_username=saved.get("nas_username", ""),
        nas_sync_hour=saved.get("nas_sync_hour", 7),
        nas_sync_minute=saved.get("nas_sync_minute", 0),
    )


@app.put(
    "/api/settings",
    response_model=SettingsResponse,
    tags=["settings"],
    summary="Update application settings",
)
async def update_settings(body: SettingsUpdateRequest):
    """Update settings, persist to disk, and hot-reload the LLM client."""
    # Load existing saved settings
    current = load_settings()

    # Merge in the new values (only non-None fields)
    if body.ai_provider is not None:
        current["ai_provider"] = body.ai_provider
        _config_module.AI_PROVIDER = body.ai_provider
    if body.openrouter_api_key is not None:
        current["openrouter_api_key"] = body.openrouter_api_key
        _config_module.OPENROUTER_API_KEY = body.openrouter_api_key
    if body.openrouter_model is not None:
        current["openrouter_model"] = body.openrouter_model
        _config_module.OPENROUTER_MODEL = body.openrouter_model
    if body.openrouter_base_url is not None:
        current["openrouter_base_url"] = body.openrouter_base_url
        _config_module.OPENROUTER_BASE_URL = body.openrouter_base_url
    if body.ollama_base_url is not None:
        current["ollama_base_url"] = body.ollama_base_url
        _config_module.OLLAMA_BASE_URL = body.ollama_base_url
    if body.ollama_model is not None:
        current["ollama_model"] = body.ollama_model
        _config_module.OLLAMA_MODEL = body.ollama_model
    if body.llamacpp_base_url is not None:
        current["llamacpp_base_url"] = body.llamacpp_base_url
        _config_module.LLAMACPP_BASE_URL = body.llamacpp_base_url
    if body.llamacpp_model is not None:
        current["llamacpp_model"] = body.llamacpp_model
        _config_module.LLAMACPP_MODEL = body.llamacpp_model

    # NAS sync settings
    nas_changed = False
    if body.nas_sync_enabled is not None:
        current["nas_sync_enabled"] = body.nas_sync_enabled
        nas_changed = True
    if body.nas_host is not None:
        current["nas_host"] = body.nas_host
        nas_changed = True
    if body.nas_share is not None:
        current["nas_share"] = body.nas_share
        nas_changed = True
    if body.nas_path is not None:
        current["nas_path"] = body.nas_path
        nas_changed = True
    if body.nas_username is not None:
        current["nas_username"] = body.nas_username
        nas_changed = True
    if body.nas_password is not None:
        current["nas_password"] = body.nas_password
        nas_changed = True
    if body.nas_sync_hour is not None:
        current["nas_sync_hour"] = body.nas_sync_hour
        nas_changed = True
    if body.nas_sync_minute is not None:
        current["nas_sync_minute"] = body.nas_sync_minute
        nas_changed = True

    # Persist to disk
    save_settings(current)
    logger.info("Settings saved to disk")

    # Hot-reload LLM client
    try:
        if app.state.llm is not None:
            app.state.llm.close()
            logger.info("Previous LLM client closed")
        app.state.llm = init_llm_client()
        logger.info("LLM client reloaded with new settings")
    except ValueError as exc:
        app.state.llm = None
        logger.warning("LLM client not available after settings update: %s", exc)

    # Apply cron schedule when NAS settings changed
    if nas_changed:
        from nas_sync import apply_cron_schedule
        cron_result = apply_cron_schedule()
        logger.info("Cron schedule update: %s", cron_result)

    return SettingsResponse(
        version=_VERSION,
        ai_provider=_config_module.AI_PROVIDER,
        openrouter_api_key=_mask_api_key(_config_module.OPENROUTER_API_KEY),
        openrouter_model=_config_module.OPENROUTER_MODEL,
        openrouter_base_url=_config_module.OPENROUTER_BASE_URL,
        ollama_base_url=_config_module.OLLAMA_BASE_URL,
        ollama_model=_config_module.OLLAMA_MODEL,
        llamacpp_base_url=_config_module.LLAMACPP_BASE_URL,
        llamacpp_model=_config_module.LLAMACPP_MODEL,
        data_dir=DATA_DIR,
        nas_sync_enabled=current.get("nas_sync_enabled", False),
        nas_host=current.get("nas_host", "192.168.1.100"),
        nas_share=current.get("nas_share", "NAS_Commun_Vol2"),
        nas_path=current.get("nas_path", "DOCUMIND/originals"),
        nas_username=current.get("nas_username", ""),
        nas_sync_hour=current.get("nas_sync_hour", 7),
        nas_sync_minute=current.get("nas_sync_minute", 0),
    )


# ── Update ─────────────────────────────────────────────────────────────────


@app.get(
    "/api/update/check",
    summary="Check for updates",
    description="Fetch origin/main and compare with local HEAD. "
    "Returns whether an update is available and how many commits behind.",
)
async def update_check():
    """Check GitHub for a newer version without applying anything."""
    return check_for_update()


@app.post(
    "/api/update/apply",
    summary="Apply update and restart",
    description="Run git pull, pip install -r requirements.txt, then restart "
    "the server process via os.execv. The response is sent before restart.",
)
async def update_apply():
    """Pull latest code, reinstall deps, and restart the server."""
    import asyncio

    async def _run():
        # Small delay so the HTTP response is sent first
        await asyncio.sleep(0.8)

        ok, msg = apply_update()
        if not ok:
            logger.error("Update aborted (git pull failed): %s", msg)
            return

        ok, msg = install_dependencies()
        if not ok:
            logger.error("Update aborted (pip install failed): %s", msg)
            return

        logger.info("Restarting server after successful update")
        restart_server()

    asyncio.create_task(_run())
    return {"status": "updating", "message": "Mise à jour en cours, redémarrage imminent…"}


# ---------------------------------------------------------------------------
# NAS Sync
# ---------------------------------------------------------------------------


@app.post(
    "/api/sync/nas",
    summary="Sync documents from NAS",
    description=(
        "Mount the configured CIFS/SMB NAS share and import any new documents "
        "that have not yet been uploaded to Documind. "
        "Requires cifs-utils installed in the container and proper NAS credentials "
        "in NAS_USERNAME / NAS_PASSWORD environment variables."
    ),
)
async def sync_nas() -> JSONResponse:
    """Trigger a NAS → Documind document sync via the processing queue."""
    import asyncio
    from nas_sync import sync_from_nas

    async def _job():
        loop = asyncio.get_event_loop()
        summary = await loop.run_in_executor(None, sync_from_nas)
        logger.info("NAS sync completed: %s", summary)
        # Upload each discovered file is handled inside sync_from_nas via the API,
        # but refresh embeddings cache after the sync finishes.
        app.state.embeddings_cache = refresh_embeddings_cache(app.state.embeddings_cache)

    await get_queue().enqueue(label="Synchronisation NAS", fn=_job)
    return JSONResponse(
        status_code=202,
        content={"status": "accepted", "message": "NAS sync queued."},
    )


@app.post(
    "/api/sync/nas/blocking",
    summary="Sync documents from NAS (blocking)",
    description="Same as /api/sync/nas but waits for the sync to complete and returns the full summary.",
)
async def sync_nas_blocking() -> JSONResponse:
    """Trigger a NAS → Documind document sync synchronously and return the result."""
    import asyncio
    from nas_sync import sync_from_nas

    loop = asyncio.get_event_loop()
    summary = await loop.run_in_executor(None, sync_from_nas)
    app.state.embeddings_cache = refresh_embeddings_cache(app.state.embeddings_cache)
    return JSONResponse(content=summary)


# ---------------------------------------------------------------------------
# Processing queue status
# ---------------------------------------------------------------------------


@app.get(
    "/api/queue",
    response_model=QueueStatusResponse,
    summary="Processing queue status",
    description="Returns the current state of the FIFO processing queue: active job, pending jobs, and recent history.",
)
async def get_queue_status() -> QueueStatusResponse:
    """Return a snapshot of the processing queue."""
    snap = get_queue().snapshot()
    return QueueStatusResponse(**snap)


# ---------------------------------------------------------------------------
# llama.cpp server connectivity test
# ---------------------------------------------------------------------------


@app.post(
    "/api/llamacpp/test",
    summary="Test llama.cpp server connection",
    description="Sends a minimal request to the configured llama.cpp server and returns connection status.",
)
async def test_llamacpp_connection() -> JSONResponse:
    """Test connectivity to the llama.cpp server."""
    import asyncio
    import httpx as _httpx

    base_url = _config_module.LLAMACPP_BASE_URL.rstrip("/")
    try:
        loop = asyncio.get_event_loop()
        def _probe():
            with _httpx.Client(timeout=5.0) as c:
                # Try /health endpoint first (llama-server exposes it)
                try:
                    r = c.get(f"{base_url}/health")
                    if r.status_code == 200:
                        return {"ok": True, "detail": r.json()}
                except Exception:
                    pass
                # Fallback: try /v1/models
                r = c.get(f"{base_url}/v1/models")
                r.raise_for_status()
                return {"ok": True, "detail": r.json()}
        result = await loop.run_in_executor(None, _probe)
        return JSONResponse(content={"status": "ok", **result})
    except Exception as exc:
        return JSONResponse(
            status_code=503,
            content={"status": "error", "detail": str(exc)},
        )


# ---------------------------------------------------------------------------
# Live log streaming (SSE)
# ---------------------------------------------------------------------------


@app.get(
    "/api/logs",
    summary="Stream backend logs",
    description="Server-Sent Events stream of backend log lines. "
    "Sends the last 200 buffered lines immediately, then streams new lines as they arrive.",
)
async def stream_logs():
    """SSE endpoint — streams backend log lines to the browser."""
    import asyncio

    async def _generate():
        # Send buffered history first
        with _LOG_LOCK:
            snapshot = list(_LOG_BUFFER)[-200:]
        for line in snapshot:
            yield f"data: {line}\n\n"

        # Then tail new lines
        last_size = len(_LOG_BUFFER)
        while True:
            await asyncio.sleep(0.5)
            with _LOG_LOCK:
                current = list(_LOG_BUFFER)
            if len(current) > last_size:
                for line in current[last_size:]:
                    yield f"data: {line}\n\n"
            last_size = len(current)

    return StreamingResponse(
        _generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


# ---------------------------------------------------------------------------
# Static file serving — must come AFTER all API routes
# ---------------------------------------------------------------------------

if STATIC_DIR.exists():
    app.mount("/", StaticFiles(directory=str(STATIC_DIR), html=True), name="static")

# ---------------------------------------------------------------------------
# Entry point for direct execution
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    import uvicorn

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )

    parser = argparse.ArgumentParser(description="DocuMind server")
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip the frontend npm build (used in Docker where static/ is pre-built)",
    )
    args = parser.parse_args()

    if not args.skip_build:
        build_frontend()
        # Re-mount static files if they were just built and weren't mounted
        # at module-load time (static/ didn't exist yet).
        if STATIC_DIR.exists():
            # Check if already mounted
            route_paths = [r.path for r in app.routes]
            if "" not in route_paths and "/" not in route_paths:
                app.mount(
                    "/",
                    StaticFiles(directory=str(STATIC_DIR), html=True),
                    name="static",
                )

    uvicorn.run(app, host=HOST, port=PORT, reload=False)
