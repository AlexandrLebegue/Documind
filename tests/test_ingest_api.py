"""HTTP behaviour of /api/ingest/check and /api/ingest/candidate."""

import hashlib
import time

import pytest
from fastapi.testclient import TestClient

import main
import nas_sync
import processing_queue


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setattr(main, "init_llm_client", lambda: None)
    monkeypatch.setattr(main, "load_embedding_model", lambda: None)
    monkeypatch.setattr(nas_sync, "apply_cron_schedule", lambda: {"status": "disabled"})
    processing_queue._queue = None
    with TestClient(main.app) as test_client:
        yield test_client
    processing_queue._queue = None


def test_check_reports_unknown_hash(client):
    digest = hashlib.sha256(b"never-seen").hexdigest()
    response = client.post("/api/ingest/check", json={"sha256": [digest]})
    assert response.status_code == 200
    body = response.json()
    assert digest in body["unknown"]
    assert body["known"] == []


def test_candidate_rejects_wrong_magic(client):
    payload = b"PK\x03\x04" + b"0" * 4096
    response = client.post(
        "/api/ingest/candidate",
        files={"file": ("archive.pdf", payload, "application/pdf")},
        data={"origin_path": "/tmp/archive.pdf", "machine": "pc-test"},
    )
    assert response.status_code == 400
    digest = hashlib.sha256(payload).hexdigest()
    check = client.post("/api/ingest/check", json={"sha256": [digest]})
    known = check.json()["known"]
    assert known and known[0]["verdict"] == "rejected"


def test_candidate_rejects_unsupported_extension(client):
    response = client.post(
        "/api/ingest/candidate",
        files={"file": ("archive.zip", b"PK\x03\x04ZIP" + b"1" * 4096, "application/zip")},
    )
    assert response.status_code == 400


def test_candidate_valid_is_queued(client, monkeypatch):
    import database

    def fake_process(sha256, llm, embedding_model):
        database.update_file_mark(sha256, verdict="pending", reason="test")

    monkeypatch.setattr(main, "process_candidate", fake_process)
    payload = b"%PDF-1.4\n" + b"0" * 4096
    response = client.post(
        "/api/ingest/candidate",
        files={"file": ("facture.pdf", payload, "application/pdf")},
        data={"origin_path": "/tmp/facture.pdf", "machine": "pc-test"},
    )
    assert response.status_code == 202
    body = response.json()
    assert body["queued"] is True
    digest = hashlib.sha256(payload).hexdigest()
    for _ in range(20):
        check = client.post("/api/ingest/check", json={"sha256": [digest]}).json()
        if check["known"]:
            break
        time.sleep(0.05)
    assert check["known"][0]["sha256"] == digest


def test_check_finds_archive_added_after_startup(client):
    import database

    digest = hashlib.sha256(b"archived-via-web").hexdigest()
    database.insert_document("web-archive", "web.pdf", "/archive/web.pdf")
    database.update_document_hash("web-archive", digest)
    assert database.get_file_mark(digest) is None
    response = client.post("/api/ingest/check", json={"sha256": [digest, digest.upper()]})
    assert response.status_code == 200
    body = response.json()
    assert body["unknown"] == []
    assert len(body["known"]) == 1
    assert body["known"][0]["verdict"] == "accepted"
    assert body["known"][0]["doc_id"] == "web-archive"
    assert database.get_file_mark(digest)["verdict"] == "accepted"


def test_candidate_does_not_queue_existing_archive_even_if_forced(client, monkeypatch):
    import database

    payload = b"%PDF-1.4\narchived" + b"x" * 2048
    digest = hashlib.sha256(payload).hexdigest()
    database.insert_document("candidate-archive", "archived.pdf", "/archive/archived.pdf")
    database.update_document_hash("candidate-archive", digest)

    def unexpected_process(*args):
        pytest.fail("An existing archive must not be processed again")

    monkeypatch.setattr(main, "process_candidate", unexpected_process)
    response = client.post(
        "/api/ingest/candidate",
        files={"file": ("renamed.pdf", payload, "application/pdf")},
        data={"force": "true"},
    )
    assert response.status_code == 202
    assert response.json()["verdict"] == "accepted"
    assert response.json()["queued"] is False
