"""Magic-byte and extension validation for folder-sync candidates."""

from ingest import check_magic_bytes, decide_verdict


def _pdf() -> bytes:
    return b"%PDF-1.4\n" + b"0" * 2048


def _png() -> bytes:
    return b"\x89PNG\r\n\x1a\n" + b"0" * 2048


def _jpeg() -> bytes:
    return b"\xff\xd8\xff\xe0" + b"0" * 2048


def _bmp() -> bytes:
    return b"BM" + b"0" * 2048


def test_pdf_magic_ok():
    assert check_magic_bytes("facture.pdf", _pdf())[0]


def test_pdf_with_wrong_magic_is_rejected():
    ok, reason = check_magic_bytes("facture.pdf", b"PK\x03\x04" + b"0" * 2048)
    assert not ok
    assert "PDF" in reason


def test_image_signatures():
    assert check_magic_bytes("photo.png", _png())[0]
    assert check_magic_bytes("photo.jpg", _jpeg())[0]
    assert check_magic_bytes("photo.jpeg", _jpeg())[0]
    assert check_magic_bytes("scan.bmp", _bmp())[0]
    assert not check_magic_bytes("photo.png", _jpeg())[0]


def test_txt_utf8_and_latin1():
    assert check_magic_bytes("note.txt", "Attestation préfecture".encode("utf-8") + b" " * 2000)[0]
    assert check_magic_bytes("note.txt", "Attestation préfecture".encode("latin-1") + b" " * 2000)[0]
    assert not check_magic_bytes("note.txt", b"abc\x00def" + b"0" * 2000)[0]


def test_disallowed_extensions():
    for name in ("archive.zip", "page.html", "icon.ico", "blob.bin", "app.exe", "doc.docx"):
        ok, _ = check_magic_bytes(name, b"0" * 4096)
        assert not ok, name


def test_size_limits():
    assert not check_magic_bytes("small.pdf", b"%PDF-1.4\n")[0]
    assert not check_magic_bytes("empty.pdf", b"")[0]


def test_verdict_threshold():
    assert decide_verdict({"keep": True, "confidence": 0.95, "reason": "facture"}, 0.7)[0] == "accepted"
    assert decide_verdict({"keep": False, "confidence": 0.95, "reason": "meme"}, 0.7)[0] == "rejected"
    assert decide_verdict({"keep": True, "confidence": 0.4, "reason": "doute"}, 0.7)[0] == "pending"
