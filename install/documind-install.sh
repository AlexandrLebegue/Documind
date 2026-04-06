#!/usr/bin/env bash
# Copyright (c) 2025 community-scripts ORG
# Author: AlexandrLebegue
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/AlexandrLebegue/Documind

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP="Documind"
APP_DIR="/opt/documind"
DATA_DIR="/opt/documind-data"
REPO="https://github.com/AlexandrLebegue/Documind.git"

msg_info "Installing System Dependencies"
$STD apt-get install -y --no-install-recommends \
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

msg_info "Installing Node.js 20"
$STD bash <(curl -fsSL https://deb.nodesource.com/setup_20.x)
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node --version)"

msg_info "Cloning ${APP} repository"
$STD git clone --depth=1 "$REPO" "$APP_DIR"
mkdir -p "${DATA_DIR}/originals" "${DATA_DIR}/models"
msg_ok "Cloned ${APP}"

msg_info "Creating Python virtual environment"
python3 -m venv "${APP_DIR}/venv"
msg_ok "Created virtual environment"

msg_info "Installing CPU-only PyTorch (this may take several minutes)"
$STD "${APP_DIR}/venv/bin/pip" install --no-cache-dir \
  torch --index-url https://download.pytorch.org/whl/cpu
msg_ok "Installed PyTorch (CPU)"

msg_info "Installing Python dependencies"
$STD "${APP_DIR}/venv/bin/pip" install --no-cache-dir \
  -r "${APP_DIR}/requirements.txt"
msg_ok "Installed Python dependencies"

msg_info "Building frontend"
cd "${APP_DIR}/frontend"
$STD npm ci --prefer-offline
$STD npm run build
# Static export lands in frontend/out; move it to static/
if [[ -d "${APP_DIR}/frontend/out" ]]; then
  mv "${APP_DIR}/frontend/out" "${APP_DIR}/static"
fi
msg_ok "Built frontend"

msg_info "Writing environment configuration"
cat >/opt/documind/.env <<'ENVEOF'
# DocuMind Environment Configuration
# Set your OpenRouter API key below after installation:
#   nano /opt/documind/.env  &&  systemctl restart documind
DOCUMIND_DATA_DIR=/opt/documind-data
OPENROUTER_API_KEY=
OPENROUTER_MODEL=google/gemini-3.1-pro-preview
PYTHONUNBUFFERED=1
ENVEOF
msg_ok "Wrote environment configuration"

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

# Record installed version (latest commit SHA on main)
RELEASE=$(curl -fsSL https://api.github.com/repos/AlexandrLebegue/Documind/releases/latest \
  | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null || true)
if [[ -z "$RELEASE" ]]; then
  RELEASE=$(curl -fsSL https://api.github.com/repos/AlexandrLebegue/Documind/commits/main \
    | grep '"sha"' | head -1 | sed -E 's/.*"([0-9a-f]{7})[0-9a-f]*.*/\1/' 2>/dev/null || true)
fi
echo "${RELEASE:-unknown}" >"${APP_DIR}/version.txt"

msg_info "Starting ${APP} service"
$STD systemctl start documind.service
msg_ok "Started ${APP} service"

motd_ssh
customize
