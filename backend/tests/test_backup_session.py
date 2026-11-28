"""Real PostgreSQL lock ownership/loss tests, isolated Unix socket only."""

import getpass
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import backup_session as backup


@unittest.skipUnless(
    all(shutil.which(t) for t in ("initdb", "pg_ctl", "psql")), "Pinned backend shell required"
)
class BackupSessionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="broyale-backup-lock-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = backup.Path(self.temporary.name)
        self.env = {k: os.environ[k] for k in ("PATH", "HOME", "LANG") if k in os.environ}
        self.env.update(
            PGHOST=str(self.root), PGPORT="55597", PGDATABASE="postgres", PGUSER=getpass.getuser()
        )
        self.command = ["psql", "-XqAt", "-v", "ON_ERROR_STOP=1"]
        self.execute(["initdb", "-D", str(self.root / "db"), "-A", "trust", "--no-locale"])
        self.execute(
            [
                "pg_ctl",
                "-D",
                str(self.root / "db"),
                "-l",
                str(self.root / "postgres.log"),
                "-o",
                "-F -k " + str(self.root) + " -p 55597 -c listen_addresses=''",
                "-w",
                "start",
            ]
        )
        self.addCleanup(
            lambda: self.execute(["pg_ctl", "-D", str(self.root / "db"), "-m", "immediate", "stop"])
        )
        self.sql(
            "CREATE TABLE public.synthetic(id integer); INSERT INTO public.synthetic VALUES(1);"
        )
        self.tables = patch.object(backup.migration, "TABLES", ["public.synthetic"])
        self.sessions = patch.object(backup.transfer, "SESSIONS", set())
        self.guard = patch.object(backup.admin, "schema_guard", return_value="")
        for boundary in (self.tables, self.sessions, self.guard):
            boundary.start()
            self.addCleanup(boundary.stop)
        self.session = backup.Session(SimpleNamespace(command=self.command, env=self.env))
        self.addCleanup(self.session.close)
        self.assertEqual(self.session.query("SELECT pg_try_advisory_lock(74042073);"), "t")

    def execute(self, command, data=None):
        result = subprocess.run(
            command, input=data, env=self.env, capture_output=True, text=True, timeout=30
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def sql(self, statement):
        return self.execute(self.command, statement)

    def test_complete_locks_block_writers_and_cross_computer_advisory_lock(self):
        self.assertEqual(self.sql("SELECT pg_try_advisory_lock(74042073);"), "f")
        checked = []
        original = backup.ownership

        def observe(session, **kwargs):
            value = original(session, **kwargs)
            writer = subprocess.run(
                self.command,
                env=self.env,
                text=True,
                capture_output=True,
                input="SET lock_timeout='100ms'; UPDATE public.synthetic SET id=2;",
                timeout=5,
            )
            self.assertNotEqual(writer.returncode, 0)
            self.assertIn("lock timeout", writer.stderr)
            self.assertTrue(value["advisory"])
            self.assertEqual(value["tables"], 1)
            self.assertIsNotNone(value["xid"])
            checked.append(value)
            return value

        with patch.object(backup, "ownership", side_effect=observe):
            backup.locked_export(self.session, [sys.executable, "-c", "pass"], self.env)
        self.assertGreaterEqual(len(checked), 2)
        self.assertTrue(all(v == checked[0] for v in checked))
        self.assertEqual(self.sql("SELECT id FROM public.synthetic;"), "1")
        self.assertEqual(
            json.loads(
                self.session.query("SELECT json_build_object('x',txid_current_if_assigned());")
            ),
            {"x": None},
        )

    def test_killed_consistency_connection_aborts_export_and_stops_worker(self):
        pid = backup.ownership(self.session)["pid"]
        timer = threading.Timer(
            0.3, lambda: self.sql("SELECT pg_terminate_backend(" + str(pid) + ");")
        )
        timer.start()
        try:
            with self.assertRaises((RuntimeError, OSError)):
                backup.locked_export(
                    self.session, [sys.executable, "-c", "import time; time.sleep(20)"], self.env
                )
        finally:
            timer.join()
        self.assertEqual(self.sql("SELECT pg_try_advisory_lock(74042073);"), "t")

    def test_interrupted_export_and_bounded_operation_rollback_locks(self):
        for command, limit in [
            ([sys.executable, "-c", "raise SystemExit(2)"], 5),
            ([sys.executable, "-c", "import time; time.sleep(20)"], 0),
        ]:
            with self.subTest(command=command), self.assertRaises(RuntimeError):
                backup.locked_export(self.session, command, self.env, limit=limit)
            self.sql("UPDATE public.synthetic SET id=1;")
            self.assertTrue(backup.ownership(self.session)["advisory"])

    def test_lock_contention_and_changed_transaction_are_refused(self):
        self.session.query("BEGIN; SET LOCAL lock_timeout='100ms';")
        other = backup.Session(SimpleNamespace(command=self.command, env=self.env))
        try:
            other.query("BEGIN; LOCK TABLE public.synthetic IN ACCESS EXCLUSIVE MODE;")
            with self.assertRaises(RuntimeError):
                backup.locked_export(self.session, [sys.executable, "-c", "pass"], self.env)
        finally:
            other.close()
        # A failed consistency session is never reconnected or silently reused.
        with self.assertRaises((RuntimeError, OSError)):
            self.session.query("SELECT 1;")


class ClientTLSChecks(unittest.TestCase):
    def test_pooler_backend_ssl_does_not_substitute_client_tls_proof(self):
        from unittest.mock import Mock

        session = Mock()
        session.query.side_effect = [
            "t",
            'You are connected to database "postgres".\nSSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)',
        ]
        backup.verified_client(
            session, {"PGSSLMODE": "verify-full", "PGSSLROOTCERT": "/disposable/public-ca.crt"}
        )
        self.assertEqual(session.query.call_count, 2)
        self.assertNotIn("pg_stat_ssl", str(session.query.call_args_list))

    def test_unverified_mode_wrong_identity_and_missing_or_old_tls_fail_closed(self):
        from unittest.mock import Mock

        for env, identity, info in [
            (
                {"PGSSLMODE": "require", "PGSSLROOTCERT": "/ca"},
                "t",
                "SSL connection (protocol: TLSv1.3, cipher: TEST,",
            ),
            (
                {"PGSSLMODE": "verify-full", "PGSSLROOTCERT": "/ca"},
                "f",
                "SSL connection (protocol: TLSv1.3, cipher: TEST,",
            ),
            ({"PGSSLMODE": "verify-full", "PGSSLROOTCERT": "/ca"}, "t", "no SSL"),
            (
                {"PGSSLMODE": "verify-full", "PGSSLROOTCERT": "/ca"},
                "t",
                "SSL connection (protocol: TLSv1.0, cipher: TEST,",
            ),
        ]:
            with self.subTest(env=env, identity=identity, info=info):
                session = Mock()
                session.query.side_effect = [identity, info]
                with self.assertRaises(RuntimeError):
                    backup.verified_client(session, env)
