"""file_marks ledger CRUD and check semantics."""

from database import (
    count_file_marks_by_verdict,
    delete_file_mark,
    get_file_mark,
    get_file_marks_by_hashes,
    init_db,
    list_file_marks,
    update_file_mark,
    upsert_file_mark,
)


def setup_module():
    init_db()


def test_upsert_and_get():
    sha = "a" * 64
    upsert_file_mark(sha, verdict="pending", source="pc-test", filename="a.pdf")
    mark = get_file_mark(sha)
    assert mark is not None
    assert mark["verdict"] == "pending"
    assert mark["source"] == "pc-test"


def test_update_verdict_sets_date():
    sha = "b" * 64
    upsert_file_mark(sha, verdict="pending")
    update_file_mark(sha, verdict="accepted", reason="facture")
    mark = get_file_mark(sha)
    assert mark["verdict"] == "accepted"
    assert mark["reason"] == "facture"
    assert mark["verdict_at"]


def test_batch_lookup():
    upsert_file_mark("c" * 64, verdict="rejected")
    rows = get_file_marks_by_hashes(["c" * 64, "d" * 64])
    assert [row["sha256"] for row in rows] == ["c" * 64]


def test_list_and_counts():
    upsert_file_mark("e" * 64, verdict="accepted")
    assert count_file_marks_by_verdict().get("accepted", 0) >= 1
    rows = list_file_marks(verdict="accepted", limit=10)
    assert all(row["verdict"] == "accepted" for row in rows)


def test_delete():
    sha = "f" * 64
    upsert_file_mark(sha, verdict="pending")
    delete_file_mark(sha)
    assert get_file_mark(sha) is None


def test_archive_migration_is_idempotent_and_preserves_verdicts():
    from database import insert_document, update_document_hash

    sha = "10" * 32
    insert_document("legacy-root", "legacy.pdf", "/archive/legacy.pdf")
    update_document_hash("legacy-root", sha)
    init_db()
    first = get_file_mark(sha)
    assert first["verdict"] == "accepted"
    assert first["doc_id"] == "legacy-root"
    assert first["source"] == "archive"
    init_db()
    assert get_file_mark(sha) == first

    for index, verdict in enumerate(["accepted", "rejected", "pending", "error"]):
        digest = f"{index + 20:02x}" * 32
        doc_id = f"preserve-mark-{index}"
        insert_document(doc_id, "existing.pdf", "/archive/existing.pdf")
        update_document_hash(doc_id, digest)
        upsert_file_mark(digest, verdict=verdict, reason="explicit verdict", source="agent")
        before = get_file_mark(digest)
        init_db()
        assert get_file_mark(digest) == before


def test_archive_migration_ignores_missing_hashes_and_segment_children():
    from database import insert_document, update_document_hash

    insert_document("unhashed-root", "old.pdf", "/archive/old.pdf")
    insert_document("segment-only", "segment.pdf", "/archive/old.pdf", parent_id="unhashed-root")
    digest = "30" * 32
    update_document_hash("segment-only", digest)
    init_db()
    assert get_file_mark(digest) is None
