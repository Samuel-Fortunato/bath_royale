"""Reproduce the managed feedback CHECK roundtrip in disposable PostgreSQL."""

import getpass
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from cloud_transfer import restore_schema


@unittest.skipUnless(
    all(shutil.which(name) for name in ("initdb", "pg_ctl", "pg_dump", "psql")),
    "Run in the pinned backend shell",
)
class ConstraintRoundtripTest(unittest.TestCase):
    def test_reconstruct_between_preserves_exact_definitions_rows_and_validation(self):
        with tempfile.TemporaryDirectory(prefix="bath-check-roundtrip-") as directory:
            root = Path(directory)
            env = {k: v for k, v in os.environ.items() if not k.startswith("PG")}
            env.update(
                PGHOST=directory, PGPORT="55598", PGDATABASE="postgres", PGUSER=getpass.getuser()
            )

            def run(args, statement=None):
                return subprocess.run(
                    args, input=statement, text=True, env=env, capture_output=True
                )

            def sql(statement):
                result = run(["psql", "-XqAt", "-v", "ON_ERROR_STOP=1"], statement)
                self.assertEqual(result.returncode, 0, result.stderr)
                return result.stdout.strip()

            database = str(root / "db")
            self.assertEqual(
                run(["initdb", "-D", database, "-A", "trust", "--no-locale"]).returncode, 0
            )
            started = run(
                [
                    "pg_ctl",
                    "-D",
                    database,
                    "-l",
                    str(root / "postgres.log"),
                    "-o",
                    f"-F -k {directory} -p 55598 -c listen_addresses=''",
                    "-w",
                    "start",
                ]
            )
            self.assertEqual(started.returncode, 0, started.stderr)
            try:
                sql(
                    "create schema app_private; create table app_private.alpha_feedback("
                    "app_version text check(length(app_version) between 1 and 64 and app_version ~ '^[A-Za-z0-9.+_-]+$'),"
                    "platform_version text check(length(platform_version) between 1 and 96 and platform_version !~ '[[:cntrl:]]'));"
                    "insert into app_private.alpha_feedback values ('0.1.0-alpha.1038','Synthetic Linux');"
                )
                query = (
                    "select 'app_private','alpha_feedback',conname,pg_get_constraintdef(oid),convalidated "
                    "from pg_constraint where conrelid='app_private.alpha_feedback'::regclass order by conname"
                )
                source = sql(query)
                dump = run(
                    [
                        "pg_dump",
                        "--schema=app_private",
                        "--quote-all-identifiers",
                        "--no-owner",
                        "--no-privileges",
                    ]
                )
                self.assertEqual(dump.returncode, 0, dump.stderr)
                sql("drop schema app_private cascade;" + dump.stdout)
                self.assertNotEqual(
                    source, sql(query), "Regression must reproduce the original failure"
                )
                rebuilt, decisions = restore_schema(dump.stdout, {"constraints": source})
                self.assertEqual(len(decisions), 2)
                sql("drop schema app_private cascade;" + rebuilt)
                self.assertEqual(source, sql(query))
                self.assertEqual(
                    sql("select app_version,platform_version from app_private.alpha_feedback"),
                    "0.1.0-alpha.1038|Synthetic Linux",
                )
                for app, platform in [
                    ("", "Linux"),
                    ("x" * 65, "Linux"),
                    ("bad version", "Linux"),
                    ("1", ""),
                    ("1", "x" * 97),
                    ("1", "line\nbreak"),
                ]:
                    result = run(
                        ["psql", "-XqAt", "-v", "ON_ERROR_STOP=1"],
                        "insert into app_private.alpha_feedback values ('"
                        + app
                        + "','"
                        + platform
                        + "')",
                    )
                    self.assertNotEqual(result.returncode, 0)
                # A changed bound or duplicate dump definition cannot be silently repaired.
                changed = dump.stdout.replace('"app_version") <= 64', '"app_version") <= 63')
                for text in [changed, dump.stdout + dump.stdout]:
                    with self.assertRaisesRegex(RuntimeError, "CHECK definition mismatch"):
                        restore_schema(text, {"constraints": source})
            finally:
                self.assertEqual(
                    run(["pg_ctl", "-D", database, "-m", "immediate", "-w", "stop"]).returncode, 0
                )
