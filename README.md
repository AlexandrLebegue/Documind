# 🗂️ DocuMind

> **Self-hosted document archive with local OCR, local LLM and hybrid search — no paid API, no document ever leaves your network.**

DocuMind ingests PDFs and images, extracts their text, classifies them, splits
multi-document scans into separate records, and makes everything searchable and
queryable. OCR runs with **OvisOCR3** on CPU; metadata, segmentation and chat use
**MiniCPM5-2B** on a local GPU; embeddings are computed locally with
`sentence-transformers`.

## ✨ Features

- **Local OCR** — OvisOCR3 over an OpenAI-compatible HTTP API, page by page, with
  per-page cache, progress tracking and Tesseract fallback.
- **Smart ingestion** — native PDF text is kept when available; scanned pages are
  rendered at 130 DPI (measured speed/quality sweet spot).
- **Automatic metadata** — title, type, issuer, date, amount, reference, expiry,
  tags, summary — extracted by MiniCPM5-2B, text only.
- **Multi-document scans** — one PDF containing several documents is split into
  child records with page ranges; the source scan becomes a `segmented` container.
- **Hybrid search** — SQLite FTS5 + semantic embeddings, weighted fusion.
- **Chat with your documents** — RAG answers with source document IDs.
- **Long documents** — map-reduce summarisation when OCR text exceeds the context
  budget (200k chars by default).
- **CLI + REST API** — scriptable JSON client (`bin/documind`) and OpenAPI docs.
- **Alerts, procedures, dashboard** — expiry warnings, renewal suggestions, gap
  detection and step-by-step administrative guides.
- **Private by design** — documents, OCR text, embeddings and the database stay on
  your server; only the configured LAN backends see page images/text.

## 🏗️ Architecture

```
                     ┌──────────────────────────────┐
  Browser / CLI ───▶ │  FastAPI + static frontend   │ :8000
                     │  SQLite + FTS5 + embeddings  │
                     └───────┬──────────────┬───────┘
                             │              │
              page JPEG      │              │  OCR text (never images)
                             ▼              ▼
                  ┌──────────────────┐  ┌──────────────────────┐
                  │ OvisOCR3 (CPU)   │  │ MiniCPM5-2B (GPU)    │
                  │ :8081 /v1        │  │ :8080 /v1            │
                  └──────────────────┘  └──────────────────────┘
```

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.11+, FastAPI, uvicorn |
| OCR | OvisOCR3 via llama.cpp (default), Tesseract 5 fallback (fra/eng/deu/ara) |
| LLM | MiniCPM5-2B via llama.cpp, thinking disabled |
| Embeddings | `all-MiniLM-L6-v2` via sentence-transformers (lazy load) |
| Search | SQLite FTS5 + cosine similarity |
| Frontend | React / Next.js static export |
| Database | SQLite 3 (WAL, thread-local connections) |
| CLI | Python standard library only |

OvisOCR3 and MiniCPM are **external services** on the LAN. Their URLs are
configurable and nothing is hard-coded to a cloud provider.

## 🚀 Quick Start — native LXC (recommended)

Tested target: Debian 12/13 LXC, 4 vCPU, 4 GB RAM, Python 3.13.

1. Clone and run the installer inside the container:

```bash
git clone https://github.com/AlexandrLebegue/Documind.git
cd Documind
sudo bash install/documind-install.sh
```

2. Edit the generated environment file if your OCR/LLM servers are not at the
   default addresses:

```bash
sudo nano /opt/documind/.env
sudo systemctl restart documind
```

3. Open `http://<container-ip>:8000` (API docs at `/docs`).

The installer creates `/opt/documind` (code + venv), `/opt/documind-data`
(originals, DB, caches), a `documind` systemd service, and a `documind` CLI
symlink in `/usr/local/bin`.

### One-liner on a Proxmox VE host

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AlexandrLebegue/Documind/main/ct/Documind.sh)
```

The Proxmox installers create the LXC, install dependencies, build the frontend
and configure the service. They no longer ask for an API key. For the standalone
container installer:

```bash
CTID=105 CT_HOSTNAME=documind \
  bash proxmox/install-documind.sh
```

## 🔧 Configuration

Settings are read from `.env` (next to `config.py`) or from the process
environment. `settings.json` in the data directory can override a few values
saved from the web UI.

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCUMIND_DATA_DIR` | `/data` | Base directory for originals, DB, models, OCR cache, bench |
| `AI_PROVIDER` | `llamacpp` | `llamacpp` (local MiniCPM) or legacy providers |
| `LLAMACPP_BASE_URL` | `http://192.168.1.59:8080` | MiniCPM OpenAI-compatible endpoint |
| `LLAMACPP_MODEL` | `minicpm5-2b` | Model alias sent to llama.cpp |
| `LLM_DISABLE_THINKING` | `1` | Disable MiniCPM thinking for deterministic JSON |
| `OVISOCR_URL` | `http://192.168.1.59:8081/v1` | OvisOCR3 OpenAI-compatible endpoint |
| `OVISOCR_MODEL` | `ovisocr3` | OCR model alias |
| `OCR_BACKEND` | `ovis` | `ovis` (default) or `tesseract` |
| `OCR_DPI` | `130` | PDF render DPI (130 = measured sweet spot) |
| `OCR_PROMPT` | `plain` | `plain` text or `markdown` tables |
| `OCR_PAGE_TIMEOUT` | `400` | Per-page OCR timeout in seconds |
| `OCR_PAGE_RETRIES` | `2` | Retries before Tesseract fallback |
| `OCR_CACHE_ENABLED` | `1` | SHA-256 page cache in `DATA_DIR/ocr_cache` |
| `SEGMENT_MULTI_DOC` | `1` | Split scans containing several documents |
| `LLM_MAP_CHUNK_CHARS` | `200000` | Map-reduce threshold (~50k tokens) |
| `LLM_MAP_CHUNK_PAGES` | `8` | Page block size for map-reduce |
| `EMBEDDING_MODEL_NAME` | `all-MiniLM-L6-v2` | Local embedding model |
| `EMBEDDING_LAZY_LOAD` | `1` | Load embeddings on first use |
| `SQLITE_CACHE_MB` / `SQLITE_MMAP_MB` | `20` / `128` | SQLite tuning |
| `NAS_*` | — | Optional SMB sync credentials |

Legacy `AI_PROVIDER=openrouter|ollama|custom` values are still accepted by
`llm.py`, but the default and documented setup is fully local.

## 📁 Data Storage

```
/opt/documind-data/
├── originals/        # Uploaded files (segments share the source file)
├── models/           # Embedding model cache
├── ocr_cache/        # Per-page OCR cache (SHA-256 keyed)
├── bench/            # Benchmark CSV/logs (never committed)
├── documind.db       # SQLite database (FTS5 + metadata + embeddings)
└── settings.json     # Optional UI overrides
```

Back up the whole data directory. Documents and OCR text must stay on the
server; do not copy `bench/` CSVs or database dumps into git or tickets.

## ⌨️ CLI

`bin/documind` (installed as `/usr/local/bin/documind`) talks to the HTTP API with
the Python standard library. JSON is the default output; add `--human` for
tables. Global flags go before the subcommand.

```bash
documind status
documind upload scan.pdf --wait
documind upload /srv/docs-test/
documind list --type facture --since 2024-01-01 --q EDF
documind show <id> --pages
documind search "facture électricité 2024"
documind ask "Quelle est la date d'expiration de ma carte d'identité ?"
documind reprocess <id> --wait
documind delete <id> --yes
documind stats
documind bench /srv/docs-test --out /opt/documind-data/bench/run.csv --resume
```

For agents and advanced usage (API details, errors, multi-document handling), see
[`skills/documind/SKILL.md`](skills/documind/SKILL.md).

## 💻 Client PC (Tauri 2)

Le client PC réutilise exactement l'interface web (export statique Next.js) dans
une fenêtre native Tauri 2 — environ 10 Mo, WebView du système, aucun Electron.
Téléchargez l'installeur depuis la page [**Releases**](https://github.com/AlexandrLebegue/Documind/releases) du dépôt :

- **Windows** : `DocuMind_<version>_x64-setup.exe` (NSIS, inclut `documind-agent.exe`)
- **Linux** : `.AppImage` ou `.deb` (dépendances `webkit2gtk-4.1`)

### Premier lancement

1. Lancez DocuMind. Un écran plein écran demande l'adresse du serveur, par
   exemple `192.168.1.67:8000`.
2. La validation appelle `/api/system` ; un message clair s'affiche si le
   serveur est injoignable.
3. Une animation géométrique courte (600–1200 ms, désactivée si
   `prefers-reduced-motion`) ouvre l'application.
4. L'adresse est mémorisée dans le store Tauri et peut être changée dans
   **Paramètres → Changer de serveur**.

Côté serveur, le CORS accepte par défaut toutes les origines (comportement
historique) et les origines Tauri `tauri://localhost`,
`http://tauri.localhost`, `https://tauri.localhost`. Pour restreindre, définissez
`CORS_ORIGINS` (liste séparée par des virgules).

### Synchronisation automatique de dossiers

Dans **Paramètres → Synchronisation automatique** (client PC uniquement) :

- ajoutez un ou plusieurs dossiers (sélecteur natif ou saisie manuelle) ;
- choisissez l'intervalle (15 min, 1 h, 6 h, 24 h) et activez la synchronisation ;
- installez le service : **service Windows** (démarrage automatique au boot,
  élévation UAC demandée) ou **unité systemd --user** sur Linux ;
- consultez l'état du service, le dernier passage et les compteurs
  envoyés / acceptés / refusés / ignorés.

L'agent (`documind-agent`) filtre localement avant tout envoi : extensions
`.pdf .txt .jpg .jpeg .png .bmp`, vérification des magic bytes, fichiers cachés
et temporaires exclus, fichiers instables sur deux relevés, taille entre 1 Ko et
50 Mo. Il calcule le SHA-256 (cache chemin+taille+mtime) et n'envoie que les
empreintes inconnues du serveur. Un fichier déjà accepté ou refusé n'est jamais
renvoyé, même déplacé ou renommé.

Côté serveur, chaque candidat est revalidé (extension + magic bytes), OCRisé
(cache de pages réutilisé), puis jugé par MiniCPM texte seul :
`{keep, confidence, reason}`. Un OUI franc crée le document en réutilisant l'OCR ;
un NON franc supprime le fichier et ne garde que l'empreinte ; un doute
(confiance < 0,7) part en validation manuelle dans **Synchronisation** (web et
desktop), avec actions Accepter / Refuser / Réévaluer.

Configuration partagée : `%ProgramData%\DocuMind\agent.json` sous Windows,
`~/.config/documind/agent.json` sous Linux. Logs rotatifs dans
`logs/agent.log`. CLI :

```bash
documind marks --verdict pending --human
documind marks --accept <sha256>
documind marks --reject <sha256>
documind marks --reevaluate <sha256>
```

### Construire le client localement

```bash
rustup toolchain install stable
cd desktop
cargo build --release -p documind-agent
cp target/release/documind-agent src-tauri/binaries/documind-agent-$(rustc -vV | sed -n 's/host: //p')
npm ci && npx tauri build
```

Les builds Windows/Linux complets sont produits par
`.github/workflows/desktop.yml` (tag `v*` → Release GitHub).

## 📊 Benchmarking

`documind bench` ingests every supported file (or a list via `--files-from`),
waits for completion, and writes one CSV row per file with pages, OCR seconds
and seconds/page, MiniCPM seconds, number of documents produced, types/titles,
wall time, process RSS/peak RSS and errors. `--resume` skips completed rows and
retries interrupted ones without re-uploading.

```bash
documind bench /srv/docs-test --out /opt/documind-data/bench/all.csv --resume
```

Aggregated, content-free results live in [`docs/BENCH.md`](docs/BENCH.md).
Performance work on startup/database is documented in
[`docs/PERF.md`](docs/PERF.md); session progress is tracked in
[`docs/STATUS.md`](docs/STATUS.md).

## 📡 API Reference

Interactive docs: `http://<host>:8000/docs`.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/health` | Service health and document count |
| `GET` | `/api/system` | Process RSS/peak, uptime, status counts |
| `GET` | `/api/queue` | Active/pending processing queue |
| `POST` | `/api/documents/upload` | Upload a PDF/image (multipart `file`) |
| `GET` | `/api/documents` | List/filter (`doc_type`, `date_from`, `q`, `filename`, pagination) |
| `GET` | `/api/documents/{id}` | Full document with OCR text |
| `GET` | `/api/documents/{id}/segments` | Child documents of a segmented scan |
| `GET` | `/api/documents/{id}/file` | Original file |
| `PUT` | `/api/documents/{id}` | Edit metadata |
| `POST` | `/api/documents/{id}/reprocess` | Re-run OCR → segmentation → metadata |
| `DELETE` | `/api/documents/{id}` | Delete a document (and its segments) |
| `POST` | `/api/search` | Hybrid FTS + semantic search |
| `POST` | `/api/chat` | RAG chat with source IDs |
| `GET` | `/api/chat/sessions` | Chat sessions |
| `GET` | `/api/stats` | Dashboard statistics |
| `GET` | `/api/alerts` | Expiry/renewal/gap alerts |
| `GET` | `/api/procedures` | Administrative procedures |
| `POST` | `/api/ingest/check` | Hashes déjà jugés + hashes inconnus |
| `POST` | `/api/ingest/candidate` | Candidat de synchronisation (multipart) |
| `GET` | `/api/ingest/marks` | Registre des empreintes et verdicts |
| `POST` | `/api/ingest/marks/{sha}/accept` | Accepter un candidat en attente |
| `POST` | `/api/ingest/marks/{sha}/reject` | Refuser un candidat |
| `POST` | `/api/ingest/marks/{sha}/reevaluate` | Forcer une réévaluation |

### Examples

```bash
curl -X POST http://localhost:8000/api/documents/upload -F "file=@invoice.pdf"

curl -X POST http://localhost:8000/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "facture electricite 2024"}'

curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Quel est le montant de ma dernière facture ?"}'
```

## 🛠️ Development

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python main.py --skip-build
```

Frontend:

```bash
cd frontend
npm ci
npm run build          # static export in frontend/out
```

Useful scripts:

```bash
python scripts/perf_profile.py imports
python scripts/perf_profile.py startup
python scripts/perf_profile.py db
```

There is no test suite in the repository; validate changes with
`python -m py_compile` and a real ingestion on the LXC test corpus.

## 📋 Supported Formats

`.pdf`, `.jpg`, `.jpeg`, `.png`, `.tiff`, `.webp` (max 50 MB per file).

Unsupported formats found during a folder ingest (`.docx`, `.txt`, `.rar`,
`.zip`) are listed and skipped without crashing.

## 🔒 Privacy & Security

- Original files and extracted text remain in `DOCUMIND_DATA_DIR`.
- OCR images are sent only to `OVISOCR_URL`; text is sent only to
  `LLAMACPP_BASE_URL` (both on the LAN by default).
- No API key is required for the default local pipeline.
- Never commit personal documents, OCR text, database files or bench CSVs.
- The service listens on port 8000; restrict access with your firewall or a
  reverse proxy if the LAN is not trusted.

## 🤝 Contributing

Small, focused commits are preferred. Do not include personal document content
or credentials in commits, issues or logs. Update `docs/STATUS.md` after each
milestone and benchmark changes with `documind bench`.

## 📄 License

MIT — see [LICENSE](LICENSE).
