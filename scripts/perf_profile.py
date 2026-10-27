#!/usr/bin/env python3
"""Micro-benchmarks for the DocuMind backend.

Run from a checkout with the application dependencies installed:

    python scripts/profile.py imports
    python scripts/profile.py db --docs 1000

The script prints JSON so results from two checkouts (before/after) can be
compared without ever including document content.
"""

from __future__ import annotations

import argparse
import json
import os
import resource
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path


def _rss_mb() -> float:
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0


def _measure_import(module: str) -> dict:
    code = (
        "import time,resource,json,sys;"
        f"t=time.perf_counter();import {module};"
        "dt=time.perf_counter()-t;"
        "rss=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1024.0;"
        "print(json.dumps({'module':sys.argv[1],'seconds':dt,'rss_mb':rss}))"
    )
    out = subprocess.run(
        [sys.executable, "-c", code, module],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(out.stdout.strip().splitlines()[-1])


def profile_imports() -> dict:
    results = []
    for module in ("config", "database", "ocr", "embeddings", "pipeline", "main"):
        try:
            results.append(_measure_import(module))
        except subprocess.CalledProcessError as exc:
            results.append({"module": module, "error": (exc.stderr or "").strip()[-500:]})
    return {"kind": "imports", "results": results}


def _seed(database, count: int) -> None:
    text = (
        "Facture d électricité émise par un fournisseur. "
        "Montant total à payer avant échéance. Référence client et contrat. "
    ) * 12
    for i in range(count):
        doc_id = str(uuid.uuid4())
        database.insert_document(doc_id, f"doc-{i}.pdf", f"/tmp/doc-{i}.pdf")
        database.update_document_text(doc_id, text)
        database.update_document_metadata(
            doc_id,
            doc_type=["facture", "fiche_de_paie", "contrat", "courrier"][i % 4],
            emetteur=f"Emetteur {i % 20}",
            doc_date=f"2024-{i % 12 + 1:02d}-15",
            montant=float(i),
            reference=f"REF{i}",
            destinataire="Alex",
            resume="Document de test synthétique",
            tags=["test", "facture"],
            title=f"Document {i}",
        )
        database.update_document_embedding(doc_id, b"\x00" * 1536)


def _timeit(fn, iterations: int) -> dict:
    samples = []
    for _ in range(iterations):
        start = time.perf_counter()
        fn()
        samples.append((time.perf_counter() - start) * 1000.0)
    samples.sort()
    return {
        "median_ms": round(statistics.median(samples), 2),
        "p95_ms": round(samples[int(len(samples) * 0.95) - 1], 2),
        "mean_ms": round(statistics.mean(samples), 2),
    }


def profile_startup() -> dict:
    """Replicate the historical startup path (DB init + eager embedding load)."""
    import database
    from embeddings import load_embedding_model

    result = {"kind": "startup", "steps": {}}

    start = time.perf_counter()
    database.init_db()
    result["steps"]["init_db_ms"] = round((time.perf_counter() - start) * 1000.0, 2)

    start = time.perf_counter()
    model = load_embedding_model()
    result["steps"]["embedding_startup_ms"] = round((time.perf_counter() - start) * 1000.0, 2)
    result["steps"]["lazy_proxy"] = not getattr(model, "loaded", True)
    result["steps"]["rss_after_startup_mb"] = round(_rss_mb(), 1)

    # First real use (search / first processed document). For an eager model
    # this is a no-op; for the lazy proxy this is where weights are allocated.
    start = time.perf_counter()
    dim = model.get_sentence_embedding_dimension()
    result["steps"]["first_use_ms"] = round((time.perf_counter() - start) * 1000.0, 2)
    result["steps"]["embedding_dim"] = int(dim)
    result["steps"]["rss_after_first_use_mb"] = round(_rss_mb(), 1)
    return result


def profile_db(docs: int, iterations: int) -> dict:
    import database

    start = time.perf_counter()
    database.init_db()
    init_first_ms = (time.perf_counter() - start) * 1000.0

    _seed(database, docs)

    start = time.perf_counter()
    database.init_db()
    init_second_ms = (time.perf_counter() - start) * 1000.0

    one = database.list_documents(limit=1)[0]["id"]
    benchmarks = {
        "list_limit_50": _timeit(lambda: database.list_documents(limit=50), iterations),
        "list_type_filter": _timeit(
            lambda: database.list_documents(doc_type="facture", limit=50), iterations
        ),
        "count_all": _timeit(database.count_documents, iterations),
        "fts_search": _timeit(lambda: database.search_fts("électricité", limit=20), iterations),
        "get_document": _timeit(lambda: database.get_document(one), iterations),
        "get_stats": _timeit(database.get_stats, max(5, iterations // 5)),
        "get_all_embeddings": _timeit(
            database.get_all_embeddings, max(5, iterations // 5)
        ),
    }
    return {
        "kind": "db",
        "docs": docs,
        "init_first_ms": round(init_first_ms, 2),
        "init_second_ms": round(init_second_ms, 2),
        "rss_mb": round(_rss_mb(), 1),
        "benchmarks": benchmarks,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["imports", "db", "startup"])
    parser.add_argument("--docs", type=int, default=1000)
    parser.add_argument("--iterations", type=int, default=100)
    args = parser.parse_args()

    if args.mode == "imports":
        result = profile_imports()
    elif args.mode == "startup":
        result = profile_startup()
    else:
        tmp = tempfile.mkdtemp(prefix="documind-profile-")
        os.environ["DOCUMIND_DATA_DIR"] = tmp
        os.environ.setdefault("EMBEDDING_LAZY_LOAD", "1")
        try:
            result = profile_db(args.docs, args.iterations)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
