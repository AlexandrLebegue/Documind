#!/usr/bin/env bash
# ============================================================
# update-documind.sh — Push code updates to an existing
#                       DocuMind Proxmox LXC container
#
# Pushes updated Python backend + Next.js frontend files,
# optionally reinstalls dependencies, rebuilds the frontend,
# and restarts the systemd service.
#
# Usage:
#   ./update-documind.sh [OPTIONS]
#
# Requirements:
#   - Must run as root on a Proxmox VE host
#   - Target container must already exist and be running
#   - Source files in /tmp/documind-install/ or alongside script
# ============================================================

set -Eeuo pipefail

# --------------------------------------------------
# Configuration — must match install-documind.sh
# --------------------------------------------------
CTID="${CTID:-104}"
APP_DIR="/opt/documind"
DATA_DIR="/opt/documind-data"

# --------------------------------------------------
# Defaults for flags
# --------------------------------------------------
SKIP_FRONTEND=false
SKIP_DEPS=false

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
    echo -e "${BL}║       ${BD}DocuMind — Proxmox LXC Updater${NC}${BL}            ║${NC}"
    echo -e "${BL}║       Push code updates to container             ║${NC}"
    echo -e "${BL}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

usage() {
    cat <<EOF
${BD}Usage:${NC}
  $(basename "$0") [OPTIONS]

${BD}Description:${NC}
  Push updated DocuMind code to an existing Proxmox LXC container,
  rebuild the frontend, and restart the service. Data in
  ${DATA_DIR} is never touched.

${BD}Options:${NC}
  --id <CTID>         Container ID (default: 104)
  --skip-frontend     Skip frontend rebuild (backend-only update)
  --skip-deps         Skip pip install (requirements.txt unchanged)
  --full              Full update: deps + frontend (this is the default)
  -h, --help          Show this help message

${BD}Examples:${NC}
  # Full update (push code, install deps, rebuild frontend)
  $(basename "$0")

  # Quick backend-only update
  $(basename "$0") --skip-frontend --skip-deps

  # Update code + frontend, but skip pip install
  $(basename "$0") --skip-deps

  # Target a different container
  $(basename "$0") --id 105

${BD}Source files:${NC}
  The script looks for DocuMind source files in this order:
    1. /tmp/documind-install/  (pre-staged)
    2. Relative to this script (../main.py)
EOF
}

# --------------------------------------------------
# Parse CLI arguments
# --------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                CTID="$2"
                shift 2
                ;;
            --skip-frontend)
                SKIP_FRONTEND=true
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --full)
                SKIP_FRONTEND=false
                SKIP_DEPS=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                msg_error "Unknown option: $1"
                echo ""
                usage
                exit 1
                ;;
        esac
    done
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

    for cmd in pct pveam; do
        if ! command -v "$cmd" &>/dev/null; then
            msg_error "Command '${cmd}' not found. Is this a Proxmox VE host?"
            exit 1
        fi
    done

    # Check container exists
    if ! pct status "$CTID" &>/dev/null; then
        msg_error "Container CT${CTID} does not exist. Run install-documind.sh first."
        exit 1
    fi

    # Check container is running
    local status
    status=$(pct status "$CTID" 2>/dev/null | awk '{print $2}')
    if [[ "$status" != "running" ]]; then
        msg_error "Container CT${CTID} is not running (status: ${status})."
        echo "  Start it with: pct start ${CTID}"
        exit 1
    fi

    # Check app dir exists inside container
    if ! pct exec "$CTID" -- test -d "$APP_DIR"; then
        msg_error "${APP_DIR} does not exist in CT${CTID}. Was DocuMind installed correctly?"
        exit 1
    fi

    msg_ok "Pre-flight checks passed (CT${CTID} is running)."
}

# --------------------------------------------------
# Locate source files
# --------------------------------------------------
find_source() {
    if [[ -d "/tmp/documind-install" && -f "/tmp/documind-install/main.py" ]]; then
        SOURCE_DIR="/tmp/documind-install"
        msg_info "Using pre-staged files from ${SOURCE_DIR}"
    else
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "${script_dir}/../main.py" ]]; then
            SOURCE_DIR="${script_dir}/.."
            msg_info "Using project files from ${SOURCE_DIR}"
        else
            msg_error "Cannot find DocuMind source files."
            echo "  Either place files in /tmp/documind-install/ or run this"
            echo "  script from the proxmox/ directory inside the project."
            exit 1
        fi
    fi
}

# --------------------------------------------------
# Stop the DocuMind service
# --------------------------------------------------
stop_service() {
    msg_info "Stopping documind service..."
    pct exec "$CTID" -- bash -c "systemctl stop documind.service 2>/dev/null || true"
    sleep 1
    msg_ok "Service stopped."
}

# --------------------------------------------------
# Push updated Python backend files
# --------------------------------------------------
push_backend() {
    msg_info "Pushing backend files to CT${CTID}:${APP_DIR}/..."

    local pushed=0
    for f in main.py config.py database.py models.py pipeline.py ocr.py llm.py embeddings.py search.py prompts.py agent.py web_tools.py update.py requirements.txt; do
        if [[ -f "${SOURCE_DIR}/${f}" ]]; then
            pct push "$CTID" "${SOURCE_DIR}/${f}" "${APP_DIR}/${f}"
            pushed=$((pushed + 1))
        else
            msg_warn "File not found: ${f} — skipping"
        fi
    done

    msg_ok "${pushed} backend files pushed."
}

# --------------------------------------------------
# Push updated frontend files
# --------------------------------------------------
push_frontend() {
    if [[ "$SKIP_FRONTEND" == true ]]; then
        msg_info "Skipping frontend push (--skip-frontend)"
        return
    fi

    if [[ ! -d "${SOURCE_DIR}/frontend" ]]; then
        msg_warn "No frontend directory found in source — skipping"
        return
    fi

    msg_info "Packaging frontend files..."
    tar -czf /tmp/documind-frontend-update.tar.gz -C "${SOURCE_DIR}" \
        --exclude='node_modules' --exclude='.next' --exclude='out' frontend/

    msg_info "Pushing frontend to CT${CTID}..."
    pct push "$CTID" /tmp/documind-frontend-update.tar.gz /tmp/documind-frontend-update.tar.gz

    # Remove old frontend source (but preserve node_modules to speed up npm ci)
    pct exec "$CTID" -- bash -c "
        if [[ -d ${APP_DIR}/frontend/node_modules ]]; then
            mv ${APP_DIR}/frontend/node_modules /tmp/documind-node-modules-bak
        fi
        rm -rf ${APP_DIR}/frontend
        cd ${APP_DIR} && tar -xzf /tmp/documind-frontend-update.tar.gz
        if [[ -d /tmp/documind-node-modules-bak ]]; then
            mv /tmp/documind-node-modules-bak ${APP_DIR}/frontend/node_modules
        fi
        rm -f /tmp/documind-frontend-update.tar.gz
    "

    rm -f /tmp/documind-frontend-update.tar.gz
    msg_ok "Frontend files pushed."
}

# --------------------------------------------------
# Install Python dependencies
# --------------------------------------------------
install_python_deps() {
    if [[ "$SKIP_DEPS" == true ]]; then
        msg_info "Skipping pip install (--skip-deps)"
        return
    fi

    msg_info "Installing Python dependencies..."
    pct exec "$CTID" -- bash -c "
        ${APP_DIR}/venv/bin/pip install --no-cache-dir \
            -r ${APP_DIR}/requirements.txt 2>&1 | tail -5
    "
    msg_ok "Python dependencies installed."
}

# --------------------------------------------------
# Rebuild the frontend
# --------------------------------------------------
build_frontend() {
    if [[ "$SKIP_FRONTEND" == true ]]; then
        msg_info "Skipping frontend build (--skip-frontend)"
        return
    fi

    if ! pct exec "$CTID" -- test -d "${APP_DIR}/frontend"; then
        msg_warn "No frontend directory in container — skipping build"
        return
    fi

    msg_info "Installing frontend dependencies (npm ci)..."
    pct exec "$CTID" -- bash -c "cd ${APP_DIR}/frontend && npm ci --prefer-offline 2>&1 | tail -3"
    msg_ok "Frontend dependencies installed."

    msg_info "Building frontend (npm run build)..."
    pct exec "$CTID" -- bash -c "cd ${APP_DIR}/frontend && npm run build 2>&1 | tail -5"
    msg_ok "Frontend built."

    # Copy build output to static directory
    msg_info "Deploying frontend build to static/..."
    pct exec "$CTID" -- bash -c "
        rm -rf ${APP_DIR}/static
        if [[ -d ${APP_DIR}/frontend/out ]]; then
            cp -r ${APP_DIR}/frontend/out ${APP_DIR}/static
        else
            echo 'WARNING: frontend/out not found after build'
        fi
    "
    msg_ok "Frontend deployed to ${APP_DIR}/static"
}

# --------------------------------------------------
# Start the DocuMind service
# --------------------------------------------------
start_service() {
    msg_info "Starting documind service..."
    pct exec "$CTID" -- bash -c "systemctl daemon-reload && systemctl start documind.service"
    sleep 3

    if pct exec "$CTID" -- bash -c "systemctl is-active documind.service" | grep -q "active"; then
        msg_ok "DocuMind service is running!"
    else
        msg_warn "Service may not have started correctly. Check with:"
        echo "    pct exec ${CTID} -- journalctl -u documind -f"
    fi
}

# --------------------------------------------------
# Print summary
# --------------------------------------------------
print_summary() {
    local ct_ip
    ct_ip=$(pct exec "$CTID" -- bash -c "hostname -I 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "unknown")

    echo ""
    echo -e "${GN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GN}║       ${BD}DocuMind Update Complete!${NC}${GN}                  ║${NC}"
    echo -e "${GN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BD}Container:${NC}      CT${CTID}"
    echo -e "  ${BD}IP Address:${NC}     ${ct_ip}"
    echo -e "  ${BD}Web UI:${NC}         ${BD}http://${ct_ip}:8000${NC}"
    echo -e "  ${BD}Backend:${NC}        updated"
    if [[ "$SKIP_FRONTEND" == true ]]; then
        echo -e "  ${BD}Frontend:${NC}       ${YW}skipped${NC}"
    else
        echo -e "  ${BD}Frontend:${NC}       rebuilt"
    fi
    if [[ "$SKIP_DEPS" == true ]]; then
        echo -e "  ${BD}Python deps:${NC}    ${YW}skipped${NC}"
    else
        echo -e "  ${BD}Python deps:${NC}    refreshed"
    fi
    echo ""
    echo -e "  ${BD}Useful commands:${NC}"
    echo "    pct exec ${CTID} -- systemctl status documind"
    echo "    pct exec ${CTID} -- journalctl -u documind -f"
    echo "    pct exec ${CTID} -- systemctl restart documind"
    echo ""
}

# --------------------------------------------------
# Cleanup trap
# --------------------------------------------------
cleanup() {
    rm -f /tmp/documind-frontend-update.tar.gz 2>/dev/null || true
}
trap cleanup EXIT

# --------------------------------------------------
# Main
# --------------------------------------------------
main() {
    parse_args "$@"
    header
    preflight
    find_source
    stop_service
    push_backend
    push_frontend
    install_python_deps
    build_frontend
    start_service
    print_summary
}

main "$@"
