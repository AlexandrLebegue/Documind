# Fix: Search Documents Returns No Results

## Problem
Searching on the documents page returns 0 results even though matching documents exist in the database.

## Root Cause Analysis

The search flow on the documents page is:

```mermaid
flowchart LR
    A[SearchBar component] -->|debounce 300ms| B[setQuery]
    B --> C[fetchDocs]
    C --> D[getDocuments - api.ts]
    D -->|GET /api/documents?q=...| E[list_docs - main.py]
    E --> F[list_documents - database.py]
    F -->|FTS5 MATCH| G[SQLite FTS5 index]
    G -->|0 results| F
```

**The documents page never uses the hybrid search endpoint** (`POST /api/search`). It uses `GET /api/documents?q=...` which goes through `list_documents()` with raw FTS5 MATCH.

### 6 bugs identified, 2 critical:

---

## Bug 1 — CRITICAL: Wrong FTS5 MATCH syntax in `list_documents`

**File:** [`database.py`](database.py:304)

```python
# Line 304 — BROKEN
conditions.append("f.documents_fts MATCH ?")
```

The FTS5 table `documents_fts` is aliased as `f` in the FROM clause. Using `f.documents_fts MATCH ?` tries to access the hidden FTS5 column through an alias — this is unreliable and may silently return no matches.

Compare with [`search_fts()`](database.py:411) which correctly uses:
```sql
WHERE documents_fts MATCH ?
```

**Fix:** Change line 304 to:
```python
conditions.append("documents_fts MATCH ?")
```

---

## Bug 2 — CRITICAL: FTS5 index not rebuilt for pre-existing documents

**File:** [`database.py`](database.py:30)

The FTS5 content-sync table relies on triggers to keep the index up to date. But if:
- The database existed before the FTS table was created
- The FTS table was dropped/recreated during a migration
- Documents were bulk-imported outside the application

...those documents are invisible to FTS search. There is no rebuild step.

**Fix:** Add an FTS5 rebuild command at the end of [`init_db()`](database.py:30):
```python
cur.execute("INSERT INTO documents_fts(documents_fts) VALUES('rebuild');")
```

This re-indexes all rows from the content table on every startup. It is fast for small/medium collections.

---

## Bug 3 — MODERATE: FTS5 only indexes `text_content`

**File:** [`database.py`](database.py:68)

The FTS5 virtual table only indexes `text_content`:
```sql
USING fts5(text_content, content='documents', content_rowid='rowid')
```

But the UI placeholder says *Rechercher par nom, contenu, emetteur...* — suggesting filename, title, emetteur, and resume should also be searchable. Searching for a document by its filename or sender currently never matches.

**Fix:** Expand the FTS5 table to include additional columns:
```sql
USING fts5(
    title, filename, text_content, emetteur, resume, tags,
    content='documents', content_rowid='rowid'
)
```
Update all three triggers (INSERT, DELETE, UPDATE) to sync all these columns.

> **Note:** This requires dropping and recreating the FTS table + triggers since FTS5 schema cannot be altered. The rebuild in Bug 2 fix will repopulate it.

---

## Bug 4 — MODERATE: No FTS5 query sanitization

**Files:** [`database.py`](database.py:298) and [`database.py`](database.py:397)

Raw user input is passed directly to FTS5 MATCH. FTS5 has special syntax characters (`AND`, `OR`, `NOT`, `NEAR`, `*`, `^`, `"`, etc.). Certain inputs can cause SQLite parse errors that bubble up as 500 errors.

**Fix:** Sanitize/escape the query before passing to MATCH. A simple approach is to double-quote each token:
```python
def _sanitize_fts_query(query: str) -> str:
    tokens = query.strip().split()
    if not tokens:
        return ""
    # Wrap each token in double quotes to escape FTS5 operators
    return " ".join(f'"{token}"' for token in tokens)
```

Apply this in both `list_documents()` and `search_fts()`.

---

## Bug 5 — MODERATE: `total` count is broken for pagination

**File:** [`main.py`](main.py:361)

```python
return DocumentListResponse(
    documents=documents,
    total=len(documents),  # ← BUG: this is the page size, not the total
    ...
)
```

The `total` field always equals the current page length. The frontend `hasMore` check (`documents.length < total`) is therefore always false, so Load More never appears.

**Fix:** Add a `count_documents()` function to `database.py` that runs the same filters without LIMIT/OFFSET, and use its result for `total`:
```python
total = count_documents(doc_type=doc_type, emetteur=emetteur, ...)
```

---

## Bug 6 — LOW: Documents page never uses hybrid search

**Files:** [`frontend/src/app/documents/page.tsx`](frontend/src/app/documents/page.tsx:44) and [`frontend/src/lib/api.ts`](frontend/src/lib/api.ts:128)

The `search()` function in `api.ts` and the `POST /api/search` endpoint exist but are never called by any frontend page. The documents page only uses `getDocuments({q: ...})` which is FTS-only — no semantic/embedding matching.

**Fix (deferred):** This is a design choice. For now, fixing FTS properly (Bugs 1-4) will make the documents page search functional. The hybrid search can be wired up later if desired.

---

## Implementation Order

1. **Bug 1** — Fix MATCH syntax in `list_documents` (one-line change in `database.py`)
2. **Bug 3** — Expand FTS5 schema to multi-column (drop + recreate FTS table & triggers in `database.py`)
3. **Bug 2** — Add FTS5 rebuild in `init_db` (one line in `database.py`)
4. **Bug 4** — Add FTS query sanitization helper (new function + apply in `database.py`)
5. **Bug 5** — Fix total count for pagination (new `count_documents` in `database.py` + update `main.py`)
6. **Bug 6** — Deferred / optional

All changes are in two files: `database.py` and `main.py`.
