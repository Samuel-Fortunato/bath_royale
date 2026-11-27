import tempfile
import unittest
from pathlib import Path

from release_plan import plan


class ReleasePlanTest(unittest.TestCase):
    def test_order_checksum_transaction_and_no_reset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "002.sql").write_text("select 2;")
            (root / "001.sql").write_text("select 1;")
            result = plan(root)
            self.assertLess(result.index("select 1;"), result.index("select 2;"))
            self.assertIn("ON_ERROR_STOP", result)
            self.assertIn("checksum differs", result)
            self.assertTrue(result.endswith("COMMIT;\n"))
            self.assertNotIn("DROP", result)
            self.assertNotIn("TRUNCATE", result)
