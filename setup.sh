#!/bin/bash
# =============================================================================
# DocuMind — Setup Script
# Creates required directories and verifies configuration.
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# Environment variables:
#   DOCUMIND_DATA_DIR    — Base data directory (default: ~/documind)
#   OPENROUTER_API_KEY   — OpenRouter API key (required for LLM features)
# =============================================================================

set -e

# ---------------------------------------------------------------------------
# Colors for terminal output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════╗"
echo "║           DocuMind Setup                 ║"
echo "║   Document Management with AI            ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ---------------------------------------------------------------------------
# Determine data directory
# ---------------------------------------------------------------------------
DATA_DIR="${DOCUMIND_DATA_DIR:-$HOME/documind}"

# ---------------------------------------------------------------------------
# Create directories
# ---------------------------------------------------------------------------
echo -e "${YELLOW}→ Creating data directories...${NC}"
mkdir -p "$DATA_DIR/originals"
mkdir -p "$DATA_DIR/models"
echo -e "${GREEN}✓ Directories created at $DATA_DIR${NC}"

# ---------------------------------------------------------------------------
# Check OpenRouter API key
# ---------------------------------------------------------------------------
echo ""
if [ -n "$OPENROUTER_API_KEY" ]; then
    echo -e "${GREEN}✓ OPENROUTER_API_KEY is set${NC}"
else
    echo -e "${YELLOW}⚠ OPENROUTER_API_KEY is not set in environment.${NC}"
    echo -e "${YELLOW}  The default key from config.py will be used.${NC}"
    echo -e "${YELLOW}  To use a custom key, set the environment variable:${NC}"
    echo ""
    echo "    export OPENROUTER_API_KEY=sk-or-v1-your-key-here"
    echo ""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Setup Complete!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}To start DocuMind:${NC}"
echo ""
echo "  With Docker:"
echo "    docker compose up -d"
echo ""
echo "  Without Docker:"
echo "    pip install -r requirements.txt"
echo "    python main.py"
echo ""
echo -e "${BLUE}LLM powered by OpenRouter (no local model download needed).${NC}"
