"""Documind command-line client.

Talks to the local HTTP API only (standard library, no heavy dependencies) so
it can run on the same small LXC as the service.
"""

from __future__ import annotations

import argparse
import csv
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

DEFAULT_URL = os.environ.get("DOCUMIND_URL", "http://127.0.0.1:8000")
SUPPORTED_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png", ".tiff", ".webp"}
TERMINAL_STATUSES = {"ready", "error", "segmented"}


class ApiError(RuntimeError):
    pass


def _request(method: str, path: str, *, payload=None, files=None, timeout=120):
    url = path if path.startswith("http") else DEFAULT_URL.rstrip("/") + path
    headers = {"Accept": "application/json"}
    body = None
    if files is not None:
        boundary = uuid.uuid4().hex
        chunks: list[bytes] = []
        for field, (filename, content) in files.items():
            mime = mimetypes.guess_type(filename)[0] or "application/octet-stream"
            chunks.append(f"--{boundary}\r\n".encode())
            chunks.append(
                f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'.encode()
            )
            chunks.append(f"Content-Type: {mime}\r\n\r\n".encode())
            chunks.append(content)
            chunks.append(b"\r\n")
        chunks.append(f"--{boundary}--\r\n".encode())
        body = b"".join(chunks)
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif payload is not None:
        body = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        try:
            detail = json.loads(detail).get("detail", detail)
        except Exception:
            pass
        raise ApiError(f"HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise ApiError(f"Cannot reach {url}: {exc.reason}") from exc
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw.decode("utf-8", "replace")


def _get(path: str, timeout=120):
    return _request("GET", path, timeout=timeout)


def _post(path: str, payload=None, timeout=600):
    return _request("POST", path, payload=payload, timeout=timeout)


def _delete(path: str, timeout=120):
    return _request("DELETE", path, timeout=timeout)


def _expand_paths(paths: list[str]) -> tuple[list[Path], list[str]]:
    files: list[Path] = []
    skipped: list[str] = []
    for raw in paths:
        p = Path(raw).expanduser()
        if p.is_dir():
            for child in sorted(p.rglob("*")):
                if child.is_file():
                    if child.suffix.lower() in SUPPORTED_EXTENSIONS:
                        files.append(child)
                    else:
                        skipped.append(str(child))
        elif p.is_file():
            if p.suffix.lower() in SUPPORTED_EXTENSIONS:
                files.append(p)
            else:
                skipped.append(str(p))
        else:
            raise ApiError(f"Path not found: {raw}")
    return files, skipped


def upload_file(path: Path) -> dict:
    content = path.read_bytes()
    return _request(
        "POST",
        "/api/documents/upload",
        files={"file": (path.name, content)},
        timeout=600,
    )


def wait_for_document(doc_id: str, timeout: float = 3600, interval: float = 2.0) -> dict:
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        doc = _get(f"/api/documents/{doc_id}")
        last = doc
        if doc.get("status") == "error":
            return doc
        if doc.get("status") == "ready":
            return doc
        if doc.get("status") == "segmented" and doc.get("total_seconds") is not None:
            return doc
        time.sleep(interval)
    raise ApiError(f"Timed out waiting for document {doc_id} (last status={last and last.get('status')})")


def _parse_pages(text: str) -> list[dict]:
    if not text:
        return []
    parts = re.split(r"(?m)^--- Page (\d+) ---\s*$", text)
    if len(parts) < 3:
        return [{"page": 1, "text": text.strip()}]
    pages = []
    for i in range(1, len(parts) - 1, 2):
        pages.append({"page": int(parts[i]), "text": parts[i + 1].strip()})
    return pages


def _doc_summary(doc: dict) -> dict:
    keys = [
        "id", "filename", "title", "doc_type", "emetteur", "doc_date",
        "montant", "reference", "destinataire", "resume", "tags",
        "date_expiration", "date_echeance", "parent_id", "page_start",
        "page_end", "pages_done", "pages_total", "ocr_backend",
        "ocr_seconds", "llm_seconds", "total_seconds", "error_message",
        "status", "created_at", "updated_at",
    ]
    return {k: doc.get(k) for k in keys}


def _print_json(data) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def _human_list(docs: list[dict]) -> None:
    if not docs:
        print("Aucun document.")
        return
    print(f"{'ID':10} {'STATUT':11} {'TYPE':16} {'DATE':10} TITRE")
    for d in docs:
        print(
            f"{(d.get('id') or '')[:8]:10} {(d.get('status') or ''):11} "
            f"{(d.get('doc_type') or '-'):16} {(d.get('doc_date') or '-'):10} "
            f"{d.get('title') or d.get('filename') or ''}"
        )


def _human_doc(doc: dict, text: str | None = None, pages: list[dict] | None = None) -> None:
    for key in (
        "id", "filename", "title", "doc_type", "emetteur", "doc_date",
        "montant", "reference", "destinataire", "date_expiration",
        "date_echeance", "pages_done", "pages_total", "ocr_backend",
        "ocr_seconds", "llm_seconds", "total_seconds", "status",
        "error_message", "parent_id", "page_start", "page_end",
    ):
        value = doc.get(key)
        if value not in (None, "", []):
            print(f"{key:16} {value}")
    if doc.get("tags"):
        print(f"{'tags':16} {', '.join(doc['tags'])}")
    if doc.get("resume"):
        print(f"{'resume':16} {doc['resume']}")
    if text is not None:
        print("\n--- TEXTE ---")
        print(text)
    if pages is not None:
        print("\n--- PAGES ---")
        for page in pages:
            print(f"[page {page['page']}]")
            print(page["text"])
            print()


def cmd_upload(args) -> int:
    files, skipped = _expand_paths(args.paths)
    results = []
    for path in files:
        try:
            resp = upload_file(path)
            item = {"file": str(path), **resp}
            if args.wait and resp.get("id"):
                item["document"] = _doc_summary(wait_for_document(resp["id"]))
            results.append(item)
            print(f"uploaded {path} -> {resp.get('id')}", file=sys.stderr)
        except ApiError as exc:
            results.append({"file": str(path), "error": str(exc)})
            print(f"failed {path}: {exc}", file=sys.stderr)
    out = {"files": results, "count": len(files), "skipped": skipped}
    if args.human:
        for item in results:
            if "error" in item:
                print(f"ERREUR  {item['file']}: {item['error']}")
            else:
                doc = item.get("document") or {}
                suffix = f" [{doc.get('status')}]" if doc else ""
                print(f"{item.get('id', '')[:8]}  {item['file']}{suffix}")
        if skipped:
            print(f"{len(skipped)} fichier(s) ignoré(s) (extension non supportée)")
    else:
        _print_json(out)
    return 0 if all("error" not in item for item in results) else 1


def cmd_status(args) -> int:
    if args.doc_id:
        doc = _get(f"/api/documents/{args.doc_id}")
        segments = _get(f"/api/documents/{args.doc_id}/segments") if doc.get("status") == "segmented" else []
        if args.human:
            _human_doc(doc)
            if segments:
                print("\n--- SEGMENTS ---")
                _human_list(segments)
        else:
            _print_json({"document": _doc_summary(doc), "segments": [_doc_summary(s) for s in segments]})
        return 0
    health = _get("/api/health")
    system = _get("/api/system")
    queue = _get("/api/queue")
    if args.human:
        print(f"service        {health.get('status')} (version {health.get('version')})")
        print(f"llm            {'chargé' if health.get('llm_loaded') else 'non chargé'}")
        print(f"embeddings     {'chargés' if health.get('embedding_model_loaded') else 'non chargés'}")
        print(f"documents      {health.get('total_documents')}")
        print(f"rss / crête    {system.get('rss_mb')} Mo / {system.get('peak_rss_mb')} Mo")
        print(f"file           actif={queue.get('total_active', 0)} en attente={queue.get('total_pending', 0)}")
        if system.get("by_status"):
            print("statuts        " + ", ".join(f"{k}={v}" for k, v in sorted(system["by_status"].items())))
    else:
        _print_json({"health": health, "system": system, "queue": queue})
    return 0


def cmd_queue(args) -> int:
    data = _get("/api/queue")
    if args.human:
        active = data.get("active")
        print(f"actif: {active.get('label') if active else '-'}")
        print(f"en attente: {data.get('total_pending', 0)}")
        for item in data.get("pending", []):
            print(f"  {item.get('id', '')[:8]}  {item.get('label')}")
        for item in data.get("history", [])[:10]:
            print(f"  {item.get('status'):10} {item.get('label')} ({item.get('error') or 'ok'})")
    else:
        _print_json(data)
    return 0


def cmd_list(args) -> int:
    params = {"limit": args.limit, "offset": args.offset}
    if args.type:
        params["doc_type"] = args.type
    if args.since:
        params["date_from"] = args.since
    if args.q:
        params["q"] = args.q
    data = _get("/api/documents?" + urllib.parse.urlencode(params))
    if args.human:
        _human_list(data.get("documents", []))
        print(f"\n{data.get('total', 0)} document(s), affichés {data.get('offset', 0)}–{data.get('offset', 0) + len(data.get('documents', []))}")
    else:
        _print_json(data)
    return 0


def cmd_show(args) -> int:
    doc = _get(f"/api/documents/{args.doc_id}")
    text = None
    pages = None
    if args.text or args.pages:
        text = doc.get("text_content") or ""
    if args.pages:
        pages = _parse_pages(text or "")
    if args.human:
        _human_doc(doc, text=text if args.text and not args.pages else None, pages=pages)
    else:
        out = _doc_summary(doc)
        if args.text:
            out["text"] = text
        if args.pages:
            out["pages"] = pages
        _print_json(out)
    return 0


def cmd_search(args) -> int:
    data = _post("/api/search", {"query": args.query})
    if args.human:
        results = data.get("results", [])
        if not results:
            print("Aucun résultat.")
        for item in results:
            d = item.get("document", {})
            print(f"{item.get('score', 0):.3f}  {(d.get('id') or '')[:8]}  {d.get('doc_type') or '-'}  {d.get('title') or d.get('filename')}")
    else:
        _print_json(data)
    return 0


def cmd_ask(args) -> int:
    payload = {"message": args.question}
    if args.session:
        payload["session_id"] = args.session
    data = _post("/api/chat", payload, timeout=args.timeout)
    if args.human:
        print(data.get("reply", ""))
        if data.get("source_document_ids"):
            print("\nSources: " + ", ".join(data["source_document_ids"]))
    else:
        _print_json(data)
    return 0


def cmd_stats(args) -> int:
    data = _get("/api/stats")
    if args.human:
        print(f"documents: {data.get('total_documents')}")
        for key, value in sorted((data.get("count_by_type") or {}).items(), key=lambda kv: -kv[1]):
            print(f"  {key:20} {value}")
        print(f"expire <30j: {data.get('expiring_soon_count')}  en retard: {data.get('overdue_count')}")
    else:
        _print_json(data)
    return 0


def cmd_reprocess(args) -> int:
    data = _post(f"/api/documents/{args.doc_id}/reprocess", timeout=120)
    if args.wait:
        doc = wait_for_document(args.doc_id)
        data["document"] = _doc_summary(doc)
    if args.human:
        print(f"retraitement lancé pour {args.doc_id[:8]}")
        if args.wait:
            _human_doc(data["document"])
    else:
        _print_json(data)
    return 0


def cmd_delete(args) -> int:
    if not args.yes:
        if not sys.stdin.isatty():
            raise ApiError("Refus de supprimer sans --yes en mode non interactif")
        answer = input(f"Supprimer {args.doc_id} ? [y/N] ").strip().lower()
        if answer not in {"y", "yes", "o", "oui"}:
            print("Annulé.")
            return 1
    data = _delete(f"/api/documents/{args.doc_id}")
    if args.human:
        print(data.get("message", "supprimé"))
    else:
        _print_json(data)
    return 0


BENCH_FIELDS = [
    "file", "filename", "doc_id", "status", "pages", "documents",
    "ocr_seconds", "ocr_s_per_page", "llm_seconds", "wall_seconds",
    "rss_mb", "peak_rss_mb", "ocr_backend", "types", "titles", "error",
]


def _write_bench_csv(path: Path, rows: list[dict]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=BENCH_FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(tmp, path)


def _read_bench_csv(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8") as fh:
        return {row["file"]: row for row in csv.DictReader(fh) if row.get("file")}


def _bench_blank_row(path: Path) -> dict:
    return {
        "file": str(path),
        "filename": path.name,
        "doc_id": "",
        "status": "error",
        "pages": 0,
        "documents": 0,
        "ocr_seconds": "",
        "ocr_s_per_page": "",
        "llm_seconds": "",
        "wall_seconds": "",
        "rss_mb": "",
        "peak_rss_mb": "",
        "ocr_backend": "",
        "types": "",
        "titles": "",
        "error": "",
    }


def _bench_fill(row: dict, doc: dict, segments: list[dict], system: dict, wall: float) -> None:
    pages = doc.get("pages_total") or 0
    ocr_seconds = doc.get("ocr_seconds")
    llm_seconds = doc.get("llm_seconds")
    if llm_seconds is None and segments:
        llm_seconds = sum(s.get("llm_seconds") or 0 for s in segments)
    row.update(
        {
            "status": doc.get("status"),
            "pages": pages,
            "documents": len(segments) or 1,
            "ocr_seconds": round(ocr_seconds, 2) if ocr_seconds is not None else "",
            "ocr_s_per_page": round(ocr_seconds / pages, 2) if ocr_seconds and pages else "",
            "llm_seconds": round(llm_seconds, 2) if llm_seconds is not None else "",
            "wall_seconds": round(wall, 2),
            "rss_mb": system.get("rss_mb"),
            "peak_rss_mb": system.get("peak_rss_mb"),
            "ocr_backend": doc.get("ocr_backend") or "",
            "types": "|".join(sorted({(s.get("doc_type") or "-") for s in segments})) if segments else (doc.get("doc_type") or "-"),
            "titles": " | ".join((s.get("title") or s.get("filename") or "") for s in segments) if segments else (doc.get("title") or doc.get("filename") or ""),
            "error": doc.get("error_message") or "",
        }
    )


def _doc_is_queued(doc_id: str) -> bool:
    queue = _get("/api/queue")
    ids = set()
    active = queue.get("active")
    if active and active.get("id"):
        ids.add(active["id"])
    for item in queue.get("pending", []):
        if item.get("id"):
            ids.add(item["id"])
    return doc_id in ids


def _bench_process(path: Path, previous: dict | None, on_update=None) -> tuple[dict, dict]:
    row = dict(previous) if previous else _bench_blank_row(path)
    started = time.time()
    if previous and previous.get("doc_id"):
        doc_id = previous["doc_id"]
        row["doc_id"] = doc_id
        try:
            doc = _get(f"/api/documents/{doc_id}")
            finished = (
                doc.get("status") in {"ready", "segmented"}
                and doc.get("total_seconds") is not None
            )
            if not finished:
                stuck = (
                    doc.get("status") in {"queued", "processing"}
                    and not _doc_is_queued(doc_id)
                )
                if doc.get("status") not in {"queued", "processing"} or stuck:
                    _post(f"/api/documents/{doc_id}/reprocess", timeout=120)
                doc = wait_for_document(doc_id)
        except ApiError as exc:
            row["status"] = "error"
            row["error"] = str(exc)
            return row, None
    else:
        resp = upload_file(path)
        doc_id = resp["id"]
        row["doc_id"] = doc_id
        row["status"] = "queued"
        if on_update is not None:
            on_update(row)
        try:
            doc = wait_for_document(doc_id)
        except ApiError as exc:
            row["status"] = "error"
            row["error"] = str(exc)
            return row, None
    segments = _get(f"/api/documents/{doc_id}/segments") if doc.get("status") == "segmented" else []
    system = _get("/api/system")
    _bench_fill(row, doc, segments, system, time.time() - started)
    return row, doc


def cmd_bench(args) -> int:
    paths: list[str] = []
    if args.files_from:
        paths.extend(
            line.strip()
            for line in Path(args.files_from).expanduser().read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        )
    if args.directory:
        paths.append(args.directory)
    if not paths:
        raise ApiError("Indiquer un dossier ou --files-from")
    files, skipped = _expand_paths(paths)

    out_path = Path(args.out).expanduser()
    if out_path.is_dir():
        out_path = out_path / time.strftime("bench_%Y%m%d_%H%M%S.csv")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    previous_rows = _read_bench_csv(out_path) if args.resume else {}
    rows_by_file = dict(previous_rows)
    order = [str(p) for p in files]

    for index, path in enumerate(files, 1):
        key = str(path)
        previous = previous_rows.get(key)
        if (
            previous
            and previous.get("status") in {"ready", "segmented"}
            and previous.get("ocr_seconds") not in {"", None}
        ):
            rows_by_file[key] = previous
            print(f"[{index}/{len(files)}] skip (done) {path}", file=sys.stderr)
            continue
        print(f"[{index}/{len(files)}] {path}", file=sys.stderr)
        def persist(partial: dict, key: str = key) -> None:
            rows_by_file[key] = partial
            current = [rows_by_file[k] for k in order if k in rows_by_file]
            current.extend(r for k, r in rows_by_file.items() if k not in order)
            _write_bench_csv(out_path, current)

        try:
            row, doc = _bench_process(path, previous, on_update=persist)
        except (ApiError, OSError) as exc:
            row = dict(previous) if previous else _bench_blank_row(path)
            row["status"] = "error"
            row["wall_seconds"] = ""
            row["error"] = str(exc)
            doc = None
        rows_by_file[key] = row
        order_rows = [rows_by_file[k] for k in order if k in rows_by_file]
        extra = [r for k, r in rows_by_file.items() if k not in order]
        _write_bench_csv(out_path, order_rows + extra)
        print(
            f"    {row['status']} pages={row['pages']} docs={row['documents']} "
            f"ocr={row['ocr_seconds']}s llm={row['llm_seconds']}s wall={row['wall_seconds']}s",
            file=sys.stderr,
        )

    rows = [rows_by_file[k] for k in order if k in rows_by_file]
    rows.extend(r for k, r in rows_by_file.items() if k not in order)
    _write_bench_csv(out_path, rows)

    total_pages = sum(int(r["pages"] or 0) for r in rows)
    total_ocr = sum(float(r["ocr_seconds"]) for r in rows if r["ocr_seconds"] not in {"", None})
    total_llm = sum(float(r["llm_seconds"]) for r in rows if r["llm_seconds"] not in {"", None})
    errors = [r for r in rows if r["status"] == "error"]
    summary = {
        "csv": str(out_path),
        "files": len(files),
        "skipped": skipped,
        "pages": total_pages,
        "ocr_seconds": round(total_ocr, 2),
        "ocr_s_per_page": round(total_ocr / total_pages, 2) if total_pages else None,
        "llm_seconds": round(total_llm, 2),
        "errors": errors,
    }
    if args.human:
        print(f"CSV: {out_path}")
        print(f"{summary['files']} fichier(s), {summary['pages']} page(s)")
        print(f"OCR: {summary['ocr_seconds']}s ({summary['ocr_s_per_page']} s/page), LLM: {summary['llm_seconds']}s")
        if errors:
            print(f"{len(errors)} erreur(s)")
    else:
        _print_json(summary)
    return 0 if not errors else 1

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="documind", description="Client CLI Documind")
    parser.add_argument("--url", default=DEFAULT_URL, help="URL de l'API (défaut: %(default)s)")
    parser.add_argument("--timeout", type=float, default=600, help="Timeout HTTP long (défaut: 600s)")
    parser.add_argument("--human", action="store_true", help="Sortie lisible plutôt que JSON")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("upload", help="Téléverser un fichier ou un dossier")
    p.add_argument("paths", nargs="+")
    p.add_argument("--wait", action="store_true", help="Attendre la fin du traitement")
    p.set_defaults(func=cmd_upload)

    p = sub.add_parser("status", help="État du service ou d'un document")
    p.add_argument("doc_id", nargs="?")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("queue", help="File de traitement")
    p.set_defaults(func=cmd_queue)

    p = sub.add_parser("list", help="Lister les documents")
    p.add_argument("--type", dest="type")
    p.add_argument("--since", help="Date minimale (YYYY-MM-DD)")
    p.add_argument("--q", help="Recherche plein texte")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--offset", type=int, default=0)
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("show", help="Afficher un document")
    p.add_argument("doc_id")
    p.add_argument("--text", action="store_true", help="Inclure le texte OCR")
    p.add_argument("--pages", action="store_true", help="Inclure le texte page par page")
    p.add_argument("--meta", action="store_true", help="Métadonnées uniquement (défaut)")
    p.set_defaults(func=cmd_show)

    p = sub.add_parser("search", help="Recherche hybride")
    p.add_argument("query")
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("ask", help="Question RAG sur les documents")
    p.add_argument("question")
    p.add_argument("--session")
    p.set_defaults(func=cmd_ask)

    p = sub.add_parser("stats", help="Statistiques de la collection")
    p.set_defaults(func=cmd_stats)

    p = sub.add_parser("reprocess", help="Relancer le pipeline d'un document")
    p.add_argument("doc_id")
    p.add_argument("--wait", action="store_true")
    p.set_defaults(func=cmd_reprocess)

    p = sub.add_parser("delete", help="Supprimer un document")
    p.add_argument("doc_id")
    p.add_argument("--yes", action="store_true")
    p.set_defaults(func=cmd_delete)

    p = sub.add_parser("bench", help="Ingérer un dossier et écrire un CSV de mesures")
    p.add_argument("directory", nargs="?")
    p.add_argument("--files-from", help="Fichier texte listant les chemins à mesurer")
    p.add_argument("--out", default="bench.csv")
    p.add_argument("--resume", action="store_true", help="Reprendre un CSV existant")
    p.set_defaults(func=cmd_bench)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    global DEFAULT_URL
    DEFAULT_URL = args.url.rstrip("/")
    try:
        return args.func(args)
    except ApiError as exc:
        print(f"documind: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("Interrompu.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
