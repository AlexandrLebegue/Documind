# Proxmox LXC — DocuMind Deployment Scripts

Scripts for deploying and managing DocuMind as a Proxmox LXC container.

## Deployment methods

### Method 1 — Proxmox Community Helper Scripts (recommended)

The files `ct/Documind.sh` and `install/documind-install.sh` in this repo
follow the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
standard. Once the script is accepted upstream, you can run it directly from
the Proxmox shell with a single command (no file copying needed):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/Documind.sh)"
```

The community script:
- Clones DocuMind from GitHub directly into the container
- Installs all dependencies (Python 3.12, Node.js 20, Tesseract OCR, PyTorch CPU)
- Builds the Next.js frontend
- Creates and enables a `documind.service` systemd unit
- Provides a built-in **update** flow (run the same script again on an existing container)

After install, set your OpenRouter API key:

```bash
pct exec <CTID> -- nano /opt/documind/.env
pct exec <CTID> -- systemctl restart documind
```

---

### Method 2 — Standalone scripts (manual / offline)

Use these when you want direct control or are working from a local copy
of the project without internet access inside the container.

| Script | Purpose |
|--------|---------|
| `install-documind.sh` | **Fresh install** — creates a new LXC container and deploys DocuMind from scratch |
| `update-documind.sh` | **Update** — pushes code changes to an existing running container |
| `proxmox-export.sh` | **Backup** — exports a container as a vzdump archive |

Creates a new Debian 12 LXC container, installs all dependencies, and deploys DocuMind.

```bash
# Copy scripts + project to Proxmox host
scp -r . root@<proxmox-host>:/tmp/documind-install/

# Run on the Proxmox host
ssh root@<proxmox-host>
cd /tmp/documind-install/proxmox
chmod +x install-documind.sh
./install-documind.sh
```

### Install Options (environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `CTID` | `104` | Container ID |
| `CT_HOSTNAME` | `documind` | Hostname |
| `OPENROUTER_API_KEY` | *(prompt)* | API key for AI features |
| `OPENROUTER_MODEL` | `google/gemini-3.1-pro-preview` | LLM model |

---

## Updating an Existing Container

After making code changes locally, use `update-documind.sh` to push them to the running container.

### Quick Start

```bash
# 1. Copy updated project files to Proxmox host
scp -r /path/to/documind/* root@<proxmox-host>:/tmp/documind-install/

# 2. Copy the update script (if not already there)
scp proxmox/update-documind.sh root@<proxmox-host>:/tmp/documind-install/proxmox/

# 3. SSH into Proxmox and run the update
ssh root@<proxmox-host>
cd /tmp/documind-install/proxmox
chmod +x update-documind.sh
./update-documind.sh
```

### What It Does

1. **Stops** the `documind.service`
2. **Pushes** updated Python files (`.py` + `requirements.txt`) via `pct push`
3. **Pushes** updated frontend source (`frontend/`) as a tar archive
4. **Installs** Python dependencies (`pip install -r requirements.txt`)
5. **Rebuilds** the frontend (`npm ci && npm run build`)
6. **Deploys** the built frontend to `static/`
7. **Restarts** the `documind.service`

### Usage

```
Usage:
  update-documind.sh [OPTIONS]

Options:
  --id <CTID>         Container ID (default: 104)
  --skip-frontend     Skip frontend rebuild (backend-only update)
  --skip-deps         Skip pip install (requirements.txt unchanged)
  --full              Full update: deps + frontend (default)
  -h, --help          Show help message
```

### Examples

```bash
# Full update (push everything, install deps, rebuild frontend)
./update-documind.sh

# Backend-only update (Python files changed, frontend unchanged)
./update-documind.sh --skip-frontend --skip-deps

# Code + frontend update, but requirements.txt didn't change
./update-documind.sh --skip-deps

# Update a different container
./update-documind.sh --id 105
```

### Typical Workflows

| What changed | Command |
|-------------|---------|
| Python files only | `./update-documind.sh --skip-frontend --skip-deps` |
| Python files + requirements.txt | `./update-documind.sh --skip-frontend` |
| Frontend files only | `./update-documind.sh --skip-deps` |
| Everything | `./update-documind.sh` |

---

## Backup / Export

Export a running container as a vzdump archive for backup or migration.

```bash
# Basic export (snapshot mode, zstd compression)
./proxmox-export.sh --id 104

# Export to custom directory
./proxmox-export.sh --id 104 --dumpdir /mnt/backups

# Stop container during backup (most consistent)
./proxmox-export.sh --id 104 --mode stop
```

### Export Options

| Flag | Default | Description |
|------|---------|-------------|
| `-i, --id <CTID>` | *(required)* | Container ID |
| `-d, --dumpdir <PATH>` | `/var/lib/vz/dump` | Output directory |
| `-c, --compress <TYPE>` | `zstd` | Compression: zstd, gzip, lzo, none |
| `-m, --mode <MODE>` | `snapshot` | Backup mode: snapshot, suspend, stop |

### Restoring a Backup

```bash
pct restore 200 /var/lib/vz/dump/vzdump-lxc-104-*.tar.zst \
  --storage local-lvm
```

---

## Container Layout

```
CT104 (documind)
├── /opt/documind/              ← Application code
│   ├── main.py                 ← FastAPI entry point
│   ├── *.py                    ← Backend modules
│   ├── requirements.txt
│   ├── .env                    ← Environment config
│   ├── venv/                   ← Python virtual environment
│   ├── frontend/               ← Next.js source
│   └── static/                 ← Built frontend (served by FastAPI)
│
└── /opt/documind-data/         ← Persistent data (never touched by updates)
    ├── documind.db             ← SQLite database
    ├── originals/              ← Uploaded documents
    └── models/                 ← Embedding models cache
```

## Useful Commands

```bash
# Check service status
pct exec 104 -- systemctl status documind

# View live logs
pct exec 104 -- journalctl -u documind -f

# Restart the service
pct exec 104 -- systemctl restart documind

# Enter the container shell
pct enter 104

# Edit environment config
pct exec 104 -- nano /opt/documind/.env
```

## License

MIT
