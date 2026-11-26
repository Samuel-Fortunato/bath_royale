"""Reject unexpected projects and unsafe transport before any managed operation."""

import json
import tempfile
import unittest
from pathlib import Path

from cloud import URL, connection_env, parse_auth_settings, private_json
from cloud_rehearsal import validate_accounts


class CloudPreflightTest(unittest.TestCase):
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
