#!/usr/bin/env bash
# Copyright (c) 2025 community-scripts ORG
# Author: AlexandrLebegue
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/AlexandrLebegue/Documind

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# App metadata
APP="Documind"
var_tags="document-management;ai;ocr"
var_cpu="2"
var_ram="2048"
var_disk="10"
var_os="debian"
var_version="12"
var_unprivileged="1"

# Header ASCII art
header_info "$APP"
color
variables
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/documind ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/AlexandrLebegue/Documind/releases/latest \
    | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

  if [[ -z "$RELEASE" ]]; then
    # Fallback: use latest commit SHA short hash on main
    RELEASE=$(curl -fsSL https://api.github.com/repos/AlexandrLebegue/Documind/commits/main \
      | grep '"sha"' | head -1 | sed -E 's/.*"([0-9a-f]{7})[0-9a-f]*.*/\1/')
  fi

  CURRENT=""
  if [[ -f /opt/documind/version.txt ]]; then
    CURRENT=$(cat /opt/documind/version.txt)
  fi

  if [[ "$RELEASE" == "$CURRENT" ]]; then
    msg_ok "No update required. ${APP} is already at ${RELEASE}."
    exit
  fi

  msg_info "Updating ${APP} from ${CURRENT:-unknown} to ${RELEASE}"

  # Stop service
  systemctl stop documind.service 2>/dev/null || true

  # Pull latest code
  msg_info "Pulling latest code"
  cd /opt/documind
  git fetch --quiet origin main
  git reset --hard origin/main
  msg_ok "Code updated"

  # Reinstall core Python dependencies
  msg_info "Updating core Python dependencies"
  /opt/documind/venv/bin/pip install --no-cache-dir -q \
    torch --index-url https://download.pytorch.org/whl/cpu
  /opt/documind/venv/bin/pip install --no-cache-dir -q \
    -r /opt/documind/requirements.txt
  msg_ok "Core Python dependencies updated"

  # Reinstall optional Python dependencies (allowed to fail)
  msg_info "Updating optional Python dependencies"
  if /opt/documind/venv/bin/pip install --no-cache-dir -q \
      -r /opt/documind/requirements-optional.txt 2>/dev/null; then
    msg_ok "Optional Python dependencies updated"
  else
    msg_info "Optional dependencies skipped (non-critical)"
  fi

  # Rebuild frontend
  msg_info "Rebuilding frontend"
  cd /opt/documind/frontend
  npm ci --prefer-offline --silent
  npm run build --silent
  rm -rf /opt/documind/static
  cp -r /opt/documind/frontend/out /opt/documind/static
  msg_ok "Frontend rebuilt"

  # Save new version
  echo "$RELEASE" >/opt/documind/version.txt

  # Restart service
  systemctl start documind.service
  msg_ok "Updated ${APP} to ${RELEASE}"
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
