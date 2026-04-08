"""Documind self-update: check GitHub for newer commits and apply them.

Two strategies depending on the runtime environment:
- **Git mode** (CT105 / bare metal install): ``git fetch`` + ``git pull`` + ``pip install``
- **Docker mode** (no .git directory): download the tarball from GitHub API,
  overwrite Python source files in-place, ``pip install``, then ``os.execv``.
"""

import logging
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

logger = logging.getLogger(__name__)

REPO = "AlexandrLebegue/Documind"
REPO_ROOT = Path(__file__).parent
_GIT_DIR = REPO_ROOT / ".git"


def _is_docker() -> bool:
    """Return True when running inside a Docker container (no .git dir)."""
    return not _GIT_DIR.exists()


# ---------------------------------------------------------------------------
# Shared: GitHub API helpers (no git required)
# ---------------------------------------------------------------------------

def _github_get(path: str) -> dict | list:
    """GET https://api.github.com{path} and return parsed JSON."""
    url = f"https://api.github.com{path}"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                               "User-Agent": "Documind-updater"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        import json
        return json.loads(resp.read())


# ---------------------------------------------------------------------------
# Git mode helpers
# ---------------------------------------------------------------------------

def _run_git(*args: str, timeout: int = 30) -> tuple[int, str, str]:
    result = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def check_for_update() -> dict:
    """Return update availability info.

    Works in both git and Docker modes.
    """
    if _is_docker():
        return _check_docker()
    return _check_git()


def apply_update() -> tuple[bool, str]:
    """Pull/download the latest code.

    Returns (success, message).
    """
    if _is_docker():
        return _apply_docker()
    return _apply_git()


def install_dependencies() -> tuple[bool, str]:
    """Run pip install -r requirements.txt."""
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


# ---------------------------------------------------------------------------
# Git mode implementation
# ---------------------------------------------------------------------------

def _check_git() -> dict:
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


def _apply_git() -> tuple[bool, str]:
    rc, out, err = _run_git("pull", "origin", "main", timeout=60)
    if rc != 0:
        logger.error("git pull failed: %s", err)
        return False, f"git pull a échoué : {err}"
    logger.info("git pull OK: %s", out)
    return True, out or "Pull effectué avec succès"


# ---------------------------------------------------------------------------
# Docker mode implementation
# ---------------------------------------------------------------------------

# Files that carry application version — used to read the local commit SHA
# embedded at build time (written by the Dockerfile build step below).
_LOCAL_SHA_FILE = REPO_ROOT / ".git_sha"

# Python source files that are overwritten during an in-place update.
_PY_SOURCES = [
    "main.py", "config.py", "database.py", "models.py", "pipeline.py",
    "ocr.py", "llm.py", "embeddings.py", "search.py", "prompts.py",
    "agent.py", "web_tools.py", "update.py", "nas_sync.py",
]


def _local_sha() -> str:
    """Return the commit SHA baked into the image, or 'unknown'."""
    if _LOCAL_SHA_FILE.exists():
        return _LOCAL_SHA_FILE.read_text().strip()[:8]
    return "unknown"


def _check_docker() -> dict:
    local = _local_sha()
    try:
        data = _github_get(f"/repos/{REPO}/commits/main")
        remote_sha: str = data["sha"]  # type: ignore[index]
        remote = remote_sha[:8]
        up_to_date = local != "unknown" and local == remote
        # Approximate behind_by via commit list
        behind_by = 0
        if not up_to_date and local != "unknown":
            try:
                commits = _github_get(
                    f"/repos/{REPO}/commits?sha=main&per_page=50"
                )
                shas = [c["sha"][:8] for c in commits]  # type: ignore[index]
                if local in shas:
                    behind_by = shas.index(local)
                else:
                    behind_by = len(shas)  # at least this many
            except Exception:
                behind_by = 1
        return {
            "up_to_date": up_to_date,
            "local_commit": local,
            "remote_commit": remote,
            "behind_by": behind_by,
            "error": None,
        }
    except Exception as exc:
        logger.warning("Docker update check failed: %s", exc)
        return {
            "up_to_date": True,
            "local_commit": local,
            "remote_commit": "?",
            "behind_by": 0,
            "error": f"Impossible de joindre GitHub : {exc}",
        }


def _apply_docker() -> tuple[bool, str]:
    """Download the main branch tarball from GitHub and overwrite .py sources."""
    url = f"https://api.github.com/repos/{REPO}/tarball/main"
    logger.info("Downloading source tarball from %s", url)

    try:
        req = urllib.request.Request(
            url,
            headers={"Accept": "application/vnd.github+json",
                     "User-Agent": "Documind-updater"},
        )
        with tempfile.TemporaryDirectory() as tmp:
            tar_path = os.path.join(tmp, "documind.tar.gz")

            # Stream download
            with urllib.request.urlopen(req, timeout=60) as resp, \
                 open(tar_path, "wb") as fh:
                shutil.copyfileobj(resp, fh)

            # Extract
            with tarfile.open(tar_path, "r:gz") as tar:
                tar.extractall(tmp)

            # Find the extracted directory (GitHub names it owner-repo-sha/)
            extracted_dirs = [
                d for d in Path(tmp).iterdir()
                if d.is_dir() and d.name != "__MACOSX"
            ]
            if not extracted_dirs:
                return False, "Archive vide ou corrompue"
            src_root = extracted_dirs[0]

            # Overwrite Python sources
            updated: list[str] = []
            for fname in _PY_SOURCES:
                src = src_root / fname
                dst = REPO_ROOT / fname
                if src.exists():
                    shutil.copy2(str(src), str(dst))
                    updated.append(fname)
                    logger.info("Updated: %s", fname)

            # Update requirements.txt
            req_src = src_root / "requirements.txt"
            if req_src.exists():
                shutil.copy2(str(req_src), str(REPO_ROOT / "requirements.txt"))
                updated.append("requirements.txt")

            # Record new SHA
            sha_src = src_root / ".git_sha"
            # GitHub tarball doesn't include .git — extract SHA from dir name
            # GitHub archive dir format: Owner-Repo-<sha7>/
            new_sha = src_root.name.split("-")[-1] if "-" in src_root.name else "unknown"
            _LOCAL_SHA_FILE.write_text(new_sha)

            logger.info("Docker update applied: %d files replaced", len(updated))
            return True, f"{len(updated)} fichiers mis à jour depuis GitHub"

    except Exception as exc:
        logger.error("Docker apply_update failed: %s", exc)
        return False, f"Échec du téléchargement : {exc}"
