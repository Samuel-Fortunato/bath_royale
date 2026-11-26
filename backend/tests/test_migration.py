"""Negative export checks complement the live end-to-end rehearsal."""

import hashlib
import tempfile
import unittest
from pathlib import Path

from migration import verify_exports


class ExportTest(unittest.TestCase):
    def test_corrupt_or_missing_export_fails(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            file = directory / "data.sql"
            file.write_bytes(b"original")
            manifest = {"data.sql": {"sha256": hashlib.sha256(b"original").hexdigest()}}
            verify_exports(directory, manifest)
            file.write_bytes(b"corrupted")
            with self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
                verify_exports(directory, manifest)
            file.unlink()
            with self.assertRaises(FileNotFoundError):
                verify_exports(directory, manifest)
