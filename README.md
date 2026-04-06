# 🗂️ DocuMind

> **Self-hosted document management with OCR + AI — zero account, zero data leakage.**

DocuMind centralizes, digitizes, organizes, and searches your personal documents (invoices, payslips, contracts, certificates, administrative mail) using OCR and AI. Everything runs in a single process or Docker container; AI is powered by the [OpenRouter](https://openrouter.ai/) API.

## ✨ Features

- **Smart OCR** — automatic text extraction from scanned PDFs and images (Tesseract 5, FR/EN/DE/AR)
- **AI Classification** — automatic metadata extraction (type, issuer, date, amount, reference) via LLM
- **Hybrid Search** — full-text (FTS5) + semantic (sentence embeddings) search
- **Chat with your documents** — ask questions in natural language, AI answers with citations
- **Smart Alerts** — expiry warnings, renewal suggestions, gap detection
- **Procedures** — step-by-step administrative guides with document matching
- **Private** — your files never leave your machine; only extracted text is sent to OpenRouter

---

## 🚀 Quick Start — Docker Compose

The fastest way to run DocuMind on any machine with Docker.

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) + [Docker Compose](https://docs.docker.com/compose/install/)
- 2 GB free RAM
- An [OpenRouter](https://openrouter.ai/) API key

### 1. Clone the repository

```bash
git clone https://github.com/AlexandrLebegue/Documind.git
cd Documind
```

### 2. Set your API key

```bash
cp .env.example .env
nano .env          # set OPENROUTER_API_KEY=sk-or-v1-...
```

### 3. Start

```bash
docker compose up -d
```

### 4. Open your browser

**[http://localhost:8000](http://localhost:8000)** — that's it!

> **Data storage**: by default the `docker-compose.yml` mounts a named Docker volume.
> To use a NAS/CIFS share instead, configure the `driver_opts` block in `docker-compose.yml`.

---

## 🖥️ Deploy on Proxmox VE (LXC container)

Run the one-liner below on your **Proxmox host shell** — it creates a Debian 12 LXC container
and lets you choose between two install methods:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AlexandrLebegue/Documind/main/ct/Documind.sh)
```

You will be prompted to choose:

| # | Method | Description |
|---|--------|-------------|
| **1** | **Docker** | DocuMind runs in Docker Compose inside the LXC. Easy updates with `docker compose pull`. Requires ~500 MB extra for Docker. |
| **2** | **Native** | Python venv + Node.js installed directly. No Docker overhead, direct `systemd` service management. |

After the installation finishes you will see the LXC IP and the command to set your API key.

### Override default settings

```bash
CTID=110 CT_RAM=4096 CT_DISK=20 CT_HOSTNAME=docs \
  bash <(curl -fsSL https://raw.githubusercontent.com/AlexandrLebegue/Documind/main/ct/Documind.sh)
```

| Variable | Default | Description |
|----------|---------|-------------|
| `CTID` | next available | Proxmox container ID |
| `CT_HOSTNAME` | `documind` | LXC hostname |
| `CT_RAM` | `2048` | RAM in MiB |
| `CT_CORES` | `2` | vCPU count |
| `CT_DISK` | `10` | Root disk in GiB |
| `CT_BRIDGE` | `vmbr0` | Network bridge |
| `TEMPLATE_STORAGE` | `local` | Storage for the Debian template |
| `CONTAINER_STORAGE` | `local-lvm` | Storage for the container rootfs |

### Post-install — set your API key

**Docker method:**
```bash
pct exec <CTID> -- nano /opt/documind/.env
pct exec <CTID> -- docker compose -f /opt/documind/docker-compose.yml up -d
```

**Native method:**
```bash
pct exec <CTID> -- nano /opt/documind/.env
pct exec <CTID> -- systemctl restart documind
```

---

## 🔧 Configuration

All environment variables (set in `.env` or `docker-compose.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCUMIND_DATA_DIR` | `/data` | Base data directory (originals, DB, model cache) |
| `OPENROUTER_API_KEY` | _(empty)_ | Your OpenRouter API key |
| `OPENROUTER_MODEL` | `google/gemini-3.1-pro-preview` | LLM model via OpenRouter |
| `OPENROUTER_BASE_URL` | `https://openrouter.ai/api/v1` | OpenRouter API URL |
| `PYTHONUNBUFFERED` | `1` | Flush Python logs immediately |

---

## 📁 Data Storage

```
/data/  (or ~/documind/ for bind-mount)
├── originals/        # Uploaded original files
├── models/           # Embedding model cache (~90 MB on first run)
└── documind.db       # SQLite database (FTS5 + all metadata)
```

Your files never leave your server. Back up the whole `/data/` directory regularly.

---

## 🏗️ Architecture

```
Single process — Port 8000
┌───────────────────────────────────────┐
│  FastAPI (Python 3.12)                │
│  ├── Static frontend (Next.js)        │
│  ├── REST API  /api/*                 │
│  ├── OpenRouter  (LLM / AI)           │
│  ├── pytesseract  (OCR)               │
│  ├── sentence-transformers (vectors)  │
│  └── SQLite + FTS5  (database)        │
└───────────────────────────────────────┘
```

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.12, FastAPI, uvicorn |
| LLM | OpenRouter API (default: `google/gemini-3.1-pro-preview`) |
| OCR | Tesseract 5 (fra + eng + deu + ara) |
| Embeddings | `all-MiniLM-L6-v2` via sentence-transformers |
| Search | SQLite FTS5 + cosine similarity |
| Frontend | React / Next.js (static export) |
| Database | SQLite 3 |

---

## 📡 API Reference

Interactive docs at **[http://localhost:8000/docs](http://localhost:8000/docs)**.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET`  | `/api/health` | Health check |
| `POST` | `/api/documents/upload` | Upload a document |
| `GET`  | `/api/documents` | List documents |
| `GET`  | `/api/documents/{id}` | Get document details |
| `PUT`  | `/api/documents/{id}` | Update metadata |
| `DELETE` | `/api/documents/{id}` | Delete a document |
| `POST` | `/api/documents/{id}/reprocess` | Re-analyze a document |
| `POST` | `/api/search` | Hybrid search |
| `POST` | `/api/chat` | Chat with documents |
| `GET`  | `/api/chat/sessions` | List chat sessions |
| `POST` | `/api/agent/chat` | Agentic chat (web search enabled) |
| `GET`  | `/api/procedures` | List procedures |
| `GET`  | `/api/alerts` | Smart alerts |
| `GET`  | `/api/stats` | Dashboard statistics |

### Examples

```bash
# Upload
curl -X POST http://localhost:8000/api/documents/upload -F "file=@invoice.pdf"

# Search
curl -X POST http://localhost:8000/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "facture electricite 2024"}'

# Chat
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Quel est le montant de ma dernière facture EDF ?"}'
```

---

## 🛠️ Development

### Backend

```bash
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
# Optional web-agent tools:
pip install -r requirements-optional.txt
python main.py                    # builds frontend + starts server on :8000
```

### Frontend only

```bash
cd frontend
npm install
npm run dev     # dev server on :3000 with API proxy to :8000
npm run build   # static export to frontend/out/
```

### Docker Build

```bash
docker compose build
docker compose up
```

---

## 📋 Supported Formats

| Format | Notes |
|--------|-------|
| PDF | Native text extraction + OCR fallback for scanned pages |
| JPG / JPEG / PNG | Full OCR |
| TIFF / WEBP | Full OCR |
| Max size | 50 MB per file |

---

## 🔒 Privacy & Security

- **Minimal exposure**: only extracted text is sent to OpenRouter — original files stay on disk
- **No telemetry**: no analytics, no tracking
- **No accounts**: no login, no registration
- **Open source**: audit the code yourself

---

## 🤝 Contributing

Contributions are welcome! Please open an issue or PR on [GitHub](https://github.com/AlexandrLebegue/Documind).

## 📄 License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
