"""NAS synchronization module — mounts a CIFS/SMB share and imports new documents.

This module is designed to run on the Proxmox CT105 container where Documind lives.
It mounts \\192.168.1.100\NAS_Commun_Vol2\DOCUMIND\originals via CIFS, then uploads
any files not already known to Documind through the internal API.

Usage (inside CT105):
    python nas_sync.py          # one-shot sync
    Called internally by POST /api/sync/nas

Crontab (CT105) — added automatically by setup_cron_ct105.sh:
    0 7 * * * curl -s -X POST http://localhost:8000/api/sync/nas >> /var/log/nas_sync.log 2>&1
"""

import logging
import os
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Optional

import httpx

from config import ORIGINALS_DIR, SUPPORTED_EXTENSIONS, load_settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# NAS settings — saved settings.json > environment variables > defaults
# ---------------------------------------------------------------------------

def _nas_settings() -> dict:
    """Return NAS settings merged from settings.json and env vars."""
    saved = load_settings()
    return {
        "host":     saved.get("nas_host",     os.environ.get("NAS_HOST",     "192.168.1.100")),
        "share":    saved.get("nas_share",    os.environ.get("NAS_SHARE",    "NAS_Commun_Vol2")),
        "path":     saved.get("nas_path",     os.environ.get("NAS_PATH",     "DOCUMIND/originals")),
        "username": saved.get("nas_username", os.environ.get("NAS_USERNAME", "Alex")),
        "password": saved.get("nas_password", os.environ.get("NAS_PASSWORD", "Alex")),
        "enabled":  saved.get("nas_sync_enabled", True),
        "hour":     saved.get("nas_sync_hour",   7),
        "minute":   saved.get("nas_sync_minute", 0),
    }

# Internal Documind API base URL (localhost inside CT105)
DOCUMIND_API_URL = os.environ.get("DOCUMIND_API_URL", "http://localhost:8000")

# Tracker file: stores filenames already imported so we don't re-import them
_SYNC_TRACKER_PATH = os.path.join(
    os.environ.get("DOCUMIND_DATA_DIR", "/data"), "nas_sync_tracker.txt"
)


# ---------------------------------------------------------------------------
# Tracker helpers
# ---------------------------------------------------------------------------

def _load_synced_files() -> set[str]:
    """Return the set of filenames already imported from the NAS."""
    if not os.path.exists(_SYNC_TRACKER_PATH):
        return set()
    with open(_SYNC_TRACKER_PATH, "r", encoding="utf-8") as f:
        return {line.strip() for line in f if line.strip()}


def _mark_synced(filename: str) -> None:
    """Append *filename* to the tracker so it won't be re-imported."""
    with open(_SYNC_TRACKER_PATH, "a", encoding="utf-8") as f:
        f.write(filename + "\n")


# ---------------------------------------------------------------------------
# CIFS mount helpers
# ---------------------------------------------------------------------------

def _mount_cifs(mount_point: str, cfg: dict) -> bool:
    """Mount the NAS share at *mount_point* using CIFS.

    Returns True on success, False on failure.
    Requires the ``cifs-utils`` package in CT105 (apt install cifs-utils).
    """
    unc = f"//{cfg['host']}/{cfg['share']}"
    cmd = [
        "mount", "-t", "cifs", unc, mount_point,
        "-o", (
            f"username={cfg['username']},password={cfg['password']},"
            "uid=0,gid=0,iocharset=utf8,vers=3.0"
        ),
    ]
    logger.info("Mounting %s at %s", unc, mount_point)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        logger.error("CIFS mount failed: %s", result.stderr)
        return False
    return True


def _umount_cifs(mount_point: str) -> None:
    """Unmount *mount_point* (best-effort)."""
    subprocess.run(["umount", mount_point], capture_output=True)
    logger.info("Unmounted %s", mount_point)


# ---------------------------------------------------------------------------
# Document upload
# ---------------------------------------------------------------------------

def _upload_file(file_path: Path, api_url: str) -> bool:
    """Upload a single file to Documind via POST /api/documents/upload.

    Returns True on success.
    """
    with open(file_path, "rb") as fh:
        files = {"file": (file_path.name, fh, _mime_for(file_path))}
        try:
            resp = httpx.post(
                f"{api_url}/api/documents/upload",
                files=files,
                timeout=120,
            )
            if resp.status_code == 201:
                logger.info("Uploaded: %s → doc_id=%s", file_path.name, resp.json().get("doc_id"))
                return True
            else:
                logger.warning("Upload failed for %s: %s %s", file_path.name, resp.status_code, resp.text[:200])
                return False
        except Exception as exc:
            logger.error("Upload error for %s: %s", file_path.name, exc)
            return False


def _mime_for(path: Path) -> str:
    ext = path.suffix.lower()
    return {
        ".pdf": "application/pdf",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".tiff": "image/tiff",
        ".webp": "image/webp",
    }.get(ext, "application/octet-stream")


# ---------------------------------------------------------------------------
# Main sync entry point
# ---------------------------------------------------------------------------

def sync_from_nas(api_url: str = DOCUMIND_API_URL) -> dict:
    """Mount the NAS share, scan for new documents, and upload them.

    Returns a summary dict:
        {
            "scanned": int,
            "imported": int,
            "skipped": int,
            "errors": int,
            "files_imported": [...],
            "files_errors": [...],
        }
    """
    cfg = _nas_settings()

    if not cfg["enabled"]:
        return {"skipped": 0, "imported": 0, "scanned": 0, "errors": 0,
                "files_imported": [], "files_errors": [],
                "error_message": "NAS sync is disabled in settings."}

    synced = _load_synced_files()
    summary = {
        "scanned": 0,
        "imported": 0,
        "skipped": 0,
        "errors": 0,
        "files_imported": [],
        "files_errors": [],
    }

    mount_point = tempfile.mkdtemp(prefix="nas_documind_")
    mounted = False

    try:
        mounted = _mount_cifs(mount_point, cfg)
        if not mounted:
            summary["error_message"] = "CIFS mount failed — check NAS credentials and connectivity."
            return summary

        scan_dir = Path(mount_point) / cfg["path"]
        if not scan_dir.exists():
            summary["error_message"] = f"NAS path not found after mount: {scan_dir}"
            return summary

        # Recursively scan for supported document files
        candidate_files: list[Path] = []
        for ext in SUPPORTED_EXTENSIONS:
            candidate_files.extend(scan_dir.rglob(f"*{ext}"))
            candidate_files.extend(scan_dir.rglob(f"*{ext.upper()}"))

        # Deduplicate (rglob with lower+upper may double-count on case-insensitive FS)
        seen_paths: set[str] = set()
        unique_files: list[Path] = []
        for p in candidate_files:
            key = str(p).lower()
            if key not in seen_paths:
                seen_paths.add(key)
                unique_files.append(p)

        summary["scanned"] = len(unique_files)
        logger.info("Found %d candidate file(s) on NAS", len(unique_files))

        for file_path in unique_files:
            filename = file_path.name

            if filename in synced:
                summary["skipped"] += 1
                continue

            success = _upload_file(file_path, api_url)
            if success:
                _mark_synced(filename)
                summary["imported"] += 1
                summary["files_imported"].append(filename)
            else:
                summary["errors"] += 1
                summary["files_errors"].append(filename)

    finally:
        if mounted:
            _umount_cifs(mount_point)
        # Remove empty temp dir
        try:
            os.rmdir(mount_point)
        except OSError:
            pass

    logger.info(
        "NAS sync done — scanned=%d imported=%d skipped=%d errors=%d",
        summary["scanned"], summary["imported"], summary["skipped"], summary["errors"],
    )
    return summary


# ---------------------------------------------------------------------------
# Cron management — called after settings update to keep crontab in sync
# ---------------------------------------------------------------------------

_CRON_MARKER = "# documind-nas-sync"


def apply_cron_schedule() -> dict:
    """Install or remove the Documind NAS sync cron job based on current settings.

    - If nas_sync_enabled is True  → installs/updates the cron entry
    - If nas_sync_enabled is False → removes the cron entry

    Returns {"status": "installed"|"removed"|"skipped"|"error", "detail": str}
    Silently skips on Windows or when crontab is not available.
    """
    import platform
    if platform.system() == "Windows":
        return {"status": "skipped", "detail": "crontab not supported on Windows"}

    cfg = _nas_settings()

    try:
        # Read current crontab (empty string if none)
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        existing_lines = [
            line for line in result.stdout.splitlines()
            if _CRON_MARKER not in line
        ]

        if not cfg["enabled"]:
            # Remove the entry
            new_crontab = "\n".join(existing_lines) + ("\n" if existing_lines else "")
            subprocess.run(["crontab", "-"], input=new_crontab, text=True, check=True)
            logger.info("NAS sync cron job removed")
            return {"status": "removed", "detail": "Cron job removed (sync disabled)"}

        # Build the new cron line
        api_url = DOCUMIND_API_URL
        cron_line = (
            f"{cfg['minute']} {cfg['hour']} * * * "
            f"curl -s -X POST {api_url}/api/sync/nas >> /var/log/nas_sync.log 2>&1"
            f"  {_CRON_MARKER}"
        )
        existing_lines.append(cron_line)
        new_crontab = "\n".join(existing_lines) + "\n"
        subprocess.run(["crontab", "-"], input=new_crontab, text=True, check=True)
        logger.info("NAS sync cron job set to %02d:%02d daily", cfg['hour'], cfg['minute'])
        return {
            "status": "installed",
            "detail": f"Cron job set: every day at {cfg['hour']:02d}:{cfg['minute']:02d}",
        }

    except Exception as exc:
        logger.error("Failed to update crontab: %s", exc)
        return {"status": "error", "detail": str(exc)}


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [nas_sync] %(levelname)s: %(message)s",
    )
    result = sync_from_nas()
    print(result)
