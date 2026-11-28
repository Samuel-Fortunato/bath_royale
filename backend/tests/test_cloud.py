"""Reject unexpected projects and unsafe transport before any managed operation."""

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from cloud import (
    STATE,
    URL,
    connection_env,
    parse_auth_settings,
    preflight,
    private_json,
    state_directory,
)
from cloud_rehearsal import validate_accounts


class CloudPreflightTest(unittest.TestCase):
    def test_explicit_state_directory_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertEqual(state_directory(root), root)
            with patch("cloud.os.getuid", return_value=os.getuid() + 1):
                with self.assertRaisesRegex(RuntimeError, "proprietário atual"):
                    state_directory(root)
            root.chmod(0o755)
            with self.assertRaisesRegex(RuntimeError, "0700"):
                state_directory(root)
            root.chmod(0o700)
            link = root / "link"
            link.symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, "ligações simbólicas"):
                state_directory(link)
            with patch("cloud.__file__", str(root / "backend" / "cloud.py")):
                with self.assertRaisesRegex(RuntimeError, "fora do repositório"):
                    state_directory(root)

    def test_preflight_uses_selected_or_legacy_state_without_writes(self):
        for selected in (None, Path("/explicit-private-state")):
            expected = STATE if selected is None else selected
            with (
                patch("cloud.state_directory", return_value=expected) as validate,
                patch(
                    "cloud.private_json", side_effect=RuntimeError("stop before network")
                ) as read,
            ):
                with self.assertRaisesRegex(RuntimeError, "stop before network"):
                    preflight(selected)
                validate.assert_called_once_with(expected)
                read.assert_called_once_with(expected / "connection.json", ["database_url"])

    def test_retained_accounts_are_private_and_fictional(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "accounts.json"
            accounts = [
                {
                    "email": "bath-royale-fictional-" + name + "@example.invalid",
                    "password": "fictional",
                }
                for name in ["a", "b"]
            ]
            path.write_text(json.dumps(accounts))
            path.chmod(0o600)
            self.assertEqual(validate_accounts(path), accounts)
            path.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "0600"):
                validate_accounts(path)
            path.chmod(0o600)
            accounts[0]["email"] = "unrelated@example.invalid"
            path.write_text(json.dumps(accounts))
            with self.assertRaisesRegex(RuntimeError, "Unexpected fictional"):
                validate_accounts(path)

    def test_auth_settings_require_explicit_booleans(self):
        valid = {"disable_signup": False, "mailer_autoconfirm": True}
        self.assertEqual(parse_auth_settings(valid), valid)
        for key in valid:
            missing = dict(valid)
            del missing[key]
            with self.assertRaisesRegex(RuntimeError, "missing boolean"):
                parse_auth_settings(missing)
            for value in (None, 0, 1, "true", "false", [], {}):
                with self.assertRaisesRegex(RuntimeError, "must be boolean"):
                    parse_auth_settings({**valid, key: value})
        self.assertFalse(
            parse_auth_settings({**valid, "mailer_autoconfirm": False})["mailer_autoconfirm"]
        )

    def test_destination_and_transport_guards(self):
        with tempfile.TemporaryDirectory() as directory:
            cert = Path(directory) / "root.crt"
            cert.touch()
            connection = {
                "database_url": "postgresql://postgres.eiitfxbmavmqafqwfxiy:fictional@aws-0-eu-central-1.pooler.supabase.com:5432/postgres?sslmode=disable"
            }
            env = connection_env(connection, {"url": URL}, cert)
            self.assertEqual(env["PGSSLMODE"], "verify-full")
            self.assertEqual(env["PGPASSWORD"], "fictional")
            for url in [URL + ".attacker.invalid", "https://other.supabase.co"]:
                with self.assertRaisesRegex(RuntimeError, "Unexpected API"):
                    connection_env(connection, {"url": url}, cert)
            for value in ["other", "eiitfxbmavmqafqwfxiy.attacker"]:
                altered = {
                    "database_url": connection["database_url"].replace(
                        "eiitfxbmavmqafqwfxiy", value
                    )
                }
                with self.assertRaisesRegex(RuntimeError, "Unexpected database"):
                    connection_env(altered, {"url": URL}, cert)
            cert.unlink()
            with self.assertRaisesRegex(RuntimeError, "Download project CA"):
                connection_env(connection, {"url": URL}, cert)

    def test_private_file_permissions_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.json"
            path.write_text('{"field":"fictional"}')
            path.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "0600"):
                private_json(path, ["field"])
            path.chmod(0o600)
            self.assertEqual(private_json(path, ["field"]), {"field": "fictional"})
            link = Path(directory) / "link.json"
            link.symlink_to(path)
            with self.assertRaisesRegex(RuntimeError, "regular file"):
                private_json(link, ["field"])
