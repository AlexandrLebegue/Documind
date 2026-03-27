#!/usr/bin/env bash
# ============================================================
# proxmox-export.sh — Export a Proxmox LXC container via vzdump
#
# A standalone script that backs up an existing LXC container
# using vzdump with configurable compression, mode, and output.
#
# Usage:
#   ./proxmox-export.sh --id <CTID> [OPTIONS]
#
# Requirements:
#   - Must run as root on a Proxmox VE host
#   - Commands: vzdump, pct
# ============================================================

set -Eeuo pipefail

# --------------------------------------------------
# Defaults
# --------------------------------------------------
CTID=""
DUMPDIR="/var/lib/vz/dump"
COMPRESS="zstd"
MODE="snapshot"
LOGFILE="/var/log/proxmox-export.log"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_START=""

# --------------------------------------------------
# Colors (disabled if not a terminal)
# --------------------------------------------------
if [[ -t 1 ]]; then
    readonly RED=$'\033[0;31m'
    readonly GREEN=$'\033[0;32m'
    readonly BLUE=$'\033[0;34m'
    readonly YELLOW=$'\033[1;33m'
    readonly BOLD=$'\033[1m'
    readonly NC=$'\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly BLUE=''
    readonly YELLOW=''
    readonly BOLD=''
    readonly NC=''
fi

# --------------------------------------------------
# Utility functions
# --------------------------------------------------

# Print a timestamped message to stdout and append to log file
log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local message="[${timestamp}] $1"
    echo -e "$message"
    echo -e "$message" >> "$LOGFILE" 2>/dev/null || true
}

msg_info() {
    log "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
    log "${GREEN}[OK]${NC} $1"
}

msg_warn() {
    log "${YELLOW}[WARN]${NC} $1"
}

msg_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Print usage information
usage() {
    cat <<EOF
${BOLD}Usage:${NC}
  ${SCRIPT_NAME} --id <CTID> [OPTIONS]

${BOLD}Description:${NC}
  Export (backup) a Proxmox LXC container using vzdump.
  Must be run as root on a Proxmox VE host.

${BOLD}Required:${NC}
  -i, --id <CTID>          Container ID to export (e.g., 100)

${BOLD}Options:${NC}
  -d, --dumpdir <PATH>     Output directory (default: /var/lib/vz/dump)
  -c, --compress <TYPE>    Compression type: zstd, gzip, lzo, none (default: zstd)
  -m, --mode <MODE>        Backup mode: snapshot, suspend, stop (default: snapshot)
  -l, --logfile <PATH>     Log file path (default: /var/log/proxmox-export.log)
  -h, --help               Show this help message

${BOLD}Examples:${NC}
  # Basic export with defaults (snapshot mode, zstd compression)
  ${SCRIPT_NAME} --id 100

  # Export to custom directory with gzip compression
  ${SCRIPT_NAME} --id 100 --dumpdir /mnt/backups --compress gzip

  # Stop container during backup for consistency
  ${SCRIPT_NAME} --id 100 --mode stop

  # Full example
  ${SCRIPT_NAME} --id 100 --dumpdir /mnt/nfs/backups --compress zstd --mode snapshot
EOF
}

# --------------------------------------------------
# Parse CLI arguments
# --------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--id)
                CTID="$2"
                shift 2
                ;;
            -d|--dumpdir)
                DUMPDIR="$2"
                shift 2
                ;;
            -c|--compress)
                COMPRESS="$2"
                shift 2
                ;;
            -m|--mode)
                MODE="$2"
                shift 2
                ;;
            -l|--logfile)
                LOGFILE="$2"
                shift 2
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
# Validation functions
# --------------------------------------------------

# Check the script is running as root
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        msg_error "This script must be run as root."
        echo "  Try: sudo ${SCRIPT_NAME} --id <CTID>"
        exit 1
    fi
}

# Check required commands are available
check_commands() {
    local missing=0
    for cmd in vzdump pct; do
        if ! command -v "$cmd" &>/dev/null; then
            msg_error "Required command '${cmd}' not found. Is this a Proxmox VE host?"
            missing=1
        fi
    done
    if [[ "$missing" -eq 1 ]]; then
        exit 1
    fi
}

# Validate all user inputs
validate_inputs() {
    # CTID is required
    if [[ -z "$CTID" ]]; then
        msg_error "Container ID (--id) is required."
        echo ""
        usage
        exit 1
    fi

    # CTID must be a positive integer
    if ! [[ "$CTID" =~ ^[0-9]+$ ]] || [[ "$CTID" -le 0 ]]; then
        msg_error "Container ID must be a positive integer, got: '${CTID}'"
        exit 1
    fi

    # Validate compression type
    case "$COMPRESS" in
        zstd|gzip|lzo|none) ;;
        *)
            msg_error "Invalid compression type: '${COMPRESS}'. Must be one of: zstd, gzip, lzo, none."
            exit 1
            ;;
    esac

    # Validate backup mode
    case "$MODE" in
        snapshot|suspend|stop) ;;
        *)
            msg_error "Invalid backup mode: '${MODE}'. Must be one of: snapshot, suspend, stop."
            exit 1
            ;;
    esac
}

# Check the container exists
check_container_exists() {
    msg_info "Checking container CT${CTID} exists..."
    if ! pct status "$CTID" &>/dev/null; then
        msg_error "Container CT${CTID} does not exist or is not accessible."
        echo "  Available containers:"
        pct list 2>/dev/null | tail -n +2 | awk '{print "    CT" $1 " — " $3}' || true
        exit 1
    fi

    local ct_status
    ct_status="$(pct status "$CTID" 2>/dev/null | awk '{print $2}')"
    msg_ok "Container CT${CTID} found (status: ${ct_status})"
}

# --------------------------------------------------
# Main export logic
# --------------------------------------------------
do_export() {
    # Ensure output directory exists
    if [[ ! -d "$DUMPDIR" ]]; then
        msg_info "Creating output directory: ${DUMPDIR}"
        mkdir -p "$DUMPDIR"
        msg_ok "Directory created."
    fi

    # Map compression type to vzdump --compress value
    local compress_flag="$COMPRESS"
    # vzdump uses 'zstd' for zstandard, which matches our input

    # Build the vzdump command
    local vzdump_cmd=(
        vzdump "$CTID"
        --mode "$MODE"
        --compress "$compress_flag"
        --dumpdir "$DUMPDIR"
        --notes-template "Exported by ${SCRIPT_NAME} on $(date '+%Y-%m-%d %H:%M:%S')"
    )

    # Log the command for reproducibility
    msg_info "Executing backup command:"
    log "  ${vzdump_cmd[*]}"

    echo ""
    msg_info "Starting export of CT${CTID} (mode=${MODE}, compress=${COMPRESS})..."
    echo "────────────────────────────────────────────────────────"

    SCRIPT_START="$(date +%s)"

    # Execute vzdump and capture output
    local vzdump_output
    local exit_code=0
    vzdump_output=$("${vzdump_cmd[@]}" 2>&1) || exit_code=$?

    echo "────────────────────────────────────────────────────────"

    # Log vzdump output
    if [[ -n "$vzdump_output" ]]; then
        log "$vzdump_output"
    fi

    local end_time
    end_time="$(date +%s)"
    local duration=$(( end_time - SCRIPT_START ))

    if [[ "$exit_code" -ne 0 ]]; then
        msg_error "vzdump failed with exit code ${exit_code}."
        msg_error "Check output above and log file: ${LOGFILE}"
        exit 1
    fi

    # Find the generated backup file (most recent in DUMPDIR matching our CTID)
    local backup_file
    backup_file=$(find "$DUMPDIR" -maxdepth 1 -name "vzdump-lxc-${CTID}-*" -type f -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn \
        | head -1 \
        | awk '{print $2}')

    echo ""
    msg_ok "Export completed successfully!"
    echo ""

    # Print summary
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Export Summary${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "  Container:    CT${CTID}"
    echo -e "  Mode:         ${MODE}"
    echo -e "  Compression:  ${COMPRESS}"

    if [[ -n "$backup_file" && -f "$backup_file" ]]; then
        local file_size
        file_size=$(du -h "$backup_file" | awk '{print $1}')
        echo -e "  Output file:  ${backup_file}"
        echo -e "  File size:    ${file_size}"
    else
        echo -e "  Output dir:   ${DUMPDIR}"
        msg_warn "Could not determine the exact output file."
    fi

    # Format duration
    local mins=$(( duration / 60 ))
    local secs=$(( duration % 60 ))
    echo -e "  Duration:     ${mins}m ${secs}s"
    echo -e "  Log file:     ${LOGFILE}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
}

# --------------------------------------------------
# Cleanup trap
# --------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -n "$CTID" ]]; then
        msg_error "Script exited with code ${exit_code}."
    fi
}
trap cleanup EXIT

# --------------------------------------------------
# Main entrypoint
# --------------------------------------------------
main() {
    parse_args "$@"
    check_root
    check_commands
    validate_inputs
    check_container_exists
    do_export
}

main "$@"
