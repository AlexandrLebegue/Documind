#!/usr/bin/env bash
# Copyright (c) 2025 community-scripts ORG
# Author: AlexandrLebegue
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/AlexandrLebegue/Documind
#
# Can be run in two ways:
#   1. Via community-scripts build_container (FUNCTIONS_FILE_PATH is set)
#   2. Standalone / curl-pipe  (no FUNCTIONS_FILE_PATH — stubs are used)
#      curl -fsSL https://raw.githubusercontent.com/AlexandrLebegue/Documind/main/install/documind-install.sh | bash

# ---------------------------------------------------------------------------
# Bootstrap helpers — use community-scripts install.func when available,
# otherwise fall back to minimal stubs so the script works standalone.
# ---------------------------------------------------------------------------
if [[ -n "${FUNCTIONS_FILE_PATH:-}" ]]; then
  # Running inside community-scripts build_container
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os
else
  # Standalone / curl-pipe execution — define minimal stubs
  set -Eeuo pipefail
  function STD()              { "$@"; }                 # run commands verbosely
  function msg_info()         { echo -e "  \e[1;34mℹ\e[0m  ${1}"; }
  function msg_ok()           { echo -e "  \e[1;32m✓\e[0m  ${1}"; }
  function msg_error()        { echo -e "  \e[1;31m✗\e[0m  ${1}"; exit 1; }
  function motd_ssh()         { :; }
  function customize()        { :; }
  # Bootstrap the OS
  echo -e "\n\e[1;36m  DocuMind — Standalone Installer\e[0m\n"
  apt-get update -qq
  apt-get upgrade -y -qq
fi

APP="Documind"
APP_DIR="/opt/documind"
DATA_DIR="/opt/documind-data"
REPO="https://github.com/AlexandrLebegue/Documind.git"

# ---------------------------------------------------------------------------
# 1. System dependencies (including build tools for native Python packages)
# ---------------------------------------------------------------------------
msg_info "Installing System Dependencies"
$STD apt-get install -y --no-install-recommends \
  build-essential \
  python3-dev \
  pkg-config \
  python3 \
  python3-pip \
  python3-venv \
  tesseract-ocr \
  tesseract-ocr-fra \
  tesseract-ocr-eng \
  tesseract-ocr-deu \
  tesseract-ocr-ara \
  libgl1 \
  libglib2.0-0 \
  curl \
  ca-certificates \
  gnupg \
  git
msg_ok "Installed System Dependencies"

# ---------------------------------------------------------------------------
# 2. Node.js 20 (for frontend build)
# ---------------------------------------------------------------------------
msg_info "Installing Node.js 20"
$STD bash <(curl -fsSL https://deb.nodesource.com/setup_20.x)
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node --version)"

# ---------------------------------------------------------------------------
# 3. Clone repository
# ---------------------------------------------------------------------------
msg_info "Cloning ${APP} repository"
$STD git clone --depth=1 "$REPO" "$APP_DIR"
mkdir -p "${DATA_DIR}/originals" "${DATA_DIR}/models"
msg_ok "Cloned ${APP}"

# ---------------------------------------------------------------------------
# 4. Python virtual environment
# ---------------------------------------------------------------------------
msg_info "Creating Python virtual environment"
python3 -m venv "${APP_DIR}/venv"
msg_ok "Created virtual environment"

# ---------------------------------------------------------------------------
# 5. Core Python dependencies (MUST succeed)
# ---------------------------------------------------------------------------
msg_info "Installing CPU-only PyTorch (this may take several minutes)"
$STD "${APP_DIR}/venv/bin/pip" install --no-cache-dir \
  torch --index-url https://download.pytorch.org/whl/cpu
msg_ok "Installed PyTorch (CPU)"

msg_info "Installing core Python dependencies"
$STD "${APP_DIR}/venv/bin/pip" install --no-cache-dir \
  -r "${APP_DIR}/requirements.txt"
msg_ok "Installed core Python dependencies"

# ---------------------------------------------------------------------------
# 6. Optional Python dependencies (allowed to fail)
# ---------------------------------------------------------------------------
msg_info "Installing optional Python dependencies (web agent tools)"
if "${APP_DIR}/venv/bin/pip" install --no-cache-dir \
    -r "${APP_DIR}/requirements-optional.txt" 2>/dev/null; then
  msg_ok "Installed optional Python dependencies"

  # Playwright needs a post-install step to download Chromium
  msg_info "Installing Playwright Chromium browser"
  if "${APP_DIR}/venv/bin/playwright" install chromium --with-deps 2>/dev/null; then
    msg_ok "Installed Playwright Chromium"
  else
    msg_info "Playwright Chromium skipped (non-critical)"
  fi
else
  msg_info "Optional dependencies skipped (crawl4ai/playwright — non-critical)"
fi

# ---------------------------------------------------------------------------
# 7. Build frontend
# ---------------------------------------------------------------------------
msg_info "Building frontend"
cd "${APP_DIR}/frontend"
$STD npm ci
$STD npm run build
# Static export lands in frontend/out; move it to static/
if [[ -d "${APP_DIR}/frontend/out" ]]; then
  mv "${APP_DIR}/frontend/out" "${APP_DIR}/static"
  msg_ok "Built frontend"
else
  msg_error "Frontend build failed — ${APP_DIR}/frontend/out not found. The API will work but the web UI will be unavailable."
fi

# ---------------------------------------------------------------------------
# 8. Environment configuration
# ---------------------------------------------------------------------------
msg_info "Writing environment configuration"
cat >"${APP_DIR}/.env" <<'ENVEOF'
# DocuMind Environment Configuration
# Set your OpenRouter API key below after installation:
#   nano /opt/documind/.env  &&  systemctl restart documind
DOCUMIND_DATA_DIR=/opt/documind-data
OPENROUTER_API_KEY=
OPENROUTER_MODEL=google/gemini-3.1-pro-preview
PYTHONUNBUFFERED=1
ENVEOF
msg_ok "Wrote environment configuration"

# ---------------------------------------------------------------------------
# 9. Systemd service
# ---------------------------------------------------------------------------
msg_info "Creating systemd service"
cat >/etc/systemd/system/documind.service <<'SVCEOF'
[Unit]
Description=DocuMind - Document Management with AI
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/documind
EnvironmentFile=/opt/documind/.env
ExecStart=/opt/documind/venv/bin/python main.py --skip-build
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
$STD systemctl enable documind.service
msg_ok "Created systemd service"

# ---------------------------------------------------------------------------
# 10. Record installed version
# ---------------------------------------------------------------------------
RELEASE=$(curl -fsSL https://api.github.com/repos/AlexandrLebegue/Documind/releases/latest \
  | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null || true)
if [[ -z "$RELEASE" ]]; then
  RELEASE=$(curl -fsSL https://api.github.com/repos/AlexandrLebegue/Documind/commits/main \
    | grep '"sha"' | head -1 | sed -E 's/.*"([0-9a-f]{7})[0-9a-f]*.*/\1/' 2>/dev/null || true)
fi
echo "${RELEASE:-unknown}" >"${APP_DIR}/version.txt"

# ---------------------------------------------------------------------------
# 11. Start service and verify it is running
# ---------------------------------------------------------------------------
msg_info "Starting ${APP} service"
systemctl start documind.service

# Give the Python process a few seconds to either stabilise or crash
sleep 5

if systemctl is-active --quiet documind.service; then
  msg_ok "Started ${APP} service — listening on port 8000"
else
  msg_error "${APP} service failed to start! Dumping journal logs:"
  journalctl -u documind.service --no-pager -n 40
  msg_error "Fix the issue above, then run:  systemctl restart documind"
fi

motd_ssh
customize
