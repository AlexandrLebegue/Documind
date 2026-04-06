#!/usr/bin/env bash
# ============================================================
# install-documind.sh — Deploy DocuMind as a Proxmox LXC container
#
# Creates an LXC container on a Proxmox VE host, installs all
# dependencies (Python 3.12, Node.js 20, Tesseract OCR), deploys
# DocuMind application code, builds the frontend, and sets up
# a systemd service.
#
# Usage:
#   ./install-documind.sh
#
# Requirements:
#   - Must run as root on a Proxmox VE host
#   - Internet access for downloading packages
# ============================================================

set -Eeuo pipefail

# --------------------------------------------------
# Configuration — adjust these as needed
# --------------------------------------------------
CTID="${CTID:-104}"
CT_HOSTNAME="${CT_HOSTNAME:-documind}"
TEMPLATE="debian-12-standard_12.12-1_amd64.tar.zst"
TEMPLATE_STORAGE="local"
CONTAINER_STORAGE="local-lvm"
DISK_SIZE="8"          # GB
MEMORY="2048"          # MB
CORES="2"
BRIDGE="vmbr0"
IP_CONFIG="dhcp"       # or e.g. "192.168.1.50/24,gw=192.168.1.1"
DOCUMIND_PORT="8000"
APP_DIR="/opt/documind"
DATA_DIR="/opt/documind-data"

# OpenRouter API settings
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
OPENROUTER_MODEL="${OPENROUTER_MODEL:-google/gemini-3.1-pro-preview}"

# --------------------------------------------------
# Colors
# --------------------------------------------------
if [[ -t 1 ]]; then
    readonly RD=$'\033[0;31m'
    readonly GN=$'\033[0;32m'
    readonly BL=$'\033[0;34m'
    readonly YW=$'\033[1;33m'
    readonly BD=$'\033[1m'
    readonly NC=$'\033[0m'
else
    readonly RD='' GN='' BL='' YW='' BD='' NC=''
fi

# --------------------------------------------------
# Utility functions
# --------------------------------------------------
msg_info()  { echo -e " ${BL}[INFO]${NC}  $1"; }
msg_ok()    { echo -e " ${GN}[OK]${NC}    $1"; }
msg_warn()  { echo -e " ${YW}[WARN]${NC}  $1"; }
msg_error() { echo -e " ${RD}[ERROR]${NC} $1"; }

header() {
    echo ""
    echo -e "${BL}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BL}║       ${BD}DocuMind — Proxmox LXC Installer${NC}${BL}         ║${NC}"
    echo -e "${BL}║       Document Management with AI               ║${NC}"
    echo -e "${BL}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --------------------------------------------------
# Pre-flight checks
# --------------------------------------------------
preflight() {
    msg_info "Running pre-flight checks..."

    if [[ "$(id -u)" -ne 0 ]]; then
        msg_error "This script must be run as root on a Proxmox VE host."
        exit 1
    fi

    for cmd in pct pveam pvesm; do
        if ! command -v "$cmd" &>/dev/null; then
            msg_error "Command '${cmd}' not found. Is this a Proxmox VE host?"
            exit 1
        fi
    done

    # Check if CTID is already in use
    if pct status "$CTID" &>/dev/null; then
        msg_error "Container CT${CTID} already exists. Change CTID or remove existing container."
        echo "  Current containers:"
        pct list
        exit 1
    fi

    msg_ok "Pre-flight checks passed."
}

# --------------------------------------------------
# Ask for OpenRouter API key if not set
# --------------------------------------------------
ask_api_key() {
    if [[ -z "$OPENROUTER_API_KEY" ]]; then
        echo ""
        msg_warn "OPENROUTER_API_KEY is not set."
        echo -e "  DocuMind needs an OpenRouter API key for AI features."
        echo -e "  Get one at: ${BD}https://openrouter.ai/keys${NC}"
        echo ""
        read -rp "  Enter your OpenRouter API key (or press Enter to skip): " OPENROUTER_API_KEY
        echo ""
        if [[ -z "$OPENROUTER_API_KEY" ]]; then
            msg_warn "No API key provided. You can set it later in ${APP_DIR}/.env"
        fi
    fi
}

# --------------------------------------------------
# Download container template
# --------------------------------------------------
download_template() {
    local template_path="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

    if pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
        msg_ok "Template already downloaded: ${TEMPLATE}"
    else
        msg_info "Downloading template: ${TEMPLATE}..."
        pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
        msg_ok "Template downloaded."
    fi
}

# --------------------------------------------------
# Create the LXC container
# --------------------------------------------------
create_container() {
    msg_info "Creating LXC container CT${CTID} (${CT_HOSTNAME})..."

    local net_config
    if [[ "$IP_CONFIG" == "dhcp" ]]; then
        net_config="name=eth0,bridge=${BRIDGE},ip=dhcp"
    else
        net_config="name=eth0,bridge=${BRIDGE},ip=${IP_CONFIG}"
    fi

    pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
        --hostname "$CT_HOSTNAME" \
        --storage "$CONTAINER_STORAGE" \
        --rootfs "${CONTAINER_STORAGE}:${DISK_SIZE}" \
        --memory "$MEMORY" \
        --cores "$CORES" \
        --net0 "$net_config" \
        --unprivileged 1 \
        --features nesting=1 \
        --onboot 1 \
        --start 0 \
        --description "DocuMind — Document Management with AI"

    msg_ok "Container CT${CTID} created."
}

# --------------------------------------------------
# Start the container
# --------------------------------------------------
start_container() {
    msg_info "Starting container CT${CTID}..."
    pct start "$CTID"
    # Wait for container to be fully up
    sleep 3

    # Wait for network
    msg_info "Waiting for network..."
    local retries=0
    while ! pct exec "$CTID" -- ping -c 1 -W 2 deb.debian.org &>/dev/null; do
        retries=$((retries + 1))
        if [[ $retries -ge 15 ]]; then
            msg_error "Container has no network after 30s. Check bridge/DHCP config."
            exit 1
        fi
        sleep 2
    done
    msg_ok "Container started and has network connectivity."
}

# --------------------------------------------------
# Install system dependencies inside the container
# --------------------------------------------------
install_dependencies() {
    msg_info "Updating package lists..."
    pct exec "$CTID" -- bash -c "apt-get update -qq"
    msg_ok "Package lists updated."

    msg_info "Installing system packages (Python, Node.js, Tesseract, git)..."
    pct exec "$CTID" -- bash -c "
        apt-get install -y --no-install-recommends \
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
    "
    msg_ok "System packages installed."

    # Install Node.js 20 via NodeSource
    msg_info "Installing Node.js 20..."
    pct exec "$CTID" -- bash -c "
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
        apt-get install -y nodejs
    "
    msg_ok "Node.js $(pct exec "$CTID" -- node --version 2>/dev/null) installed."
}

# --------------------------------------------------
# Deploy DocuMind application code
# --------------------------------------------------
deploy_application() {
    msg_info "Creating application directories..."
    pct exec "$CTID" -- bash -c "mkdir -p ${APP_DIR} ${DATA_DIR}/originals ${DATA_DIR}/models"

    # Strategy: use pre-staged files from /tmp/documind-install if available,
    # otherwise try to find files relative to this script
    local source_dir=""

    if [[ -d "/tmp/documind-install" && -f "/tmp/documind-install/main.py" ]]; then
        source_dir="/tmp/documind-install"
        msg_info "Using pre-staged files from ${source_dir}"
    else
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "${script_dir}/../main.py" ]]; then
            source_dir="${script_dir}/.."
            msg_info "Using project files from ${source_dir}"
        else
            msg_error "Cannot find DocuMind source files."
            echo "  Either place files in /tmp/documind-install/ or run this"
            echo "  script from the proxmox/ directory inside the project."
            exit 1
        fi
    fi

    msg_info "Copying application files into container..."

    # Python application files
    for f in main.py config.py database.py models.py pipeline.py ocr.py llm.py embeddings.py search.py prompts.py requirements.txt; do
        if [[ -f "${source_dir}/${f}" ]]; then
            pct push "$CTID" "${source_dir}/${f}" "${APP_DIR}/${f}"
        else
            msg_warn "File not found: ${f} — skipping"
        fi
    done

    # Frontend directory
    if [[ -d "${source_dir}/frontend" ]]; then
        msg_info "Packaging frontend..."
        tar -czf /tmp/documind-frontend.tar.gz -C "${source_dir}" \
            --exclude='node_modules' --exclude='.next' --exclude='out' frontend/
        pct push "$CTID" /tmp/documind-frontend.tar.gz /tmp/documind-frontend.tar.gz
        pct exec "$CTID" -- bash -c "cd ${APP_DIR} && tar -xzf /tmp/documind-frontend.tar.gz && rm /tmp/documind-frontend.tar.gz"
        rm -f /tmp/documind-frontend.tar.gz
        msg_ok "Frontend files copied."
    else
        msg_warn "Frontend directory not found — skipping frontend build"
    fi

    msg_ok "Application files deployed to ${APP_DIR}"
}

# --------------------------------------------------
# Install Python dependencies
# --------------------------------------------------
install_python_deps() {
    msg_info "Creating Python virtual environment..."
    pct exec "$CTID" -- bash -c "python3 -m venv ${APP_DIR}/venv"

    msg_info "Installing CPU-only PyTorch (this may take a few minutes)..."
    pct exec "$CTID" -- bash -c "
        ${APP_DIR}/venv/bin/pip install --no-cache-dir \
            torch --index-url https://download.pytorch.org/whl/cpu
    "
    msg_ok "PyTorch (CPU) installed."

    msg_info "Installing Python dependencies from requirements.txt..."
    pct exec "$CTID" -- bash -c "
        ${APP_DIR}/venv/bin/pip install --no-cache-dir \
            -r ${APP_DIR}/requirements.txt
    "
    msg_ok "Python dependencies installed."
}

# --------------------------------------------------
# Build the frontend
# --------------------------------------------------
build_frontend() {
    if pct exec "$CTID" -- test -d "${APP_DIR}/frontend"; then
        msg_info "Installing frontend dependencies (npm ci)..."
        pct exec "$CTID" -- bash -c "cd ${APP_DIR}/frontend && npm ci --prefer-offline"
        msg_ok "Frontend dependencies installed."

        msg_info "Building frontend (npm run build)..."
        pct exec "$CTID" -- bash -c "cd ${APP_DIR}/frontend && npm run build"
        msg_ok "Frontend built."

        # Move build output to static directory
        msg_info "Moving frontend build to static directory..."
        pct exec "$CTID" -- bash -c "
            if [[ -d ${APP_DIR}/frontend/out ]]; then
                mv ${APP_DIR}/frontend/out ${APP_DIR}/static
            elif [[ -d ${APP_DIR}/frontend/.next ]]; then
                mv ${APP_DIR}/frontend/.next ${APP_DIR}/static
            fi
        "
        msg_ok "Frontend deployed to ${APP_DIR}/static"
    else
        msg_warn "No frontend directory found — skipping frontend build"
    fi
}

# --------------------------------------------------
# Create environment file
# --------------------------------------------------
create_env_file() {
    msg_info "Creating environment configuration..."
    cat > /tmp/documind.env <<ENVEOF
# DocuMind Environment Configuration
DOCUMIND_DATA_DIR=${DATA_DIR}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
OPENROUTER_MODEL=${OPENROUTER_MODEL}
PYTHONUNBUFFERED=1
ENVEOF
    pct push "$CTID" /tmp/documind.env "${APP_DIR}/.env"
    rm -f /tmp/documind.env
    msg_ok "Environment file created at ${APP_DIR}/.env"
}

# --------------------------------------------------
# Create systemd service
# --------------------------------------------------
create_service() {
    msg_info "Creating systemd service..."
    cat > /tmp/documind.service <<SVCEOF
[Unit]
Description=DocuMind — Document Management with AI
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/venv/bin/python main.py --skip-build
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF
    pct push "$CTID" /tmp/documind.service /etc/systemd/system/documind.service
    rm -f /tmp/documind.service
    pct exec "$CTID" -- bash -c "systemctl daemon-reload && systemctl enable documind.service"
    msg_ok "Systemd service created and enabled."
}

# --------------------------------------------------
# Start DocuMind service
# --------------------------------------------------
start_service() {
    msg_info "Starting DocuMind service..."
    pct exec "$CTID" -- bash -c "systemctl start documind.service"
    sleep 3

    # Check if running
    if pct exec "$CTID" -- bash -c "systemctl is-active documind.service" | grep -q "active"; then
        msg_ok "DocuMind service is running!"
    else
        msg_warn "Service may not have started yet. Check with:"
        echo "    pct exec ${CTID} -- journalctl -u documind -f"
    fi
}

# --------------------------------------------------
# Print summary
# --------------------------------------------------
print_summary() {
    # Get container IP
    local ct_ip
    ct_ip=$(pct exec "$CTID" -- bash -c "hostname -I 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "unknown")

    echo ""
    echo -e "${GN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GN}║       ${BD}DocuMind Installation Complete!${NC}${GN}            ║${NC}"
    echo -e "${GN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BD}Container:${NC}    CT${CTID} (${CT_HOSTNAME})"
    echo -e "  ${BD}IP Address:${NC}   ${ct_ip}"
    echo -e "  ${BD}Web UI:${NC}       ${BD}http://${ct_ip}:${DOCUMIND_PORT}${NC}"
    echo -e "  ${BD}App Dir:${NC}      ${APP_DIR}"
    echo -e "  ${BD}Data Dir:${NC}     ${DATA_DIR}"
    echo -e "  ${BD}Service:${NC}      documind.service"
    echo ""
    echo -e "  ${BD}Useful commands:${NC}"
    echo "    pct exec ${CTID} -- systemctl status documind"
    echo "    pct exec ${CTID} -- journalctl -u documind -f"
    echo "    pct exec ${CTID} -- systemctl restart documind"
    echo ""
    if [[ -z "$OPENROUTER_API_KEY" ]]; then
        echo -e "  ${YW}⚠ Remember to set your OpenRouter API key:${NC}"
        echo "    pct exec ${CTID} -- nano ${APP_DIR}/.env"
        echo "    pct exec ${CTID} -- systemctl restart documind"
        echo ""
    fi
}

# --------------------------------------------------
# Cleanup trap
# --------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        msg_error "Installation failed (exit code ${exit_code})."
        echo "  The container CT${CTID} may still exist. To remove it:"
        echo "    pct stop ${CTID} && pct destroy ${CTID}"
    fi
    rm -f /tmp/documind-frontend.tar.gz 2>/dev/null || true
}
trap cleanup EXIT

# --------------------------------------------------
# Main
# --------------------------------------------------
main() {
    header
    preflight
    ask_api_key
    download_template
    create_container
    start_container
    install_dependencies
    deploy_application
    install_python_deps
    build_frontend
    create_env_file
    create_service
    start_service
    print_summary
}

main "$@"
