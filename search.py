"""Hybrid search combining FTS5 full-text and semantic similarity."""

import logging
import numpy as np
from typing import Optional

from database import search_fts, get_all_embeddings, get_document
from embeddings import generate_embedding, semantic_search, deserialize_embedding
from config import FTS_WEIGHT, SEMANTIC_WEIGHT, DEFAULT_SEARCH_TOP_K

logger = logging.getLogger(__name__)


def load_embeddings_cache() -> list[tuple[str, np.ndarray]]:
    """Load all document embeddings from the database into memory.

    Reads every ``(doc_id, embedding_blob)`` pair from the database and
    deserializes the binary blobs into numpy vectors for fast in-memory
    semantic search.

    Returns:
        List of ``(doc_id, numpy_vector)`` tuples.
    """
    raw_pairs = get_all_embeddings()
    cache: list[tuple[str, np.ndarray]] = []
    for doc_id, blob in raw_pairs:
        try:
            vector = deserialize_embedding(blob)
            cache.append((doc_id, vector))
        except Exception:
            logger.warning("Failed to deserialize embedding for doc %s — skipping", doc_id)
    logger.info("Embeddings cache loaded: %d documents", len(cache))
    return cache


def refresh_embeddings_cache(
    cache: list[tuple[str, np.ndarray]],
) -> list[tuple[str, np.ndarray]]:
    """Rebuild the embeddings cache from the database.

    Called after a new document is processed or a document is deleted so
    that the in-memory cache stays in sync with persistent storage.

    Args:
        cache: The current (now stale) cache — ignored, kept for API
            symmetry.

    Returns:
        A freshly loaded list of ``(doc_id, numpy_vector)`` tuples.
    """
    return load_embeddings_cache()


def _normalize_scores(scores: dict[str, float]) -> dict[str, float]:
    """Normalize a dict of raw scores to the ``[0, 1]`` range.

    Uses min–max normalization.  When all values are identical every
    entry receives a score of ``1.0``.

    Args:
        scores: Mapping of ``doc_id`` → raw score.

    Returns:
        Mapping of ``doc_id`` → normalized score in ``[0, 1]``.
    """
    if not scores:
        return {}

    values = list(scores.values())
    min_val = min(values)
    max_val = max(values)

    if max_val == min_val:
        return {doc_id: 1.0 for doc_id in scores}

    return {
        doc_id: (score - min_val) / (max_val - min_val)
        for doc_id, score in scores.items()
    }


def hybrid_search(
    query: str,
    embedding_model,
    embeddings_cache: list[tuple[str, np.ndarray]],
    top_k: int = DEFAULT_SEARCH_TOP_K,
) -> list[dict]:
    """Run a hybrid search combining FTS5 full-text and semantic similarity.

    The algorithm works in four stages:

    1. **FTS5 search** — lexical matching via SQLite FTS5.
    2. **Semantic search** — cosine-similarity over dense embeddings.
    3. **Score normalization** — both score sets are independently mapped
       to ``[0, 1]`` using min–max normalization.
    4. **Score fusion** — a weighted linear combination produces the
       final ranking (weights from ``config.FTS_WEIGHT`` /
       ``config.SEMANTIC_WEIGHT``).

    Args:
        query: User search query string.
        embedding_model: Loaded ``SentenceTransformer`` instance.
        embeddings_cache: In-memory list of ``(doc_id, vector)`` tuples.
        top_k: Maximum number of results to return.

    Returns:
        List of dicts, each containing ``document`` (full document dict),
        ``score`` (fused relevance score), and ``match_type``
        (``"fts"``, ``"semantic"``, or ``"hybrid"``).
    """
    # ------------------------------------------------------------------
    # 1. FTS5 search
    # ------------------------------------------------------------------
    fts_scores: dict[str, float] = {}
    try:
        fts_results = search_fts(query, limit=top_k)
        for row in fts_results:
            doc_id = row["id"]
            # FTS5 rank is negative (lower = better); use abs so higher = better
            fts_scores[doc_id] = abs(row.get("rank", 0.0))
    except Exception:
        logger.warning("FTS5 search failed for query '%s' — continuing with semantic only", query)

    # ------------------------------------------------------------------
    # 2. Semantic search
    # ------------------------------------------------------------------
    semantic_scores: dict[str, float] = {}
    try:
        if embedding_model is not None and embeddings_cache:
            query_embedding = generate_embedding(embedding_model, query)
            sem_results = semantic_search(query_embedding, embeddings_cache, top_k=top_k)
            for doc_id, score in sem_results:
                semantic_scores[doc_id] = score
    except Exception:
        logger.warning("Semantic search failed for query '%s' — continuing with FTS only", query)

    # ------------------------------------------------------------------
    # 3. Normalize both score sets
    # ------------------------------------------------------------------
    fts_normalized = _normalize_scores(fts_scores)
    semantic_normalized = _normalize_scores(semantic_scores)

    # ------------------------------------------------------------------
    # 4. Score fusion
    # ------------------------------------------------------------------
    all_doc_ids = set(fts_normalized.keys()) | set(semantic_normalized.keys())

    fused: list[dict] = []
    for doc_id in all_doc_ids:
        fts_val = fts_normalized.get(doc_id, 0.0)
        sem_val = semantic_normalized.get(doc_id, 0.0)
        final_score = FTS_WEIGHT * fts_val + SEMANTIC_WEIGHT * sem_val

        # Determine match type
        in_fts = doc_id in fts_normalized
        in_sem = doc_id in semantic_normalized
        if in_fts and in_sem:
            match_type = "hybrid"
        elif in_fts:
            match_type = "fts"
        else:
            match_type = "semantic"

        fused.append({
            "doc_id": doc_id,
            "score": final_score,
            "match_type": match_type,
        })

    # Sort by score descending
    fused.sort(key=lambda x: x["score"], reverse=True)

    # ------------------------------------------------------------------
    # 5. Fetch full documents and build response
    # ------------------------------------------------------------------
    results: list[dict] = []
    for item in fused[:top_k]:
        doc = get_document(item["doc_id"])
        if doc is None:
            # Document deleted between search and fetch — skip
            continue
        results.append({
            "document": doc,
            "score": item["score"],
            "match_type": item["match_type"],
        })

    logger.info(
        "Hybrid search for '%s': %d FTS hits, %d semantic hits, %d fused results returned",
        query, len(fts_scores), len(semantic_scores), len(results),
    )
    return results
