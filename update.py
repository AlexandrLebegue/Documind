"""Documind self-update: check GitHub for newer commits and apply them."""

import logging
import os
import subprocess
import sys
from pathlib import Path

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).parent


def _run_git(*args: str, timeout: int = 30) -> tuple[int, str, str]:
    """Run a git command in the repo root.

    Returns:
        (returncode, stdout, stderr) — all strings are stripped.
    """
    result = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def check_for_update() -> dict:
    """Fetch origin/main and compare with local HEAD.

    Returns a dict with:
        up_to_date   bool   — True when local == remote
        local_commit str    — short SHA of HEAD
        remote_commit str   — short SHA of origin/main
        behind_by    int    — number of commits behind remote
        error        str|None — non-None when git commands failed
    """
    rc, _, err = _run_git("fetch", "origin", "main", "--quiet")
    if rc != 0:
        logger.warning("git fetch failed: %s", err)
        return {"up_to_date": True, "local_commit": "?", "remote_commit": "?",
                "behind_by": 0, "error": f"git fetch a échoué : {err}"}

    rc, local_hash, _ = _run_git("rev-parse", "HEAD")
    if rc != 0:
        return {"up_to_date": True, "local_commit": "?", "remote_commit": "?",
                "behind_by": 0, "error": "Impossible de lire le commit local"}

    rc, remote_hash, _ = _run_git("rev-parse", "origin/main")
    if rc != 0:
        return {"up_to_date": True, "local_commit": local_hash[:8], "remote_commit": "?",
                "behind_by": 0, "error": "Impossible de lire origin/main"}

    up_to_date = local_hash == remote_hash
    behind_by = 0

    if not up_to_date:
        rc, count_str, _ = _run_git("rev-list", "--count", f"{local_hash}..origin/main")
        if rc == 0:
            try:
                behind_by = int(count_str)
            except ValueError:
                pass

    return {
        "up_to_date": up_to_date,
        "local_commit": local_hash[:8],
        "remote_commit": remote_hash[:8],
        "behind_by": behind_by,
        "error": None,
    }


def apply_update() -> tuple[bool, str]:
    """Run git pull origin main.

    Returns:
        (success, message)
    """
    rc, out, err = _run_git("pull", "origin", "main", timeout=60)
    if rc != 0:
        logger.error("git pull failed: %s", err)
        return False, f"git pull a échoué : {err}"
    logger.info("git pull OK: %s", out)
    return True, out or "Pull effectué avec succès"


def install_dependencies() -> tuple[bool, str]:
    """Run pip install -r requirements.txt.

    Returns:
        (success, message)
    """
    req_file = REPO_ROOT / "requirements.txt"
    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-r", str(req_file), "--quiet"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode != 0:
        logger.error("pip install failed: %s", result.stderr)
        return False, result.stderr or "pip install a échoué"
    logger.info("pip install OK")
    return True, "Dépendances installées"


def restart_server() -> None:
    """Replace the current process with a fresh instance (os.execv)."""
    logger.info("Restarting server: %s %s", sys.executable, sys.argv)
    os.execv(sys.executable, [sys.executable] + sys.argv)
