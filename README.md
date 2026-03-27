# 🗂️ DocuMind

> **Self-hosted document management with OCR + AI — zero account, zero data leakage.**

DocuMind is a self-hosted application that lets you centralize, digitize, organize, and search all your personal documents (invoices, payslips, contracts, certificates, administrative mail) using OCR and AI. Everything runs in a single Docker container with AI powered by the OpenRouter API.

## ✨ Features

- **Smart OCR**: Automatic text extraction from scanned documents and PDFs (Tesseract 5, multilingual: French, English, German, Arabic)
- **AI-Powered Classification**: Automatic metadata extraction (document type, issuer, date, amount, reference) via LLM (OpenRouter API)
- **Hybrid Search**: Full-text search (FTS5) combined with semantic search (sentence embeddings) for finding documents by keywords or meaning
- **Chat with your Documents**: Ask questions about your documents in natural language — the AI answers by citing sources
- **Private**: Your documents stay on your machine. Only document text is sent to the LLM API for analysis. No telemetry.
- **Simple Setup**: One Docker container, one command, one browser tab.

## 🖼️ Screenshots

_Coming soon_

## 🚀 Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)
- 2 GB of free RAM
- An [OpenRouter](https://openrouter.ai/) API key

### 1. Clone the repository

```bash
git clone https://github.com/your-username/documind.git
cd documind
```

### 2. Configure your API key (optional — a default key is included)

Edit `docker-compose.yml` and set your `OPENROUTER_API_KEY`, or export it as an environment variable:

```bash
export OPENROUTER_API_KEY=sk-or-v1-your-key-here
```

### 3. Start DocuMind

```bash
docker compose up -d
```

### 4. Open your browser

Navigate to **[http://localhost:8000](http://localhost:8000)** — that's it!

## 📁 Data Storage

All your data is stored in a Docker volume (or a local directory if you use bind mounts):

```
~/documind/           (or Docker volume)
├── originals/        # Your uploaded files
├── models/           # Embedding model cache
└── documind.db       # SQLite database
```

Your files never leave your machine. You can back up the entire `~/documind/` directory.

## 🏗️ Architecture

```
Single Docker Container — Port 8000
┌────────────────────────────────────┐
│  FastAPI (Python)                  │
│  ├── Static frontend (React)      │
│  ├── REST API                     │
│  ├── OpenRouter API (LLM)         │
│  ├── pytesseract (OCR)            │
│  ├── sentence-transformers (embeddings) │
│  └── SQLite + FTS5 (database)     │
└────────────────────────────────────┘
```

**Stack:**

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.12, FastAPI, uvicorn |
| LLM | OpenRouter API (default model: google/gemini-3.1-pro-preview) |
| OCR | Tesseract 5 (fra+eng+deu+ara) |
| Embeddings | all-MiniLM-L6-v2 via sentence-transformers |
| Search | SQLite FTS5 + cosine similarity |
| Frontend | React/Next.js (static export) |
| Database | SQLite 3 |

## 📡 API Reference

All endpoints are available at `http://localhost:8000/api/`. Interactive API docs at `http://localhost:8000/docs`.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/health` | Health check |
| `POST` | `/api/documents/upload` | Upload a document |
| `GET` | `/api/documents` | List documents (with filters) |
| `GET` | `/api/documents/{id}` | Get document details |
| `PUT` | `/api/documents/{id}` | Update document metadata |
| `DELETE` | `/api/documents/{id}` | Delete a document |
| `POST` | `/api/documents/{id}/reprocess` | Re-analyze a document |
| `POST` | `/api/search` | Hybrid search |
| `POST` | `/api/chat` | Chat with your documents |
| `GET` | `/api/chat/history` | Chat history |
| `GET` | `/api/stats` | Dashboard statistics |

### Upload Example

```bash
curl -X POST http://localhost:8000/api/documents/upload \
  -F "file=@invoice.pdf"
```

### Search Example

```bash
curl -X POST http://localhost:8000/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "facture electricité 2024"}'
```

### Chat Example

```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Quel est le montant de ma dernière facture EDF ?"}'
```

## 🔧 Configuration

Environment variables (all optional, sensible defaults):

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCUMIND_DATA_DIR` | `/data` | Base data directory |
| `OPENROUTER_API_KEY` | _(built-in default)_ | Your OpenRouter API key |
| `OPENROUTER_MODEL` | `google/gemini-3.1-pro-preview` | LLM model to use via OpenRouter |
| `OPENROUTER_BASE_URL` | `https://openrouter.ai/api/v1` | OpenRouter API base URL |

## 🛠️ Development

### Backend

```bash
pip install -r requirements.txt
python main.py
```

### Frontend

```bash
cd frontend
npm install
npm run dev    # Development server on port 3000
npm run build  # Static export to out/
```

### Docker Build

```bash
docker compose build
docker compose up
```

## 📋 Supported Formats

- **PDF** (native text extraction + OCR fallback for scanned pages)
- **Images**: JPG, JPEG, PNG, TIFF, WEBP
- **Max file size**: 50 MB

## 🔒 Privacy & Security

- **Minimal data exposure**: Only extracted text is sent to OpenRouter for AI processing — your original files stay on disk
- **No telemetry**: No analytics, no tracking, no phone home
- **No accounts**: No login, no registration, no authentication
- **Your data, your disk**: Files stored in a local directory you control
- **Open source**: Apache 2.0 license — audit the code yourself

## 🤝 Contributing

Contributions are welcome! Please read the contribution guidelines before submitting a PR.

## 📄 License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
