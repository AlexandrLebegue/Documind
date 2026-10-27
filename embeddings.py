"""Embedding module: sentence-transformers for document vectorization and similarity search."""

import logging
import threading

import numpy as np

from config import (
    EMBEDDING_MODEL_NAME,
    EMBEDDING_CACHE_DIR,
    EMBEDDING_LAZY_LOAD,
)

logger = logging.getLogger(__name__)

# Text is truncated before encoding to stay within reasonable model input
_MAX_TEXT_CHARS = 5000


class LazyEmbeddingModel:
    """Proxy that loads the sentence-transformer model on first use.

    Loading ``all-MiniLM-L6-v2`` costs ~1 GB of RSS and several seconds.
    Most idle instances never need it, so startup should not pay that cost.
    The proxy is thread-safe and otherwise behaves like the real model for
    the two methods the app uses (``encode`` and
    ``get_sentence_embedding_dimension``).
    """

    def __init__(self, model_name: str, cache_dir: str) -> None:
        self.model_name = model_name
        self.cache_dir = cache_dir
        self._model = None
        self._lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self._model is not None

    def _ensure(self):
        if self._model is not None:
            return self._model
        with self._lock:
            if self._model is None:
                from sentence_transformers import SentenceTransformer

                logger.info("Loading embedding model lazily: %s", self.model_name)
                self._model = SentenceTransformer(
                    self.model_name, cache_folder=self.cache_dir
                )
                logger.info(
                    "Embedding model loaded: %s (dimension=%d)",
                    self.model_name,
                    self._model.get_sentence_embedding_dimension(),
                )
        return self._model

    def encode(self, *args, **kwargs):
        return self._ensure().encode(*args, **kwargs)

    def get_sentence_embedding_dimension(self):
        return self._ensure().get_sentence_embedding_dimension()


def load_embedding_model(
    model_name: str = EMBEDDING_MODEL_NAME,
    cache_dir: str = EMBEDDING_CACHE_DIR,
    lazy: bool = EMBEDDING_LAZY_LOAD,
):
    """Load (or defer loading of) a sentence-transformer embedding model.

    Args:
        model_name: HuggingFace model identifier or local path.
        cache_dir: Directory to cache downloaded model files.
        lazy: When true, return a :class:`LazyEmbeddingModel` that only
            imports torch/sentence-transformers and allocates weights on
            first use.

    Returns:
        A loaded model or a lazy proxy exposing the same API.
    """
    if lazy:
        logger.info("Embedding model configured for lazy loading: %s", model_name)
        return LazyEmbeddingModel(model_name, cache_dir)

    from sentence_transformers import SentenceTransformer

    model = SentenceTransformer(model_name, cache_folder=cache_dir)
    dim = model.get_sentence_embedding_dimension()
    logger.info(
        "Embedding model loaded: %s (dimension=%d, cache=%s)",
        model_name, dim, cache_dir,
    )
    return model


def generate_embedding(model, text: str) -> np.ndarray:
    """Generate a dense embedding vector for a text string.

    The input text is truncated to the first 5 000 characters before
    encoding to keep memory usage predictable.

    Args:
        model: Loaded :class:`SentenceTransformer` instance.
        text: Input text to embed.

    Returns:
        1-D ``float32`` numpy array representing the text embedding.
    """
    truncated = text[:_MAX_TEXT_CHARS]
    vector = model.encode(truncated, show_progress_bar=False)
    return np.asarray(vector, dtype=np.float32)


def cosine_similarity(vec_a: np.ndarray, vec_b: np.ndarray) -> float:
    """Compute cosine similarity between two vectors.

    Args:
        vec_a: First embedding vector (1-D).
        vec_b: Second embedding vector (1-D).

    Returns:
        Cosine similarity score in ``[-1, 1]``.  Returns ``0.0`` if
        either vector has zero norm.
    """
    norm_a = np.linalg.norm(vec_a)
    norm_b = np.linalg.norm(vec_b)

    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0

    return float(np.dot(vec_a, vec_b) / (norm_a * norm_b))


def batch_cosine_similarity(
    query_vec: np.ndarray,
    doc_vectors: np.ndarray,
) -> np.ndarray:
    """Compute cosine similarity of a query vector against multiple document vectors.

    Uses vectorised numpy operations for efficiency.

    Args:
        query_vec: 1-D query embedding.
        doc_vectors: 2-D array of shape ``(N, dim)`` containing document embeddings.

    Returns:
        1-D array of *N* similarity scores.
    """
    # Norms for each document vector (row-wise)
    query_norm = np.linalg.norm(query_vec)
    doc_norms = np.linalg.norm(doc_vectors, axis=1)

    # Avoid division by zero
    safe_denom = query_norm * doc_norms
    safe_denom = np.where(safe_denom == 0.0, 1.0, safe_denom)

    dot_products = doc_vectors @ query_vec
    similarities = dot_products / safe_denom

    return similarities.astype(np.float64)


def semantic_search(
    query_embedding: np.ndarray,
    doc_embeddings: list[tuple[str, np.ndarray]],
    top_k: int = 20,
) -> list[tuple[str, float]]:
    """Retrieve the top-K most similar documents by cosine similarity.

    Args:
        query_embedding: 1-D query embedding vector.
        doc_embeddings: List of ``(doc_id, embedding_vector)`` tuples.
        top_k: Number of results to return.

    Returns:
        List of ``(doc_id, score)`` tuples sorted by descending similarity.
    """
    if not doc_embeddings:
        return []

    doc_ids = [doc_id for doc_id, _ in doc_embeddings]
    vectors = np.stack([vec for _, vec in doc_embeddings])

    scores = batch_cosine_similarity(query_embedding, vectors)

    # Sort indices by score descending
    sorted_indices = np.argsort(scores)[::-1][:top_k]

    results = [(doc_ids[i], float(scores[i])) for i in sorted_indices]
    return results


def serialize_embedding(vector: np.ndarray) -> bytes:
    """Serialize an embedding vector to raw bytes for database storage.

    Args:
        vector: 1-D numpy array to serialize.

    Returns:
        Byte representation of the ``float32`` vector.
    """
    return vector.astype(np.float32).tobytes()


def deserialize_embedding(blob: bytes) -> np.ndarray:
    """Deserialize a byte blob back into a numpy embedding vector.

    Args:
        blob: Byte representation produced by :func:`serialize_embedding`.

    Returns:
        1-D ``float32`` numpy array.
    """
    return np.frombuffer(blob, dtype=np.float32)
