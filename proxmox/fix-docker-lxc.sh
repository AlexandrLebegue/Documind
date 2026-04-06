#!/usr/bin/env bash
# =============================================================
# DocuMind — Docker LXC Quick-Fix Script
# Run on your Proxmox HOST shell to repair an existing container
# that was installed with the Docker method but won't serve :8000
#
# Usage:
#   CTID=105 bash fix-docker-lxc.sh
#   or just:
#   bash fix-docker-lxc.sh          (defaults to CTID=105)
# =============================================================

set -Eeuo pipefail

CTID="${CTID:-105}"

BL='\033[36m'; GN='\033[1;92m'; YW='\033[33m'; RD='\033[01;31m'; CL='\033[m'
msg_info()  { echo -e "  ${YW}ℹ${CL}  ${1}"; }
msg_ok()    { echo -e "  ${GN}✓${CL}  ${1}"; }
msg_error() { echo -e "  ${RD}✗${CL}  ${1}"; }

echo -e "\n${BL}  DocuMind — Docker LXC Fix (container ${CTID})${CL}\n"

# Confirm container exists and is running
if ! pct status "${CTID}" 2>/dev/null | grep -q "running"; then
  msg_info "Starting container ${CTID}"
  pct start "${CTID}"
  sleep 4
fi

# ---------------------------------------------------------------------------
# Step 1 — Install git (needed for clone)
# ---------------------------------------------------------------------------
msg_info "Installing git inside the container"
pct exec "${CTID}" -- apt-get install -y --no-install-recommends git -qq
msg_ok "git installed"

# ---------------------------------------------------------------------------
# Step 2 — Clone the full DocuMind repository
# (docker compose build needs Dockerfile + frontend/ + requirements.txt etc.)
# ---------------------------------------------------------------------------
msg_info "Cloning DocuMind repository to /opt/documind"
pct exec "${CTID}" -- bash -c "
  rm -rf /opt/documind
  git clone --depth=1 https://github.com/AlexandrLebegue/Documind.git /opt/documind
"
msg_ok "Repository cloned"

# ---------------------------------------------------------------------------
# Step 3 — Set up .env from example
# ---------------------------------------------------------------------------
msg_info "Creating .env configuration"
pct exec "${CTID}" -- bash -c "
  cp /opt/documind/.env.example /opt/documind/.env
  # Set data dir to a local path (not NAS)
  sed -i 's|DOCUMIND_DATA_DIR=.*|DOCUMIND_DATA_DIR=/data|' /opt/documind/.env
"
msg_ok ".env created at /opt/documind/.env"

# ---------------------------------------------------------------------------
# Step 4 — Override the CIFS/NAS volume with a plain local volume
# The default docker-compose.yml tries to mount a NAS share which fails
# in most environments. The override replaces it with a simple local volume.
# ---------------------------------------------------------------------------
msg_info "Writing docker-compose.override.yml (local volume, no NAS)"
cat > /tmp/documind-compose-override.yml <<'OVERRIDE'
# This override replaces the NAS/CIFS volume defined in docker-compose.yml
# with a plain local Docker volume. Delete this file to restore NAS mounting.
volumes:
  documind-data:
    driver: local
OVERRIDE
pct push "${CTID}" /tmp/documind-compose-override.yml /opt/documind/docker-compose.override.yml
rm -f /tmp/documind-compose-override.yml
msg_ok "docker-compose.override.yml written"

# ---------------------------------------------------------------------------
# Step 5 — Build and start the Docker Compose stack
# ---------------------------------------------------------------------------
msg_info "Building DocuMind Docker image (this takes ~10 minutes on first run)"
pct exec "${CTID}" -- bash -c "
  cd /opt/documind
  docker compose up -d --build
" && msg_ok "Docker Compose stack started" || {
  msg_error "docker compose failed — check logs:"
  echo -e "   pct exec ${CTID} -- docker compose -f /opt/documind/docker-compose.yml logs --tail=50"
  exit 1
}

# ---------------------------------------------------------------------------
# Step 6 — Update/create systemd service to auto-start on boot
# ---------------------------------------------------------------------------
msg_info "Updating documind-docker.service"
cat > /tmp/documind-docker.service <<'EOF'
[Unit]
Description=DocuMind Docker Compose
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/documind
ExecStartPre=-/usr/bin/docker compose pull --quiet
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
pct push "${CTID}" /tmp/documind-docker.service /etc/systemd/system/documind-docker.service
rm -f /tmp/documind-docker.service
pct exec "${CTID}" -- bash -c "systemctl daemon-reload && systemctl enable documind-docker.service"
msg_ok "documind-docker.service enabled"

# ---------------------------------------------------------------------------
# Step 7 — Wait and verify
# ---------------------------------------------------------------------------
msg_info "Waiting 30s for the container to start (embedding model downloads on first run)…"
sleep 30

if pct exec "${CTID}" -- docker compose \
    -f /opt/documind/docker-compose.yml ps 2>/dev/null | grep -qiE "running|up"; then
  msg_ok "DocuMind is running!"
else
  msg_info "Container may still be starting. Check with:"
  echo -e "   pct exec ${CTID} -- docker compose -f /opt/documind/docker-compose.yml ps"
  echo -e "   pct exec ${CTID} -- docker compose -f /opt/documind/docker-compose.yml logs -f"
fi

# Get IP
IP=$(pct exec "${CTID}" -- ip -4 addr show eth0 \
  | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' 2>/dev/null || echo "<container-ip>")

echo ""
echo -e "${GN}  ══════════════════════════════════════════${CL}"
echo -e "${GN}  DocuMind Docker fix complete!${CL}"
echo -e "${GN}  ══════════════════════════════════════════${CL}"
echo ""
echo -e "  ${BL}Web UI   :${CL}  http://${IP}:8000"
echo -e "  ${BL}API docs :${CL}  http://${IP}:8000/docs"
echo ""
echo -e "  ${YW}Set your OpenRouter API key:${CL}"
echo -e "  pct exec ${CTID} -- nano /opt/documind/.env"
echo -e "  pct exec ${CTID} -- docker compose -f /opt/documind/docker-compose.yml up -d"
echo ""
