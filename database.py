"""DocuMind database layer — SQLite with FTS5 for full-text search."""

import json
import logging
import os
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any

from config import DB_PATH

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    """Return the current UTC time as an ISO-8601 string with 'Z' suffix."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _get_connection() -> sqlite3.Connection:
    """Open a new SQLite connection with WAL mode and foreign keys enabled."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA foreign_keys=ON;")
    conn.row_factory = sqlite3.Row
    return conn


# ---------------------------------------------------------------------------
# Schema initialization
# ---------------------------------------------------------------------------

def init_db() -> None:
    """Create all tables, FTS5 virtual tables, and synchronization triggers.

    Safe to call multiple times — uses IF NOT EXISTS throughout.
    """
    with _get_connection() as conn:
        cur = conn.cursor()

        # -- documents table -------------------------------------------------
        cur.execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id          TEXT PRIMARY KEY,
                filename    TEXT NOT NULL,
                filepath    TEXT NOT NULL,
                title       TEXT,
                text_content TEXT,
                doc_type    TEXT,
                emetteur    TEXT,
                doc_date    TEXT,
                montant     REAL,
                reference   TEXT,
                destinataire TEXT,
                resume      TEXT,
                tags        TEXT,
                embedding   BLOB,
                status      TEXT NOT NULL DEFAULT 'processing',
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            );
        """)

        # Migration: add title column for existing databases
        try:
            cur.execute("ALTER TABLE documents ADD COLUMN title TEXT;")
        except Exception:
            pass  # Column already exists

        # Migration: add date_expiration column for expiry tracking
        try:
            cur.execute("ALTER TABLE documents ADD COLUMN date_expiration TEXT;")
        except Exception:
            pass  # Column already exists

        # Migration: add date_echeance column for payment deadline tracking
        try:
            cur.execute("ALTER TABLE documents ADD COLUMN date_echeance TEXT;")
        except Exception:
            pass  # Column already exists

        # -- FTS5 virtual table (content-sync with documents) ----------------
        # Drop and recreate to ensure schema matches (multi-column index).
        # The rebuild at the end of init_db re-populates the index.
        cur.execute("DROP TABLE IF EXISTS documents_fts;")
        cur.execute("""
            CREATE VIRTUAL TABLE documents_fts
            USING fts5(
                title, filename, text_content, emetteur, resume, tags,
                content='documents',
                content_rowid='rowid'
            );
        """)

        # -- Triggers to keep FTS in sync -----------------------------------
        _FTS_COLS = "title, filename, text_content, emetteur, resume, tags"

        cur.execute("DROP TRIGGER IF EXISTS documents_ai;")
        cur.execute(f"""
            CREATE TRIGGER documents_ai AFTER INSERT ON documents
            BEGIN
                INSERT INTO documents_fts(rowid, {_FTS_COLS})
                VALUES (new.rowid, new.title, new.filename, new.text_content,
                        new.emetteur, new.resume, new.tags);
            END;
        """)

        cur.execute("DROP TRIGGER IF EXISTS documents_ad;")
        cur.execute(f"""
            CREATE TRIGGER documents_ad AFTER DELETE ON documents
            BEGIN
                INSERT INTO documents_fts(documents_fts, rowid, {_FTS_COLS})
                VALUES ('delete', old.rowid, old.title, old.filename,
                        old.text_content, old.emetteur, old.resume, old.tags);
            END;
        """)

        cur.execute("DROP TRIGGER IF EXISTS documents_au;")
        cur.execute(f"""
            CREATE TRIGGER documents_au AFTER UPDATE ON documents
            BEGIN
                INSERT INTO documents_fts(documents_fts, rowid, {_FTS_COLS})
                VALUES ('delete', old.rowid, old.title, old.filename,
                        old.text_content, old.emetteur, old.resume, old.tags);
                INSERT INTO documents_fts(rowid, {_FTS_COLS})
                VALUES (new.rowid, new.title, new.filename, new.text_content,
                        new.emetteur, new.resume, new.tags);
            END;
        """)

        # -- chat_sessions table ---------------------------------------------
        cur.execute("""
            CREATE TABLE IF NOT EXISTS chat_sessions (
                id         TEXT PRIMARY KEY,
                title      TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
        """)

        # -- chat_history table ----------------------------------------------
        cur.execute("""
            CREATE TABLE IF NOT EXISTS chat_history (
                id              TEXT PRIMARY KEY,
                session_id      TEXT REFERENCES chat_sessions(id) ON DELETE CASCADE,
                message         TEXT NOT NULL,
                role            TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                context_doc_ids TEXT,
                created_at      TEXT NOT NULL
            );
        """)

        # Migration: add session_id column for existing databases
        try:
            cur.execute("ALTER TABLE chat_history ADD COLUMN session_id TEXT REFERENCES chat_sessions(id) ON DELETE CASCADE;")
        except Exception:
            pass  # Column already exists

        # -- procedures table ------------------------------------------------
        cur.execute("""
            CREATE TABLE IF NOT EXISTS procedures (
                id                  TEXT PRIMARY KEY,
                name                TEXT NOT NULL,
                procedure_type      TEXT NOT NULL,
                description         TEXT,
                required_documents  TEXT,
                remarks             TEXT,
                status              TEXT NOT NULL DEFAULT 'active',
                created_at          TEXT NOT NULL,
                updated_at          TEXT NOT NULL
            );
        """)

        # -- procedure_executions table --------------------------------------
        cur.execute("""
            CREATE TABLE IF NOT EXISTS procedure_executions (
                id                  TEXT PRIMARY KEY,
                procedure_id        TEXT NOT NULL,
                person_name         TEXT NOT NULL,
                matched_documents   TEXT,
                status              TEXT NOT NULL DEFAULT 'completed',
                created_at          TEXT NOT NULL,
                FOREIGN KEY (procedure_id) REFERENCES procedures(id) ON DELETE CASCADE
            );
        """)

        # -- dismissed_alerts table ------------------------------------------
        cur.execute("""
            CREATE TABLE IF NOT EXISTS dismissed_alerts (
                id         TEXT PRIMARY KEY,
                doc_id     TEXT NOT NULL,
                alert_type TEXT NOT NULL CHECK(alert_type IN ('expiration', 'echeance')),
                dismissed_at TEXT NOT NULL,
                UNIQUE(doc_id, alert_type)
            );
        """)

        # -- Rebuild FTS index from content table ----------------------------
        # Ensures the index is always in sync, even for pre-existing data.
        cur.execute("INSERT INTO documents_fts(documents_fts) VALUES('rebuild');")
        logger.info("FTS5 index rebuilt")

        conn.commit()


# ---------------------------------------------------------------------------
# Document CRUD
# ---------------------------------------------------------------------------

def insert_document(doc_id: str, filename: str, filepath: str) -> None:
    """Insert a new document record with status 'processing'.

    Args:
        doc_id: UUID string for the document.
        filename: Original filename as uploaded.
        filepath: Path to the stored original file on disk.
    """
    now = _now_iso()
    with _get_connection() as conn:
        conn.execute(
            """
            INSERT INTO documents (id, filename, filepath, status, created_at, updated_at)
            VALUES (?, ?, ?, 'processing', ?, ?);
            """,
            (doc_id, filename, filepath, now, now),
        )
        conn.commit()


def update_document_text(doc_id: str, text_content: str) -> None:
    """Store extracted / OCR text for a document.

    Args:
        doc_id: UUID of the target document.
        text_content: Full extracted text.
    """
    now = _now_iso()
    with _get_connection() as conn:
        conn.execute(
            """
            UPDATE documents SET text_content = ?, updated_at = ? WHERE id = ?;
            """,
            (text_content, now, doc_id),
        )
        conn.commit()


def update_document_metadata(
    doc_id: str,
    doc_type: str | None,
    emetteur: str | None,
    doc_date: str | None,
    montant: float | None,
    reference: str | None,
    destinataire: str | None,
    resume: str | None,
    tags: list[str] | None,
    title: str | None = None,
    date_expiration: str | None = None,
    date_echeance: str | None = None,
) -> None:
    """Store LLM-extracted metadata for a document.

    Args:
        doc_id: UUID of the target document.
        doc_type: Classified document type (e.g. 'facture', 'contrat').
        emetteur: Issuer / sender name.
        doc_date: Date found in the document (ISO-8601 preferred).
        montant: Monetary amount if applicable.
        reference: Reference number or code.
        destinataire: Recipient name.
        resume: Short summary of the document.
        tags: List of keyword tags.
        title: Human-readable document title generated by the LLM.
        date_expiration: Expiry / end-of-validity date (YYYY-MM-DD or None).
        date_echeance: Payment due date (YYYY-MM-DD or None).
    """
    now = _now_iso()
    tags_json = json.dumps(tags, ensure_ascii=False) if tags is not None else None
    with _get_connection() as conn:
        conn.execute(
            """
            UPDATE documents
            SET title = ?, doc_type = ?, emetteur = ?, doc_date = ?, montant = ?,
                reference = ?, destinataire = ?, resume = ?, tags = ?,
                date_expiration = ?, date_echeance = ?,
                updated_at = ?
            WHERE id = ?;
            """,
            (title, doc_type, emetteur, doc_date, montant, reference,
             destinataire, resume, tags_json,
             date_expiration, date_echeance,
             now, doc_id),
        )
        conn.commit()


def update_document_embedding(doc_id: str, embedding_blob: bytes) -> None:
    """Store the serialized embedding vector for a document.

    Args:
        doc_id: UUID of the target document.
        embedding_blob: Binary-serialized embedding (e.g. numpy .tobytes()).
    """
    now = _now_iso()
    with _get_connection() as conn:
        conn.execute(
            """
            UPDATE documents SET embedding = ?, updated_at = ? WHERE id = ?;
            """,
            (embedding_blob, now, doc_id),
        )
        conn.commit()


def update_document_status(doc_id: str, status: str) -> None:
    """Update the processing status of a document.

    Args:
        doc_id: UUID of the target document.
        status: New status value (e.g. 'processing', 'ready', 'error').
    """
    now = _now_iso()
    with _get_connection() as conn:
        conn.execute(
            """
            UPDATE documents SET status = ?, updated_at = ? WHERE id = ?;
            """,
            (status, now, doc_id),
        )
        conn.commit()


def _row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    """Convert a sqlite3.Row to a plain dict, deserializing JSON fields."""
    if row is None:
        return None
    d = dict(row)
    # Deserialize tags from JSON string to list
    if d.get("tags") is not None:
        try:
            d["tags"] = json.loads(d["tags"])
        except (json.JSONDecodeError, TypeError):
            d["tags"] = []
    return d


def get_document(doc_id: str) -> dict[str, Any] | None:
    """Retrieve a single document by its UUID.

    Args:
        doc_id: UUID of the document.

    Returns:
        Document as a dict with all columns, or None if not found.
    """
    with _get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM documents WHERE id = ?;",
            (doc_id,),
        ).fetchone()
    return _row_to_dict(row)


def _sanitize_fts_query(query: str) -> str:
    """Escape a user query for safe use with FTS5 MATCH.

    Wraps each whitespace-separated token in double quotes so that
    FTS5 special operators (``AND``, ``OR``, ``NOT``, ``NEAR``, ``*``,
    ``^``, etc.) are treated as literal text.

    Returns:
        Sanitized query string, or empty string if input is blank.
    """
    tokens = query.strip().split()
    if not tokens:
        return ""
    escaped = []
    for token in tokens:
        # Double any existing quotes inside the token
        token = token.replace('"', '""')
        escaped.append(f'"{token}"')
    return " ".join(escaped)


def _build_filter_clauses(
    doc_type: str | None = None,
    emetteur: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    q: str | None = None,
) -> tuple[str, str, list[Any]]:
    """Build shared FROM/JOIN and WHERE fragments for document queries.

    Returns:
        ``(base_sql, where_sql, params)`` tuple.
    """
    conditions: list[str] = []
    params: list[Any] = []

    if q:
        sanitized = _sanitize_fts_query(q)
        if sanitized:
            base = """
                SELECT d.* FROM documents d
                INNER JOIN documents_fts f ON d.rowid = f.rowid
            """
            conditions.append("documents_fts MATCH ?")
            params.append(sanitized)
        else:
            base = "SELECT * FROM documents d"
    else:
        base = "SELECT * FROM documents d"

    if doc_type is not None:
        conditions.append("d.doc_type = ?")
        params.append(doc_type)
    if emetteur is not None:
        conditions.append("d.emetteur = ?")
        params.append(emetteur)
    if date_from is not None:
        conditions.append("d.doc_date >= ?")
        params.append(date_from)
    if date_to is not None:
        conditions.append("d.doc_date <= ?")
        params.append(date_to)

    where = (" WHERE " + " AND ".join(conditions)) if conditions else ""
    return base, where, params


def list_documents(
    doc_type: str | None = None,
    emetteur: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    q: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> list[dict[str, Any]]:
    """Return a filtered and paginated list of documents.

    Args:
        doc_type: Filter by document type.
        emetteur: Filter by issuer/sender.
        date_from: Filter documents with doc_date >= this value.
        date_to: Filter documents with doc_date <= this value.
        q: Full-text search query (uses FTS5 MATCH).
        limit: Maximum number of results.
        offset: Pagination offset.

    Returns:
        List of document dicts matching the filters.
    """
    base, where, params = _build_filter_clauses(
        doc_type=doc_type, emetteur=emetteur,
        date_from=date_from, date_to=date_to, q=q,
    )
    sql = f"{base}{where} ORDER BY d.created_at DESC LIMIT ? OFFSET ?;"
    params.extend([limit, offset])

    with _get_connection() as conn:
        rows = conn.execute(sql, params).fetchall()
    return [_row_to_dict(row) for row in rows]


def count_documents(
    doc_type: str | None = None,
    emetteur: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    q: str | None = None,
) -> int:
    """Return the total number of documents matching the given filters.

    Uses the same filter logic as :func:`list_documents` but returns
    only the count (no LIMIT / OFFSET).
    """
    base, where, params = _build_filter_clauses(
        doc_type=doc_type, emetteur=emetteur,
        date_from=date_from, date_to=date_to, q=q,
    )
    # Replace the SELECT columns with COUNT(*)
    count_base = re.sub(r"SELECT .+? FROM", "SELECT COUNT(*) AS cnt FROM", base, count=1)
    sql = f"{count_base}{where};"

    with _get_connection() as conn:
        row = conn.execute(sql, params).fetchone()
    return row["cnt"] if row else 0


def update_document_fields(doc_id: str, **fields: Any) -> None:
    """Partially update document metadata by providing arbitrary field values.

    Only columns present in the documents table are accepted. The
    ``updated_at`` column is automatically refreshed.

    Args:
        doc_id: UUID of the target document.
        **fields: Column-name / value pairs to update.

    Raises:
        ValueError: If no fields are provided.
    """
    allowed = {
        "filename", "filepath", "title", "text_content", "doc_type", "emetteur",
        "doc_date", "montant", "reference", "destinataire", "resume",
        "tags", "embedding", "status",
        "date_expiration", "date_echeance",
    }
    to_update = {k: v for k, v in fields.items() if k in allowed}
    if not to_update:
        raise ValueError("No valid fields provided for update.")

    # Serialize tags if present
    if "tags" in to_update and isinstance(to_update["tags"], list):
        to_update["tags"] = json.dumps(to_update["tags"], ensure_ascii=False)

    to_update["updated_at"] = _now_iso()
    set_clause = ", ".join(f"{col} = ?" for col in to_update)
    values = list(to_update.values()) + [doc_id]

    with _get_connection() as conn:
        conn.execute(
            f"UPDATE documents SET {set_clause} WHERE id = ?;",
            values,
        )
        conn.commit()


def delete_document(doc_id: str) -> None:
    """Delete a document record and its original file from disk.

    The FTS entry is removed automatically via the AFTER DELETE trigger.

    Args:
        doc_id: UUID of the document to delete.
    """
    with _get_connection() as conn:
        row = conn.execute(
            "SELECT filepath FROM documents WHERE id = ?;",
            (doc_id,),
        ).fetchone()
        conn.execute("DELETE FROM documents WHERE id = ?;", (doc_id,))
        conn.commit()

    # Remove original file from disk (best-effort)
    if row and row["filepath"]:
        try:
            os.remove(row["filepath"])
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Full-text search
# ---------------------------------------------------------------------------

def search_fts(query: str, limit: int = 20) -> list[dict[str, Any]]:
    """Perform an FTS5 search on document text content.

    The raw *query* is sanitised before being passed to FTS5 MATCH so
    that user input containing special FTS5 operators is handled safely.

    Args:
        query: User search string (will be sanitised for FTS5).
        limit: Maximum number of results.

    Returns:
        List of document dicts, each augmented with a ``rank`` score.
    """
    sanitized = _sanitize_fts_query(query)
    if not sanitized:
        return []

    sql = """
        SELECT d.*, f.rank
        FROM documents_fts f
        INNER JOIN documents d ON d.rowid = f.rowid
        WHERE documents_fts MATCH ?
        ORDER BY f.rank
        LIMIT ?;
    """
    with _get_connection() as conn:
        rows = conn.execute(sql, (sanitized, limit)).fetchall()
    results: list[dict[str, Any]] = []
    for row in rows:
        d = _row_to_dict(row)
        if d is not None:
            results.append(d)
    return results


# ---------------------------------------------------------------------------
# Embeddings
# ---------------------------------------------------------------------------

def get_all_embeddings() -> list[tuple[str, bytes]]:
    """Return all document embeddings for semantic search.

    Returns:
        List of (doc_id, embedding_blob) tuples for documents with non-null
        embeddings.
    """
    with _get_connection() as conn:
        rows = conn.execute(
            "SELECT id, embedding FROM documents WHERE embedding IS NOT NULL;"
        ).fetchall()
    return [(row["id"], row["embedding"]) for row in rows]


# ---------------------------------------------------------------------------
# Chat sessions
# ---------------------------------------------------------------------------

def create_chat_session(session_id: str, title: str) -> None:
    """Create a new chat session.

    Args:
        session_id: UUID string for the session.
        title: Display title for the session.
    """
    now = _now_iso()
    with _get_connection() as conn:
        conn.execute(
            """
            INSERT INTO chat_sessions (id, title, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """,
            (session_id, title, now, now),
        )
        conn.commit()


def get_chat_session(session_id: str) -> dict[str, Any] | None:
    """Retrieve a single chat session by its UUID.

    Args:
        session_id: UUID of the session.

    Returns:
        Session as a dict, or None if not found.
    """
    with _get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM chat_sessions WHERE id = ?;",
            (session_id,),
        ).fetchone()
    if row is None:
        return None
    return dict(row)


def list_chat_sessions(limit: int = 50, offset: int = 0) -> list[dict[str, Any]]:
    """Return a paginated list of chat sessions ordered by most recent first.

    Args:
        limit: Maximum number of sessions to return.
        offset: Pagination offset.

    Returns:
        List of session dicts.
    """
    with _get_connection() as conn:
        rows = conn.execute(
            "SELECT * FROM chat_sessions ORDER BY updated_at DESC LIMIT ? OFFSET ?;",
            (limit, offset),
        ).fetchall()
    return [dict(row) for row in rows]


def count_chat_sessions() -> int:
    """Return the total number of chat sessions."""
    with _get_connection() as conn:
        row = conn.execute("SELECT COUNT(*) AS cnt FROM chat_sessions;").fetchone()
    return row["cnt"] if row else 0


def update_chat_session_title(session_id: str, title: str) -> None:
    """Rename a chat session.

    Args:
        session_id: UUID of the session.
        title: New title.
    """
    now = _now_iso()
    with _get_connection() as conn:
        conn.execute(
            "UPDATE chat_sessions SET title = ?, updated_at = ? WHERE id = ?;",
            (title, now, session_id),
        )
        conn.commit()


def update_chat_session_timestamp(session_id: str) -> None:
    """Touch the updated_at timestamp of a session (e.g. after a new message).

    Args:
        session_id: UUID of the session.
    """
    now = _now_iso()
    with _get_connection() as conn:
        conn.execute(
            "UPDATE chat_sessions SET updated_at = ? WHERE id = ?;",
            (now, session_id),
        )
        conn.commit()


def delete_chat_session(session_id: str) -> None:
    """Delete a chat session and all its messages (via CASCADE).

    Args:
        session_id: UUID of the session to delete.
    """
    with _get_connection() as conn:
        conn.execute("DELETE FROM chat_sessions WHERE id = ?;", (session_id,))
        conn.commit()


# ---------------------------------------------------------------------------
# Chat history (messages)
# ---------------------------------------------------------------------------

def insert_chat_message(
    msg_id: str,
    message: str,
    role: str,
    session_id: str,
    context_doc_ids: list[str] | None = None,
) -> None:
    """Insert a new chat history entry.

    Args:
        msg_id: UUID for the message.
        message: Text of the message.
        role: Either 'user' or 'assistant'.
        session_id: UUID of the parent chat session.
        context_doc_ids: Optional list of document UUIDs used as context.
    """
    now = _now_iso()
    ctx_json = json.dumps(context_doc_ids, ensure_ascii=False) if context_doc_ids else None
    with _get_connection() as conn:
        conn.execute(
            """
            INSERT INTO chat_history (id, session_id, message, role, context_doc_ids, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            (msg_id, session_id, message, role, ctx_json, now),
        )
        conn.commit()


def _parse_chat_row(row: sqlite3.Row) -> dict[str, Any]:
    """Convert a chat_history row to a dict, deserialising context_doc_ids."""
    d = dict(row)
    if d.get("context_doc_ids") is not None:
        try:
            d["context_doc_ids"] = json.loads(d["context_doc_ids"])
        except (json.JSONDecodeError, TypeError):
            d["context_doc_ids"] = []
    return d


def get_chat_history(
    session_id: str,
    limit: int = 50,
    offset: int = 0,
) -> list[dict[str, Any]]:
    """Return chat messages for a session, ordered by creation time descending.

    Args:
        session_id: UUID of the session to retrieve messages for.
        limit: Maximum number of messages to return.
        offset: Pagination offset.

    Returns:
        List of chat message dicts (newest first).
    """
    with _get_connection() as conn:
        rows = conn.execute(
            """
            SELECT * FROM chat_history
            WHERE session_id = ?
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?;
            """,
            (session_id, limit, offset),
        ).fetchall()

    return [_parse_chat_row(row) for row in rows]


def get_session_messages_for_llm(
    session_id: str,
    limit: int = 20,
) -> list[dict[str, str]]:
    """Return the most recent messages for a session in chronological order.

    Used to build the multi-turn conversation context sent to the LLM.
    Returns dicts with 'role' and 'content' keys (OpenAI message format).

    Args:
        session_id: UUID of the session.
        limit: Maximum number of messages to include.

    Returns:
        List of ``{role, content}`` dicts in chronological order (oldest first).
    """
    with _get_connection() as conn:
        rows = conn.execute(
            """
            SELECT role, message FROM chat_history
            WHERE session_id = ?
            ORDER BY created_at DESC
            LIMIT ?;
            """,
            (session_id, limit),
        ).fetchall()

    # Reverse to get chronological order (oldest → newest)
    messages = [{"role": row["role"], "content": row["message"]} for row in reversed(rows)]
    return messages


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------

def get_stats() -> dict[str, Any]:
    """Return aggregate statistics about the document collection.

    Returns:
        Dict with keys: total_documents, count_by_type, count_by_month,
        recent_documents, expiring_soon_count, overdue_count.
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    in_30_days = (datetime.now(timezone.utc) + timedelta(days=30)).strftime("%Y-%m-%d")

    with _get_connection() as conn:
        # Total count
        total = conn.execute("SELECT COUNT(*) AS cnt FROM documents;").fetchone()["cnt"]

        # Count by type
        type_rows = conn.execute(
            """
            SELECT doc_type, COUNT(*) AS cnt
            FROM documents
            WHERE doc_type IS NOT NULL
            GROUP BY doc_type
            ORDER BY cnt DESC;
            """
        ).fetchall()
        count_by_type: dict[str, int] = {row["doc_type"]: row["cnt"] for row in type_rows}

        # Count by month (YYYY-MM from created_at)
        month_rows = conn.execute(
            """
            SELECT SUBSTR(created_at, 1, 7) AS month, COUNT(*) AS cnt
            FROM documents
            GROUP BY month
            ORDER BY month DESC;
            """
        ).fetchall()
        count_by_month: dict[str, int] = {row["month"]: row["cnt"] for row in month_rows}

        # Recent documents (last 10)
        recent_rows = conn.execute(
            "SELECT * FROM documents ORDER BY created_at DESC LIMIT 10;"
        ).fetchall()
        recent_documents = [_row_to_dict(row) for row in recent_rows]

        # Expiring soon: documents with date_expiration between today and +30 days
        expiring_soon = conn.execute(
            """
            SELECT COUNT(*) AS cnt FROM documents
            WHERE date_expiration IS NOT NULL
              AND date_expiration >= ?
              AND date_expiration <= ?
              AND status = 'ready';
            """,
            (today, in_30_days),
        ).fetchone()["cnt"]

        # Overdue: documents with date_expiration before today
        overdue = conn.execute(
            """
            SELECT COUNT(*) AS cnt FROM documents
            WHERE date_expiration IS NOT NULL
              AND date_expiration < ?
              AND status = 'ready';
            """,
            (today,),
        ).fetchone()["cnt"]

    return {
        "total_documents": total,
        "count_by_type": count_by_type,
        "count_by_month": count_by_month,
        "recent_documents": recent_documents,
        "expiring_soon_count": expiring_soon,
        "overdue_count": overdue,
    }


# ---------------------------------------------------------------------------
# Dismissed alerts
# ---------------------------------------------------------------------------


def dismiss_alert(doc_id: str, alert_type: str) -> None:
    """Dismiss an alert for a document.

    Args:
        doc_id: UUID of the document.
        alert_type: 'expiration' or 'echeance'.
    """
    import uuid as _uuid
    now = _now_iso()
    with _get_connection() as conn:
        conn.execute(
            """
            INSERT OR REPLACE INTO dismissed_alerts (id, doc_id, alert_type, dismissed_at)
            VALUES (?, ?, ?, ?);
            """,
            (str(_uuid.uuid4()), doc_id, alert_type, now),
        )
        conn.commit()


def undismiss_alert(doc_id: str, alert_type: str) -> None:
    """Re-enable a previously dismissed alert.

    Args:
        doc_id: UUID of the document.
        alert_type: 'expiration' or 'echeance'.
    """
    with _get_connection() as conn:
        conn.execute(
            "DELETE FROM dismissed_alerts WHERE doc_id = ? AND alert_type = ?;",
            (doc_id, alert_type),
        )
        conn.commit()


def get_dismissed_alert_keys() -> set[tuple[str, str]]:
    """Return a set of ``(doc_id, alert_type)`` tuples for all dismissed alerts."""
    with _get_connection() as conn:
        rows = conn.execute("SELECT doc_id, alert_type FROM dismissed_alerts;").fetchall()
    return {(row["doc_id"], row["alert_type"]) for row in rows}


# ---------------------------------------------------------------------------
# Alert queries
# ---------------------------------------------------------------------------


def get_expiring_documents(days_ahead: int = 90, limit: int = 50) -> list[dict]:
    """Return documents whose ``date_expiration`` falls within *days_ahead*.

    Results are ordered by expiration date ascending (soonest first).
    Includes already-overdue documents (negative days remaining).
    """
    cutoff = (
        datetime.now(timezone.utc) + timedelta(days=days_ahead)
    ).strftime("%Y-%m-%d")

    with _get_connection() as conn:
        rows = conn.execute(
            """
            SELECT * FROM documents
            WHERE date_expiration IS NOT NULL
              AND date_expiration <= ?
              AND status = 'ready'
            ORDER BY date_expiration ASC
            LIMIT ?;
            """,
            (cutoff, limit),
        ).fetchall()
    return [_row_to_dict(row) for row in rows]


def get_upcoming_echeances(days_ahead: int = 90, limit: int = 50) -> list[dict]:
    """Return documents whose ``date_echeance`` falls within *days_ahead*.

    Results are ordered by due date ascending (soonest first).
    Includes already-overdue payments.
    """
    cutoff = (
        datetime.now(timezone.utc) + timedelta(days=days_ahead)
    ).strftime("%Y-%m-%d")

    with _get_connection() as conn:
        rows = conn.execute(
            """
            SELECT * FROM documents
            WHERE date_echeance IS NOT NULL
              AND date_echeance <= ?
              AND status = 'ready'
            ORDER BY date_echeance ASC
            LIMIT ?;
            """,
            (cutoff, limit),
        ).fetchall()
    return [_row_to_dict(row) for row in rows]


def get_documents_for_gap_detection(doc_type: str, limit: int = 200) -> list[dict]:
    """Return documents of a given type, ordered by date, for gap analysis.

    Args:
        doc_type: Document type to query (e.g. 'fiche_de_paie').
        limit: Maximum rows to return.

    Returns:
        List of document dicts ordered by ``doc_date`` ascending.
    """
    with _get_connection() as conn:
        rows = conn.execute(
            """
            SELECT * FROM documents
            WHERE doc_type = ?
              AND doc_date IS NOT NULL
              AND status = 'ready'
            ORDER BY doc_date ASC
            LIMIT ?;
            """,
            (doc_type, limit),
        ).fetchall()
    return [_row_to_dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Procedures CRUD
# ---------------------------------------------------------------------------

def insert_procedure(
    proc_id: str,
    name: str,
    procedure_type: str,
    description: str | None,
    required_documents: list[dict],
    remarks: str | None,
) -> None:
    """Insert a new procedure record.

    Args:
        proc_id: UUID string for the procedure.
        name: Short descriptive name.
        procedure_type: Category (administrative, contrat, bancaire, etc.).
        description: Summary description.
        required_documents: List of required document dicts.
        remarks: Additional user remarks.
    """
    now = _now_iso()
    req_docs_json = json.dumps(required_documents, ensure_ascii=False)
    with _get_connection() as conn:
        conn.execute(
            """
            INSERT INTO procedures (id, name, procedure_type, description,
                                    required_documents, remarks, status,
                                    created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?);
            """,
            (proc_id, name, procedure_type, description,
             req_docs_json, remarks, now, now),
        )
        conn.commit()


def get_procedure(proc_id: str) -> dict[str, Any] | None:
    """Retrieve a single procedure by its UUID.

    Args:
        proc_id: UUID of the procedure.

    Returns:
        Procedure as a dict with all columns, or None if not found.
    """
    with _get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM procedures WHERE id = ?;",
            (proc_id,),
        ).fetchone()
    if row is None:
        return None
    d = dict(row)
    # Deserialize required_documents from JSON
    if d.get("required_documents") is not None:
        try:
            d["required_documents"] = json.loads(d["required_documents"])
        except (json.JSONDecodeError, TypeError):
            d["required_documents"] = []
    return d


def list_procedures(
    limit: int = 50,
    offset: int = 0,
) -> list[dict[str, Any]]:
    """Return a paginated list of procedures ordered by creation date.

    Args:
        limit: Maximum number of results.
        offset: Pagination offset.

    Returns:
        List of procedure dicts.
    """
    with _get_connection() as conn:
        rows = conn.execute(
            "SELECT * FROM procedures ORDER BY created_at DESC LIMIT ? OFFSET ?;",
            (limit, offset),
        ).fetchall()
    results: list[dict[str, Any]] = []
    for row in rows:
        d = dict(row)
        if d.get("required_documents") is not None:
            try:
                d["required_documents"] = json.loads(d["required_documents"])
            except (json.JSONDecodeError, TypeError):
                d["required_documents"] = []
        results.append(d)
    return results


def count_procedures() -> int:
    """Return the total number of procedures."""
    with _get_connection() as conn:
        row = conn.execute("SELECT COUNT(*) AS cnt FROM procedures;").fetchone()
    return row["cnt"] if row else 0


def delete_procedure(proc_id: str) -> None:
    """Delete a procedure and its executions (cascade).

    Args:
        proc_id: UUID of the procedure to delete.
    """
    with _get_connection() as conn:
        conn.execute("DELETE FROM procedures WHERE id = ?;", (proc_id,))
        conn.commit()


def update_procedure(
    proc_id: str,
    name: str | None = None,
    procedure_type: str | None = None,
    description: str | None = None,
    required_documents: list[dict] | None = None,
    remarks: str | None = None,
) -> None:
    """Update an existing procedure record (partial update).

    Only non-None fields are updated.  ``updated_at`` is always refreshed.

    Args:
        proc_id: UUID of the procedure.
        name: New name (optional).
        procedure_type: New type (optional).
        description: New description (optional).
        required_documents: New required documents list (optional).
        remarks: New remarks (optional).
    """
    fields: list[str] = []
    values: list[Any] = []

    if name is not None:
        fields.append("name = ?")
        values.append(name)
    if procedure_type is not None:
        fields.append("procedure_type = ?")
        values.append(procedure_type)
    if description is not None:
        fields.append("description = ?")
        values.append(description)
    if required_documents is not None:
        fields.append("required_documents = ?")
        values.append(json.dumps(required_documents, ensure_ascii=False))
    if remarks is not None:
        fields.append("remarks = ?")
        values.append(remarks)

    # Always update the timestamp
    fields.append("updated_at = ?")
    values.append(_now_iso())

    values.append(proc_id)

    with _get_connection() as conn:
        conn.execute(
            f"UPDATE procedures SET {', '.join(fields)} WHERE id = ?;",
            tuple(values),
        )
        conn.commit()


# ---------------------------------------------------------------------------
# Procedure Executions
# ---------------------------------------------------------------------------

def insert_procedure_execution(
    exec_id: str,
    procedure_id: str,
    person_name: str,
    matched_documents: list[dict],
    status: str = "completed",
) -> None:
    """Insert a procedure execution record.

    Args:
        exec_id: UUID for the execution.
        procedure_id: UUID of the parent procedure.
        person_name: Name of the person searched for.
        matched_documents: List of match result dicts.
        status: Execution status.
    """
    now = _now_iso()
    matched_json = json.dumps(matched_documents, ensure_ascii=False)
    with _get_connection() as conn:
        conn.execute(
            """
            INSERT INTO procedure_executions (id, procedure_id, person_name,
                                              matched_documents, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            (exec_id, procedure_id, person_name, matched_json, status, now),
        )
        conn.commit()


def get_procedure_execution(exec_id: str) -> dict[str, Any] | None:
    """Retrieve a single procedure execution by its UUID.

    Args:
        exec_id: UUID of the execution.

    Returns:
        Execution dict, or None if not found.
    """
    with _get_connection() as conn:
        row = conn.execute(
            "SELECT * FROM procedure_executions WHERE id = ?;",
            (exec_id,),
        ).fetchone()
    if row is None:
        return None
    d = dict(row)
    if d.get("matched_documents") is not None:
        try:
            d["matched_documents"] = json.loads(d["matched_documents"])
        except (json.JSONDecodeError, TypeError):
            d["matched_documents"] = []
    return d


def search_documents_by_type_and_name(
    doc_type: str,
    person_name: str,
    limit: int = 10,
) -> list[dict[str, Any]]:
    """Search documents matching a type and containing a person's name.

    Searches for the person's name in destinataire, emetteur, title,
    filename, text_content and resume fields. Results are ordered by
    doc_date descending (most recent first), then by created_at.

    Args:
        doc_type: The document type to filter on.
        person_name: Person's name to search for in document fields.
        limit: Maximum results.

    Returns:
        List of matching document dicts.
    """
    # Build LIKE pattern for name matching
    name_pattern = f"%{person_name}%"
    with _get_connection() as conn:
        rows = conn.execute(
            """
            SELECT * FROM documents
            WHERE doc_type = ?
              AND status = 'ready'
              AND (
                  destinataire LIKE ? COLLATE NOCASE
                  OR emetteur LIKE ? COLLATE NOCASE
                  OR title LIKE ? COLLATE NOCASE
                  OR filename LIKE ? COLLATE NOCASE
                  OR text_content LIKE ? COLLATE NOCASE
                  OR resume LIKE ? COLLATE NOCASE
              )
            ORDER BY doc_date DESC, created_at DESC
            LIMIT ?;
            """,
            (doc_type, name_pattern, name_pattern, name_pattern,
             name_pattern, name_pattern, name_pattern, limit),
        ).fetchall()
    return [_row_to_dict(row) for row in rows]
