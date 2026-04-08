#!/bin/bash
# =============================================================================
# setup_cron_ct105.sh — One-time setup on Proxmox CT105
#
# Run this ONCE inside CT105 after deploying Documind:
#   bash setup_cron_ct105.sh
#
# What it does:
#   1. Installs cifs-utils (required to mount SMB/CIFS shares)
#   2. Creates /var/log/nas_sync.log
#   3. The cron schedule itself is managed automatically by Documind:
#      - On startup, Documind reads settings.json and installs/updates the cron entry
#      - When you change the NAS settings in the web UI and save, the cron is updated immediately
# =============================================================================

set -e

echo "=== DocuMind — CT105 one-time setup ==="

# 1. Install cifs-utils if missing
if ! dpkg -s cifs-utils &>/dev/null 2>&1; then
    echo "[1/2] Installing cifs-utils..."
    apt-get update -qq && apt-get install -y -qq cifs-utils
    echo "      cifs-utils installed"
else
    echo "[1/2] cifs-utils already installed — OK"
fi

# 2. Create log file with correct permissions
LOG=/var/log/nas_sync.log
touch "$LOG"
chmod 644 "$LOG"
echo "[2/2] Log file ready: $LOG"

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open the Documind web UI → Paramètres → Synchronisation NAS"
echo "  2. Enable the sync, fill in the NAS credentials and schedule"
echo "  3. Click 'Enregistrer' — the cron job is installed automatically"
echo "  4. Use 'Synchroniser maintenant' to test immediately"
echo ""
echo "To watch logs:  tail -f $LOG"
