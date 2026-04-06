#!/usr/bin/env bash
# =============================================================
# DocuMind — Proxmox LXC Installer (Standalone)
# =============================================================
# Creates a Debian 12 LXC container and installs DocuMind.
# Two install methods are available:
#
#   1) Docker  — DocuMind runs in Docker Compose inside the LXC
#                Easy updates: docker compose pull && docker compose up -d
#
#   2) Native  — Python venv + Node.js installed directly in the LXC
#                No Docker overhead, direct process access
#
# Run on your Proxmox host shell:
#   bash <(curl -fsSL https://raw.githubusercontent.com/AlexandrLebegue/Documind/main/ct/Documind.sh)
#
# Override defaults with env vars:
#   CTID=110 CT_RAM=4096 CT_DISK=20 bash <(curl ...)
# =============================================================

set -Eeuo pipefail
trap 'echo -e "\n\033[01;31mError on line ${LINENO} — installation aborted.\033[m"; exit 1' ERR

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
BL='\033[36m'; RD='\033[01;31m'; GN='\033[1;92m'; YW='\033[33m'; CL='\033[m'
CM="${GN}✓${CL}"; CROSS="${RD}✗${CL}"; INFO="${YW}ℹ${CL}"

msg_info()  { echo -e "   ${INFO}  ${1}"; }
msg_ok()    { echo -e "   ${CM}  ${1}"; }
msg_error() { echo -e "   ${CROSS}  \033[1;31m${1}\033[m"; }

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo -e "
${BL}  ____               __  __ _           _
 |  _ \  ___  ___ _   _|  \/  (_)_ __   __| |
 | | | |/ _ \/ __| | | | |\/| | | '_ \ / _\` |
 | |_| | (_) | (__| |_| | |  | | | | | | (_| |
 |____/ \___/ \___|\__,_|_|  |_|_|_| |_|\__,_|
${CL}
  ${YW}Proxmox LXC Installer${CL}"
echo ""

# ---------------------------------------------------------------------------
# Install method selection
# ---------------------------------------------------------------------------
echo -e "  ${BL}Select install method:${CL}"
echo -e ""
echo -e "  ${GN}1)${CL} ${YW}Docker${CL}   — DocuMind runs inside Docker Compose in the LXC"
echo -e "          Simpler, isolated, easy to update with \`docker compose pull\`"
echo -e ""
echo -e "  ${GN}2)${CL} ${YW}Native${CL}   — Python venv + Node.js installed directly in the LXC"
echo -e "          No Docker overhead, direct systemd service management"
echo -e ""
read -r -p "  Enter choice [1/2]: " INSTALL_METHOD_INPUT
case "$INSTALL_METHOD_INPUT" in
  1) INSTALL_METHOD="docker" ;;
  2) INSTALL_METHOD="native" ;;
  *) msg_error "Invalid choice — enter 1 or 2."; exit 1 ;;
esac
echo ""

# ---------------------------------------------------------------------------
# Default settings (override with environment variables before running)
# ---------------------------------------------------------------------------
CTID="${CTID:-$(pvesh get /cluster/nextid)}"
CT_HOSTNAME="${CT_HOSTNAME:-documind}"
CT_RAM="${CT_RAM:-2048}"
CT_CORES="${CT_CORES:-2}"
CT_DISK="${CT_DISK:-10}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
CONTAINER_STORAGE="${CONTAINER_STORAGE:-local-lvm}"
TEMPLATE="debian-12-standard_12.12-1_amd64.tar.zst"
GITHUB_RAW="https://raw.githubusercontent.com/AlexandrLebegue/Documind/main"

# ---------------------------------------------------------------------------
# Show settings and confirm
# ---------------------------------------------------------------------------
echo -e "  ${BL}Container settings${CL}"
echo -e "  ${YW}Install method  :${CL} ${INSTALL_METHOD}"
echo -e "  ${YW}Container ID    :${CL} ${CTID}"
echo -e "  ${YW}Hostname        :${CL} ${CT_HOSTNAME}"
echo -e "  ${YW}OS              :${CL} Debian 12"
echo -e "  ${YW}CPU Cores       :${CL} ${CT_CORES}"
echo -e "  ${YW}RAM             :${CL} ${CT_RAM} MiB"
echo -e "  ${YW}Disk            :${CL} ${CT_DISK} GiB"
echo -e "  ${YW}Bridge          :${CL} ${CT_BRIDGE}"
echo -e "  ${YW}Template store  :${CL} ${TEMPLATE_STORAGE}"
echo -e "  ${YW}Container store :${CL} ${CONTAINER_STORAGE}"
echo ""
read -r -p "  Proceed with these settings? [y/N]: " CONFIRM
[[ "${CONFIRM,,}" =~ ^(y|yes)$ ]] || { echo "Aborted."; exit 0; }
echo ""

# ---------------------------------------------------------------------------
# Download Debian 12 template if not already present
# ---------------------------------------------------------------------------
TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
if ! pveam list "${TEMPLATE_STORAGE}" 2>/dev/null | grep -q "${TEMPLATE}"; then
  msg_info "Downloading Debian 12 template"
  pveam update >/dev/null 2>&1 || true
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}" >/dev/null 2>&1
  msg_ok "Debian 12 template downloaded"
else
  msg_ok "Debian 12 template already present"
fi

# Docker-in-LXC requires nesting + keyctl features on an unprivileged container
if [[ "$INSTALL_METHOD" == "docker" ]]; then
  LXC_FEATURES="nesting=1,keyctl=1"
else
  LXC_FEATURES="nesting=1"
fi

# ---------------------------------------------------------------------------
# Create LXC container
# ---------------------------------------------------------------------------
msg_info "Creating LXC container ${CTID} (${CT_HOSTNAME})"
pct create "${CTID}" "${TEMPLATE_PATH}" \
  --hostname  "${CT_HOSTNAME}" \
  --cores     "${CT_CORES}" \
  --memory    "${CT_RAM}" \
  --rootfs    "${CONTAINER_STORAGE}:${CT_DISK}" \
  --net0      "name=eth0,bridge=${CT_BRIDGE},ip=dhcp" \
  --features  "${LXC_FEATURES}" \
  --unprivileged 1 \
  --onboot    1 \
  >/dev/null 2>&1
msg_ok "LXC container ${CTID} created"

# ---------------------------------------------------------------------------
# Start container and wait for DHCP address
# ---------------------------------------------------------------------------
msg_info "Starting container"
pct start "${CTID}"
sleep 4

IP=""
for i in $(seq 1 15); do
  IP=$(pct exec "${CTID}" -- ip -4 addr show eth0 \
    | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' 2>/dev/null || true)
  [[ -n "$IP" ]] && break
  sleep 2
done
msg_ok "Container running — IP: ${IP:-DHCP pending}"


# =============================================================================
#  BRANCH 1 — DOCKER INSTALL
# =============================================================================
if [[ "$INSTALL_METHOD" == "docker" ]]; then

  # -- Install Docker CE -------------------------------------------------------
  msg_info "Installing Docker CE inside the LXC"
  pct exec "${CTID}" -- bash -c "
    set -e
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker --now
  "
  msg_ok "Docker CE installed"

  # -- Clone full repo (docker compose build needs the source) ----------------
  msg_info "Cloning DocuMind repository"
  pct exec "${CTID}" -- bash -c "
    set -e
    apt-get install -y --no-install-recommends git -qq
    git clone --depth=1 https://github.com/AlexandrLebegue/Documind.git /opt/documind
    cp /opt/documind/.env.example /opt/documind/.env
  "
  msg_ok "Repository cloned to /opt/documind/"

  # -- Override the CIFS volume with a plain local volume ---------------------
  msg_info "Configuring local data volume (override NAS settings)"
  cat > /tmp/documind-compose-override.yml <<'OVERRIDE'
# Overrides the NAS/CIFS volume from docker-compose.yml with a plain local volume.
# Edit /opt/documind/docker-compose.yml to restore NAS storage.
volumes:
  documind-data:
    driver: local
OVERRIDE
  pct push "${CTID}" /tmp/documind-compose-override.yml /opt/documind/docker-compose.override.yml
  rm -f /tmp/documind-compose-override.yml
  msg_ok "docker-compose.override.yml written (uses local storage)"

  # -- Create systemd unit to manage the Compose stack ------------------------
  msg_info "Creating documind-docker.service"
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
  msg_ok "documind-docker.service created and enabled"

  # -- Build and start the stack ----------------------------------------------
  msg_info "Building and starting DocuMind (this may take 5–10 minutes on first run)"
  pct exec "${CTID}" -- bash -c "
    cd /opt/documind
    docker compose up -d --build 2>&1 | tail -5
  "

  # Health check
  sleep 8
  if pct exec "${CTID}" -- \
      docker compose -f /opt/documind/docker-compose.yml ps 2>/dev/null \
      | grep -q "running\|Up"; then
    msg_ok "DocuMind Docker container is running"
  else
    msg_error "Container may still be pulling/building. Check progress with:"
    echo -e "   pct exec ${CTID} -- docker compose -f /opt/documind/docker-compose.yml logs -f"
  fi


# =============================================================================
#  BRANCH 2 — NATIVE INSTALL
# =============================================================================
else

  msg_info "Running DocuMind native installer inside the LXC (~15 min)"
  pct exec "${CTID}" -- bash -c \
    "curl -fsSL '${GITHUB_RAW}/install/documind-install.sh' | bash"

  # Post-install health check
  sleep 5
  if pct exec "${CTID}" -- systemctl is-active --quiet documind.service 2>/dev/null; then
    msg_ok "DocuMind native service is running"
  else
    msg_error "Service may have failed. Check with:"
    echo -e "   pct exec ${CTID} -- journalctl -u documind --no-pager -n 40"
  fi

fi


# ---------------------------------------------------------------------------
# update_script — called when re-running the script on an existing container
# ---------------------------------------------------------------------------
function update_script() {
  echo -e "\n${BL}Update mode — checking for new version...${CL}\n"

  RELEASE=$(curl -fsSL https://api.github.com/repos/AlexandrLebegue/Documind/releases/latest \
    | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null || true)
  if [[ -z "$RELEASE" ]]; then
    RELEASE=$(curl -fsSL https://api.github.com/repos/AlexandrLebegue/Documind/commits/main \
      | grep '"sha"' | head -1 | sed -E 's/.*"([0-9a-f]{7})[0-9a-f]*.*/\1/' 2>/dev/null || true)
  fi

  CURRENT=""
  [[ -f /opt/documind/version.txt ]] && CURRENT=$(cat /opt/documind/version.txt)

  if [[ "$RELEASE" == "$CURRENT" && -n "$CURRENT" ]]; then
    msg_ok "Already at ${RELEASE} — no update needed."
    exit 0
  fi

  msg_info "Updating DocuMind from ${CURRENT:-unknown} to ${RELEASE}"

  # Detect active install method
  if [[ -f /opt/documind/docker-compose.yml ]] \
      && systemctl is-active --quiet documind-docker.service 2>/dev/null; then
    # Docker update
    msg_info "Docker mode — pulling latest image"
    cd /opt/documind
    docker compose pull --quiet
    docker compose up -d
    msg_ok "Docker stack updated to ${RELEASE}"
  else
    # Native update
    systemctl stop documind.service 2>/dev/null || true

    msg_info "Pulling latest code"
    cd /opt/documind
    git fetch --quiet origin main
    git reset --hard origin/main
    msg_ok "Code updated"

    msg_info "Updating core Python dependencies"
    /opt/documind/venv/bin/pip install --no-cache-dir -q \
      torch --index-url https://download.pytorch.org/whl/cpu
    /opt/documind/venv/bin/pip install --no-cache-dir -q \
      -r /opt/documind/requirements.txt
    msg_ok "Core Python dependencies updated"

    msg_info "Updating optional Python dependencies"
    if /opt/documind/venv/bin/pip install --no-cache-dir -q \
        -r /opt/documind/requirements-optional.txt 2>/dev/null; then
      msg_ok "Optional Python dependencies updated"
    else
      msg_info "Optional dependencies skipped (non-critical)"
    fi

    msg_info "Rebuilding frontend"
    cd /opt/documind/frontend
    npm ci --silent
    npm run build --silent
    rm -rf /opt/documind/static
    if [[ -d /opt/documind/frontend/out ]]; then
      cp -r /opt/documind/frontend/out /opt/documind/static
      msg_ok "Frontend rebuilt"
    else
      msg_error "Frontend build produced no output — static/ not updated"
    fi

    echo "$RELEASE" > /opt/documind/version.txt
    systemctl start documind.service
    msg_ok "DocuMind updated to ${RELEASE}"
  fi
}


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GN}  ══════════════════════════════════════════════════${CL}"
echo -e "${GN}  DocuMind successfully installed! (${INSTALL_METHOD} method)${CL}"
echo -e "${GN}  ══════════════════════════════════════════════════${CL}"
echo ""
echo -e "  ${BL}Web UI      :${CL}  http://${IP:-<container-ip>}:8000"
echo -e "  ${BL}API docs    :${CL}  http://${IP:-<container-ip>}:8000/docs"
echo ""
if [[ "$INSTALL_METHOD" == "docker" ]]; then
  echo -e "  ${YW}Set your OpenRouter API key:${CL}"
  echo -e "  pct exec ${CTID} -- nano /opt/documind/.env"
  echo -e "  pct exec ${CTID} -- docker compose -f /opt/documind/docker-compose.yml up -d"
else
  echo -e "  ${YW}Set your OpenRouter API key:${CL}"
  echo -e "  pct exec ${CTID} -- nano /opt/documind/.env"
  echo -e "  pct exec ${CTID} -- systemctl restart documind"
fi
echo ""
