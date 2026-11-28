"""Offline synthetic-data regression tests; no network, containers or private evidence."""

import argparse
import contextlib
import hashlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import cloud
import cloud_transfer as transfer
import migration
import poc


def section(table, rows="", columns='"id"'):
    schema, name = table.split(".")
    return f'COPY "{schema}"."{name}" ({columns}) FROM stdin;\n{rows}\\.\n'


def fixture():
    return "".join(section(t, "fictional\n") for t in migration.TABLES)


class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.columns = {t: ["id"] for t in migration.TABLES}

    def test_preserve_rows_exclude_sessions_and_only_explicit_empty_sections(self):
        extra = "".join(section(t, "session\n") for t in sorted(transfer.SESSIONS))
        extra += "".join(section(t) for t in sorted(transfer.EMPTY_OMISSIONS))
        extra += 'SELECT pg_catalog.setval(\'"auth"."refresh_tokens_id_seq"\', 2, true);\n'
        actual, decisions = transfer.adapt_data(fixture() + extra, self.columns)
        self.assertEqual(actual, fixture())
        self.assertEqual(len(decisions), 14)
        self.assertNotIn("session", actual)

    def test_sync_sequence_and_all_protocol_metadata_are_preserved(self):
        sequence = "SELECT pg_catalog.setval('app_private.sync_changes_position_seq', 123, true);\n"
        actual, _ = transfer.adapt_data(fixture() + sequence, self.columns)
        self.assertEqual(actual, fixture() + sequence)
        for name in ["sync_clock", "sync_records", "sync_changes", "sync_receipts", "sync_cursors"]:
            self.assertIn("app_private." + name, migration.TABLES)

    def test_legacy_native_backup_preserves_core_and_rejects_unreviewed_scopes(self):
        text = "".join(section(t, "fictional\n") for t in transfer.LEGACY_CORE)
        self.assertEqual(transfer.adapt_data(text, self.columns, transfer.LEGACY_CORE)[0], text)
        with self.assertRaises(RuntimeError):
            transfer.adapt_data(text, self.columns)
        with self.assertRaises(RuntimeError):
            transfer.adapt_data(
                text + section("app_private.sync_records", "unexpected\n"),
                self.columns,
                transfer.LEGACY_CORE,
            )
        for scope in [transfer.LEGACY_CORE, migration.TABLES]:
            bundle = {
                "components.json": json.dumps({"scope": scope}),
                "before.json": json.dumps({t: [] for t in scope}),
            }
            self.assertEqual(transfer.bundle_scope(bundle), scope)
            bundle["components.json"] = json.dumps({"scope": scope[:-1]})
            with self.assertRaises(RuntimeError):
                transfer.bundle_scope(bundle)

    def test_populated_unsupported_sections_and_new_sequence_fail(self):
        for extra in (
            section("storage.objects", "object\n"),
            section("auth.custom_oauth_providers", "provider\n"),
            section("auth.mfa_factors", "factor\n"),
            "SELECT pg_catalog.setval('public.new_seq', 3, true);\n",
        ):
            with self.subTest(extra=extra), self.assertRaises(RuntimeError):
                transfer.adapt_data(fixture() + extra, self.columns)

    def test_unknown_empty_missing_columns_duplicate_and_truncated_copy_fail(self):
        for sql in (
            fixture() + section("unknown.table"),
            fixture().replace('("id")', '("new_column")', 1),
            fixture() + section("auth.users"),
            fixture()[:-3],
            "COPY auth.users (id) FROM stdin;\n\\.\n",
            "",
        ):
            with self.subTest(sql=sql[:50]), self.assertRaises(RuntimeError):
                transfer.adapt_data(sql, self.columns)

    def test_compatible_empty_auth_table_retained_but_populated_out_of_scope_fails(self):
        self.columns["auth.mfa_factors"] = ["id"]
        actual, _ = transfer.adapt_data(fixture() + section("auth.mfa_factors"), self.columns)
        self.assertIn('"mfa_factors"', actual)
        with self.assertRaises(RuntimeError):
            transfer.adapt_data(fixture() + section("auth.mfa_factors", "factor\n"), self.columns)

    def test_exact_cli_filters_and_tls_are_preserved(self):
        generated = (
            "export PGHOST=placeholder\nexport PGPASSWORD=placeholder\npg_dump | sed 'filter'\n"
        )
        self.assertEqual(transfer.filtered_script(generated), "pg_dump | sed 'filter'")
        with tempfile.TemporaryDirectory() as name:
            cert = Path(name) / "root.crt"
            cert.touch()
            with patch.dict(os.environ, {"PGSSLMODE": "disable", "PGSERVICE": "unsafe"}):
                env = cloud.connection_env(
                    {
                        "database_url": f"postgresql://postgres.{cloud.PROJECT}:fake@"
                        "test.pooler.supabase.com:5432/postgres?sslmode=disable"
                    },
                    {"url": cloud.URL},
                    cert,
                )
            self.assertEqual(env["PGSSLMODE"], "verify-full")
            self.assertEqual(env["PGSSLROOTCERT"], str(cert))
            self.assertNotIn("PGSERVICE", env)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bundle = Path(self.temp.name) / "bundle"
        self.bundle.mkdir(mode=0o700)
        for name in (
            "roles.sql",
            "schema.sql",
            "data.sql",
            "before.json",
            "inventory.json",
            "acls.json",
            "columns.json",
            "components.json",
        ):
            poc.secure_write(self.bundle / name, "{}")
        transfer.seal(self.bundle)

    def test_valid_bundle_and_corruption_failures(self):
        self.assertEqual(len(transfer.load_bundle(self.bundle)), 8)
        (self.bundle / "data.sql").write_text("corrupt")
        with self.assertRaisesRegex(RuntimeError, "checksum"):
            transfer.load_bundle(self.bundle)

    def test_missing_extra_permissions_and_symlink_fail(self):
        path = self.bundle / "data.sql"
        original = path.read_text()
        path.chmod(0o644)
        with self.assertRaises(RuntimeError):
            transfer.load_bundle(self.bundle)
        path.unlink()
        with self.assertRaises(RuntimeError):
            transfer.load_bundle(self.bundle)
        path.symlink_to(self.bundle / "schema.sql")
        with self.assertRaises(RuntimeError):
            transfer.load_bundle(self.bundle)
        path.unlink()
        poc.secure_write(path, original)
        poc.secure_write(self.bundle / "extra.sql", "")
        with self.assertRaises(RuntimeError):
            transfer.load_bundle(self.bundle)

    def test_manifest_traversal_and_checkout_destination_fail(self):
        path = self.bundle / "manifest.json"
        manifest = json.loads(path.read_text())
        manifest["files"]["../private"] = {"bytes": 0, "sha256": ""}
        path.write_text(json.dumps(manifest))
        with self.assertRaises(RuntimeError):
            transfer.load_bundle(self.bundle)
        with self.assertRaises(RuntimeError):
            transfer.outside_checkout(poc.ROOT / "backend/export")

    def test_offline_verify_never_contacts_services(self):
        with (
            patch.object(transfer, "destination") as destination,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            transfer.verify_bundle(
                SimpleNamespace(bundle=self.bundle, destination=None, runtime=False)
            )
        destination.assert_not_called()


class ExportTests(unittest.TestCase):
    def test_legacy_export_refuses_drift_before_creating_a_bundle(self):
        with tempfile.TemporaryDirectory() as name:
            parent = Path(name)
            parent.chmod(0o700)
            args = SimpleNamespace(
                bundle=parent / "new", source_state=parent, project="a" * 20, legacy_core=True
            )
            core = poc.ROOT / "supabase/migrations/202611250001_core.sql"
            ledger = [{"name": core.name, "sha256": hashlib.sha256(core.read_bytes()).hexdigest()}]
            for responses in [[[]], [ledger, [{"name": "public.unknown"}]]]:
                with (
                    patch.object(transfer, "managed", return_value=Mock()),
                    patch.object(transfer, "json_query", side_effect=responses),
                    self.assertRaises(RuntimeError),
                ):
                    transfer.export_bundle(args)
                self.assertFalse(args.bundle.exists())

    def test_export_uses_three_cli_scripts_verified_environment_and_seals_originals(self):
        with tempfile.TemporaryDirectory() as name:
            parent = Path(name)
            parent.chmod(0o700)
            args = SimpleNamespace(bundle=parent / "new", source_state=parent, project="a" * 20)
            remote = SimpleNamespace(env={"PGSSLMODE": "verify-full"})
            script = "export PGPASSWORD=placeholder\npg_dump | sed 'platform-filter'"
            with (
                patch.object(transfer, "managed", return_value=remote),
                patch.object(migration, "snapshot", return_value={}),
                patch.object(transfer, "inventory", return_value={}),
                patch.object(transfer, "acls", return_value={}),
                patch.object(transfer, "json_query", return_value=[]),
                patch.object(
                    poc,
                    "run",
                    side_effect=["2.111.0", "pg_dump (PostgreSQL) 17.12", script, script, script],
                ) as commands,
                patch.object(
                    transfer.subprocess,
                    "run",
                    return_value=SimpleNamespace(returncode=0, stdout="fictional export"),
                ) as execute,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                transfer.export_bundle(args)
            self.assertEqual(execute.call_count, 3)
            for call in execute.call_args_list:
                self.assertEqual(call.args[0], ["bash", "-e", "-o", "pipefail"])
                self.assertEqual(call.kwargs["env"], remote.env)
                self.assertEqual(call.kwargs["input"], "pg_dump | sed 'platform-filter'")
            dump_calls = commands.call_args_list[2:]
            self.assertIn("--role-only", dump_calls[0].args[0])
            self.assertIn("--use-copy", dump_calls[2].args[0])
            self.assertIn("--data-only", dump_calls[2].args[0])
            for call in dump_calls:
                self.assertIn("--dry-run", call.args[0])
                self.assertIn(
                    "postgresql://postgres:placeholder@127.0.0.1:5432/postgres", call.args[0]
                )
            loaded = transfer.load_bundle(args.bundle)
            self.assertEqual(loaded["data.sql"], "fictional export")

    def test_cli_failure_never_creates_a_complete_bundle(self):
        with tempfile.TemporaryDirectory() as name:
            parent = Path(name)
            parent.chmod(0o700)
            args = SimpleNamespace(bundle=parent / "new", source_state=parent, project="a" * 20)
            with (
                patch.object(transfer, "managed", return_value=SimpleNamespace(env={})),
                patch.object(migration, "snapshot", return_value={}),
                patch.object(transfer, "inventory", return_value={}),
                patch.object(transfer, "acls", return_value={}),
                patch.object(transfer, "json_query", return_value=[]),
                patch.object(poc, "run", side_effect=["2.111.0", "17.12", "pg_dump | cat"]),
                patch.object(
                    transfer.subprocess,
                    "run",
                    return_value=SimpleNamespace(
                        returncode=1, stdout="partial private rows", stderr="private diagnostics"
                    ),
                ),
            ):
                with self.assertRaises(RuntimeError):
                    transfer.export_bundle(args)
            self.assertFalse((args.bundle / "manifest.json").exists())
            self.assertFalse((args.bundle / "roles.sql").exists())


class DestinationTests(unittest.TestCase):
    def target(self, path, responses):
        return SimpleNamespace(
            STATE=path, PROJECT="bath-royale-migration-offline", run=Mock(side_effect=responses)
        )

    def test_existing_state_and_all_resource_kinds_refused(self):
        with tempfile.TemporaryDirectory() as name:
            existing = self.target(Path(name), [])
            with self.assertRaises(RuntimeError):
                transfer.fresh_target(existing)
            existing.run.assert_not_called()
            for i in range(3):
                target = self.target(
                    Path(name) / "absent",
                    ["true"] + [""] * i + ["bath-royale-migration-offline-db"],
                )
                with self.assertRaisesRegex(RuntimeError, "resources exist"):
                    transfer.fresh_target(target)

    def test_daemon_errors_are_never_interpreted_as_absence(self):
        with tempfile.TemporaryDirectory() as name:
            target = self.target(Path(name) / "absent", ["true", RuntimeError("daemon")])
            with self.assertRaisesRegex(RuntimeError, "daemon"):
                transfer.fresh_target(target)
            target = self.target(Path(name) / "absent", ["true", "", "", ""])
            transfer.fresh_target(target)
            self.assertEqual(target.run.call_count, 4)

    def test_protected_installations_cannot_be_selected(self):
        with patch.dict(os.environ, {"XDG_STATE_HOME": "/tmp/transfer-tests"}):
            for name in ("source", "destination", "cloud-destination"):
                target = transfer.destination(name, (55561, 55562))
                self.assertTrue(target.PROJECT.startswith("bath-royale-migration-"))
                self.assertNotEqual(target.PROJECT, "bath-royale-poc-" + name)
        for name in ("../source", "", "source;bad"):
            with self.assertRaises(RuntimeError):
                transfer.destination(name)
        with self.assertRaises(RuntimeError):
            transfer.destination("offline", (55561, 55561))

    def test_cli_requires_explicit_destination_disposable_ports_and_quiescence(self):
        for argv in (
            ["restore", "--bundle", "/tmp/unused"],
            [
                "export",
                "--bundle",
                "/tmp/unused",
                "--source-state",
                "/tmp/private",
                "--project",
                "a" * 20,
            ],
        ):
            with (
                patch("sys.argv", ["cloud_transfer.py", *argv]),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                with self.assertRaises(SystemExit) as raised:
                    transfer.main()
                self.assertEqual(raised.exception.code, 2)


class PreservationTests(unittest.TestCase):
    def test_effective_acls_include_implicit_function_defaults_column_grants_and_options(self):
        self.assertIn("acldefault('f',p.proowner)", transfer.ACL)
        source = {
            "objects": [
                {
                    "object": "FUNCTION public.example()",
                    "privilege_type": "EXECUTE",
                    "is_grantable": False,
                    "role": "PUBLIC",
                }
            ],
            "columns": [
                {
                    "tab": "public.example",
                    "col": '"value"',
                    "privilege_type": "SELECT",
                    "is_grantable": True,
                    "role": "authenticated",
                }
            ],
        }
        sql = transfer.reconcile_sql(source)
        self.assertIn("REVOKE ALL ON ", sql)
        self.assertIn("REVOKE ", sql)
        self.assertIn("GRANT EXECUTE ON FUNCTION public.example() TO PUBLIC;", sql)
        self.assertIn(
            'GRANT SELECT ("value") ON TABLE public.example TO authenticated WITH GRANT OPTION;',
            sql,
        )
        self.assertIn("END; $reconcile$;", sql)

    def test_row_inventory_and_acl_differences_fail(self):
        bundle = {
            "before.json": json.dumps({t: [] for t in migration.TABLES}),
            "components.json": json.dumps({"scope": migration.TABLES}),
            "inventory.json": json.dumps({k: "" for k in transfer.INVENTORY_KEYS}),
            "acls.json": "{}",
        }
        for rows, inventory, acls in (
            ({"different": []}, {}, {}),
            ({t: [] for t in migration.TABLES}, {"schemas": "changed"}, {}),
            (
                {t: [] for t in migration.TABLES},
                {k: "" for k in transfer.INVENTORY_KEYS},
                {"different": []},
            ),
        ):
            with (
                patch.object(migration, "snapshot", return_value=rows),
                patch.object(transfer, "inventory", return_value=inventory),
                patch.object(transfer, "acls", return_value=acls),
                self.assertRaises(RuntimeError),
            ):
                transfer.preservation(Mock(), bundle)

    def test_fk_revalidation_is_rolled_back_and_names_are_quoted(self):
        bundle = {
            "before.json": json.dumps({t: [] for t in migration.TABLES}),
            "components.json": json.dumps({"scope": migration.TABLES}),
            "inventory.json": json.dumps({k: "" for k in transfer.INVENTORY_KEYS}),
            "acls.json": "{}",
        }
        target = SimpleNamespace(sql=Mock())
        with (
            patch.object(migration, "snapshot", return_value={t: [] for t in migration.TABLES}),
            patch.object(
                transfer, "inventory", return_value={k: "" for k in transfer.INVENTORY_KEYS}
            ),
            patch.object(transfer, "acls", return_value={}),
            patch.object(
                transfer,
                "json_query",
                return_value=[
                    {
                        "conname": 'odd"name',
                        "definition": "FOREIGN KEY (id) REFERENCES public.profiles(id)",
                    }
                ],
            ),
        ):
            transfer.preservation(target, bundle)
        for call in target.sql.call_args_list:
            sql = call.args[0]
            self.assertTrue(sql.startswith("begin;"))
            self.assertTrue(sql.endswith("rollback;"))
            self.assertIn('"odd""name"', sql)

    def test_restore_is_single_transaction_and_failure_never_retries_or_cleans(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            manifest = root / "manifest.json"
            manifest.write_text("{}")
            args = argparse.Namespace(
                bundle=root,
                disposable=True,
                destination="offline",
                auth_port=55561,
                rest_port=55562,
            )
            bundle = {
                "before.json": json.dumps({t: [] for t in migration.TABLES}),
                "inventory.json": '{"constraints": ""}',
                "roles.sql": "ROLES;",
                "schema.sql": "SCHEMA;",
                "data.sql": fixture(),
                "columns.json": json.dumps(
                    [
                        {"tab": t, "col": "id", "data_type": "uuid", "udt_name": "uuid"}
                        for t in migration.TABLES
                    ]
                ),
                "acls.json": '{"objects": [], "columns": []}',
                "components.json": json.dumps(
                    {
                        "scope": migration.TABLES,
                        "compose_sha256": hashlib.sha256(
                            (poc.ROOT / "backend/compose.yml").read_bytes()
                        ).hexdigest(),
                    }
                ),
            }
            target = SimpleNamespace(
                STATE=root / "new",
                start=Mock(),
                compose=Mock(),
                sql=Mock(side_effect=["0", "0", RuntimeError("private diagnostics")]),
            )
            with (
                patch.object(transfer, "load_bundle", return_value=bundle),
                patch.object(transfer, "destination", return_value=target),
                patch.object(transfer, "fresh_target") as fresh,
                patch.object(
                    transfer,
                    "json_query",
                    return_value=[
                        {"tab": t, "col": "id", "data_type": "uuid", "udt_name": "uuid"}
                        for t in migration.TABLES
                    ],
                ),
            ):
                with self.assertRaises(RuntimeError):
                    transfer.restore_bundle(args)
                fresh.assert_called_once_with(target)
            sql = target.sql.call_args_list[-1].args[0]
            self.assertTrue(sql.startswith("begin;\nROLES;\nSCHEMA;"))
            self.assertIn("set local session_replication_role=replica;", sql)
            self.assertIn("DO $reconcile$", sql)
            self.assertTrue(sql.endswith("commit;"))
            self.assertEqual(target.sql.call_count, 3)
            target.start.assert_called_once_with(migrations=False)
            target.compose.assert_called_once_with("stop", "auth", "rest")
            self.assertTrue((target.STATE / "transfer.json").exists())


class CleanupTests(unittest.TestCase):
    def test_cleanup_requires_matching_disposable_receipt_and_checks_absence(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / "manifest.json").write_text("disposable manifest")
            (state / "manifest.json").chmod(0o600)
            args = SimpleNamespace(disposable=True, destination="disposable-unit", bundle=state)
            receipt = {
                "destination": args.destination,
                "bundle_sha256": hashlib.sha256((state / "manifest.json").read_bytes()).hexdigest(),
            }
            (state / "transfer.json").write_text(json.dumps(receipt))
            (state / "transfer.json").chmod(0o600)
            target = SimpleNamespace(
                STATE=state,
                PROJECT="bath-royale-migration-disposable-unit",
                compose=Mock(),
                run=Mock(return_value=""),
            )
            with (
                patch.object(transfer, "load_bundle", return_value={"verified": True}),
                patch.object(transfer, "destination", return_value=target),
            ):
                transfer.cleanup_destination(args)
                target.compose.assert_called_once_with("down", "-v")
                self.assertEqual(target.run.call_count, 3)
                args.disposable = False
                target.compose.reset_mock()
                with self.assertRaises(RuntimeError):
                    transfer.cleanup_destination(args)
                target.compose.assert_not_called()
                args.disposable = True
                receipt["bundle_sha256"] = "wrong"
                (state / "transfer.json").write_text(json.dumps(receipt))
                with self.assertRaises(RuntimeError):
                    transfer.cleanup_destination(args)
                target.compose.assert_not_called()
                receipt["bundle_sha256"] = hashlib.sha256(
                    (state / "manifest.json").read_bytes()
                ).hexdigest()
                (state / "transfer.json").write_text(json.dumps(receipt))
                target.run.return_value = target.PROJECT + "-db"
                with self.assertRaises(RuntimeError):
                    transfer.cleanup_destination(args)


class EvidenceTests(unittest.TestCase):
    def test_evidence_checks_existing_manifests_without_destination_or_network(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inner = root / "restore"
            inner.mkdir(mode=0o700)
            (inner / "manifest.json").write_text("disposable manifest")
            args = SimpleNamespace(bundle=root, destination=None, runtime=False, evidence=True)
            with (
                patch.object(transfer, "load_bundle", return_value={}) as load,
                patch.object(transfer, "destination", side_effect=AssertionError("network")),
            ):
                transfer.verify_bundle(args)
                load.assert_called_once()
                self.assertEqual(load.call_args.args[0], inner)
                args.destination = "refused"
                with self.assertRaises(RuntimeError):
                    transfer.verify_bundle(args)


if __name__ == "__main__":
    unittest.main()
