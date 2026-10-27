"""Test bootstrap: isolate all runtime data in a temporary directory."""

import os
import tempfile

_TEST_DATA_DIR = tempfile.mkdtemp(prefix="documind-tests-")
os.environ.setdefault("DOCUMIND_DATA_DIR", _TEST_DATA_DIR)
os.environ.setdefault("EMBEDDING_LAZY_LOAD", "1")
os.environ.setdefault("AI_PROVIDER", "llamacpp")
