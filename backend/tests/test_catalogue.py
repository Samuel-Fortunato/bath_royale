import csv
import tempfile
import unittest
from pathlib import Path

from import_catalogue import ROOT, identity, load, plan


class CatalogueTest(unittest.TestCase):
    def test_approved_catalogue_and_permanent_identity(self):
        entries = load(ROOT / "content/official_bathrooms.csv")
        self.assertEqual(len(entries), 34)
        self.assertEqual(entries[0]["id"], "ee759988-87ed-54e1-bee5-94be386a03e1")
        self.assertEqual(entries[0]["content"]["name"], "DLC")
        self.assertEqual(entries[0]["content"]["emoji"], "🗣️")
        self.assertEqual(entries[0]["content"]["accent_rgb"], 0x8B5CF6)
        self.assertEqual(entries[-1]["content"]["name"], "Antiga Reitoria")
        for entry in entries:
            self.assertEqual(entry["id"], identity(entry["key"]))
            self.assertEqual(entry["content"]["origin"], "curated")
        dry = plan(entries)
        self.assertTrue(dry.endswith("ROLLBACK;\n"))
        self.assertNotIn("INSERT INTO public.bathrooms", dry)
        self.assertNotIn("sync_revision()", dry)
        self.assertTrue(plan(entries, apply=True).endswith("COMMIT;\n"))

    def test_rejects_duplicates_invalid_rgb_keys_and_names(self):
        valid = ["ua-one", "Trono", "👑", "#123456"]
        invalid = [
            [valid, valid],
            [valid, ["ua-two", "TRONO", "👑", "#123456"]],
            [["bad key", *valid[1:]]],
            [[*valid[:3], "#12345"]],
            [[valid[0], " Trono", *valid[2:]]],
            [],
        ]
        for rows in invalid:
            with self.subTest(rows=rows), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "catalogue.csv"
                with path.open("w", newline="") as stream:
                    writer = csv.writer(stream)
                    writer.writerow(["key", "name", "emoji", "color"])
                    writer.writerows(rows)
                with self.assertRaises(ValueError):
                    load(path)
