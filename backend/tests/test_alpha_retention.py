import unittest

from alpha_retention import plan


class RetentionTest(unittest.TestCase):
    def test_untrusted_or_ambiguous_journal_is_rejected(self):
        valid = {
            "id": "ab9c1b1b-6cdc-4fc1-9cdc-9992db99a6fa",
            "reviewed_at": "2026-01-01T00:00:00Z",
        }
        for records in (
            {},
            [dict(valid, id="'; DELETE FROM auth.users; --")],
            [dict(valid, reviewed_at="2026-01-01")],
            [dict(valid, reviewed_at="2999-01-01T00:00:00Z")],
            [dict(valid, description="private text")],
            [valid, valid],
        ):
            with self.subTest(records=records), self.assertRaises((ValueError, TypeError)):
                plan(records)

    def test_empty_journal_cannot_select_any_report(self):
        self.assertIn("(NULL::uuid,NULL::timestamptz)", plan([]))
        self.assertNotIn("DELETE", plan([]))
        self.assertTrue(plan([]).endswith("ROLLBACK;\n"))


if __name__ == "__main__":
    unittest.main()
