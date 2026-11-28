"""Offline protocol/security tests; actual domain writes use the isolated rehearsal."""

import json
import subprocess
import unittest
from unittest.mock import patch

import administration as admin


class ProtocolTests(unittest.TestCase):
    def test_environment_selection_precedes_io(self):
        with patch.object(subprocess, "run") as run:
            for env, kwargs in [
                ("managed", {}),
                ("managed", {"container": "other"}),
                ("development", {}),
                ("development", {"container": "bath-royale-poc-db"}),
                ("production", {}),
            ]:
                with self.subTest(env=env), self.assertRaises(admin.AdminError):
                    admin.Database(env, **kwargs)
            run.assert_not_called()

    def test_read_queries_exclude_credentials_and_feedback_retry_proof(self):
        for operation in (
            "users.list",
            "users.creators",
            "users.moderators",
            "feedback.list",
            "reports.list",
            "db.stats",
        ):
            query = admin.read_query(operation, {})
            self.assertNotIn("encrypted_password", query)
            self.assertNotIn("retry_hash", query)
            self.assertNotIn("reporter", query)
        self.assertNotIn("description", admin.read_query("feedback.list", {}))
        self.assertNotIn("email", admin.read_query("users.list", {}))
        for args in (
            {"limit": 0},
            {"limit": 201},
            {"offset": -1},
            {"status": "';delete from auth.users;--"},
        ):
            with self.assertRaises(admin.AdminError):
                admin.read_query("feedback.list", args)

    def test_permanent_references_and_sync_dependencies_are_explicit(self):
        deps = admin.dependencies("00000000-0000-4000-8000-000000000001")
        self.assertEqual(
            set(deps),
            {
                "visits",
                "reviews",
                "favourites",
                "reports",
                "links",
                "registry",
                "sync_records",
                "sync_changes",
                "sync_receipts",
                "sync_dependents",
            },
        )
        self.assertIn("confdeltype='a'", admin.known_references_sql())
        self.assertEqual(len(admin.suggestions()), 40)
        self.assertNotIn("author", json.dumps(admin.suggestions()))

    def test_backup_gate_reuses_sealed_bundle_scope_and_exact_schema(self):
        import hashlib
        from pathlib import Path

        import cloud_transfer
        import migration

        expected = [
            {"name": p.name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
            for p in (admin.ROOT / "supabase/migrations").glob("*.sql")
        ]
        snapshot = {table: [] for table in migration.TABLES}
        snapshot["bath_royale_migrations.applied"] = expected
        bundle = {
            "components.json": json.dumps(
                {"scope": migration.TABLES, "project": admin.cloud.PROJECT}
            ),
            "before.json": json.dumps(snapshot),
        }
        with patch.object(cloud_transfer, "load_bundle", return_value=bundle):
            self.assertTrue(
                admin.verify_backup(Path("/synthetic"), admin.cloud.PROJECT)["verified"]
            )
            bundle["components.json"] = json.dumps(
                {"scope": cloud_transfer.LEGACY_CORE, "project": admin.cloud.PROJECT}
            )
            with self.assertRaises(RuntimeError):
                admin.verify_backup(Path("/synthetic"), admin.cloud.PROJECT)
            bundle["components.json"] = json.dumps(
                {"scope": migration.TABLES, "project": "other-project"}
            )
            with self.assertRaises(admin.AdminError):
                admin.verify_backup(Path("/synthetic"), admin.cloud.PROJECT)
            bundle["components.json"] = json.dumps(
                {"scope": migration.TABLES, "project": admin.cloud.PROJECT}
            )
            snapshot["bath_royale_migrations.applied"] = []
            bundle["before.json"] = json.dumps(snapshot)
            with self.assertRaises(admin.AdminError):
                admin.verify_backup(Path("/synthetic"), admin.cloud.PROJECT)

    def test_unsafe_subprocess_diagnostics_are_never_forwarded(self):
        db = object.__new__(admin.Database)
        db.command, db.env = ["psql"], {}
        for diagnostic, expected in [
            ("secret-marker", "SQL foi recusada"),
            ("Stale plan", "desatualizado"),
            ("Unsafe deletion", "Eliminação recusada"),
        ]:
            with patch.object(
                subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", diagnostic)
            ):
                with self.assertRaises(admin.AdminError) as error:
                    db.sql("SELECT 1")
                self.assertIn(expected, str(error.exception))
                self.assertNotIn("secret-marker", str(error.exception))

    def test_mutation_confirmation_and_target_binding_cannot_be_bypassed(self):
        class Fake:
            environment = "development"
            target = "podman:explicit-disposable"

        identifier = "00000000-0000-4000-8000-000000000001"
        request = {
            "version": 1,
            "operation": "users.grant",
            "args": {"id": identifier, "actor": identifier},
            "plan": {},
        }
        with self.assertRaises(admin.AdminError):
            admin.execute(Fake(), request)
        request["confirmed"] = True
        request["plan"] = {"environment": "managed"}
        with self.assertRaises(admin.AdminError):
            admin.execute(Fake(), request)
        with self.assertRaises(ValueError):
            admin.identifier("';delete from auth.users;--")
