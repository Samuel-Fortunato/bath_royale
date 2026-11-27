"""Development fixture guards run without network or database mutation."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import seed_development as seed


class FixtureGuards(unittest.TestCase):
    def test_non_fixture_instance_is_rejected_before_any_io(self):
        for instance in ("source", "auth", "community", "protocol", "managed"):
            with (
                patch.object(seed.poc, "INSTANCE", instance),
                patch.object(seed.poc, "start") as start,
            ):
                with self.assertRaises(RuntimeError):
                    seed.seed(Path("/missing"), Path("/missing"))
                start.assert_not_called()

    def test_repository_output_is_forbidden(self):
        with self.assertRaises(RuntimeError):
            seed.outside_checkout(seed.poc.ROOT / "private-fixtures")

    def test_symlink_password_is_forbidden(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "actual").write_text("unit-test-only")
            (root / "link").symlink_to(root / "actual")
            with (
                patch.object(seed.poc, "INSTANCE", "fixtures"),
                patch.object(seed.poc, "start") as start,
            ):
                with self.assertRaises(RuntimeError):
                    seed.seed(root / "link", root / "output")
                start.assert_not_called()

    def test_existing_unowned_account_is_never_authenticated_or_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            password = root / "input"
            seed.secure_file(password, "unit-input-only")

            def sql(statement):
                return (
                    "11111111-1111-4111-8111-111111111111" if "from auth.users" in statement else ""
                )

            with (
                patch.object(seed.poc, "INSTANCE", "fixtures"),
                patch.object(seed.poc, "start"),
                patch.object(seed.poc, "bindings"),
                patch.object(seed.poc, "sql", side_effect=sql),
                patch.object(seed.poc, "request") as request,
            ):
                with self.assertRaisesRegex(RuntimeError, "unowned test account"):
                    seed.seed(password, root / "output")
                request.assert_not_called()
