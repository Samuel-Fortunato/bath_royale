"""Synthetic SQL regression in a temporary Unix-socket-only PostgreSQL cluster.

Runs with the locked backend shell. Never connects to an existing installation.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import cloud_transfer as transfer
from alpha_retention import plan as retention_plan


@unittest.skipUnless(
    all(shutil.which(name) for name in ("initdb", "pg_ctl", "psql")),
    "Run in nix develop .#backend for isolated PostgreSQL regression",
)
class ReconcileSQLTests(unittest.TestCase):
    def test_reconciliation_and_fail_fast_rollback(self):
        with tempfile.TemporaryDirectory(prefix="bath-transfer-sql-") as name:
            root = Path(name)
            root.chmod(0o700)
            database = root / "db"
            env = {k: v for k, v in os.environ.items() if not k.startswith("PG")}
            env.update(
                PGHOST=str(root),
                PGPORT="55599",
                PGDATABASE="postgres",
                PGUSER=__import__("getpass").getuser(),
                PSQL_HISTORY=os.devnull,
            )

            def run(args, statement=None):
                result = subprocess.run(
                    args, input=statement, env=env, capture_output=True, text=True, check=False
                )
                if result.returncode:
                    self.fail("Temporary synthetic PostgreSQL failed: " + result.stderr)
                return result.stdout.strip()

            run(["initdb", "-D", str(database), "-A", "trust", "--no-locale", "-E", "UTF8"])
            run(
                [
                    "pg_ctl",
                    "-D",
                    str(database),
                    "-l",
                    str(root / "server.log"),
                    "-o",
                    f"-F -k {root} -p 55599 -c listen_addresses=''",
                    "-w",
                    "start",
                ]
            )
            try:

                def sql(statement):
                    return run(["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1"], statement)

                local = SimpleNamespace(sql=sql)
                sql(
                    "create schema app_private; create schema bath_royale_migrations; "
                    "create role source_reader; create role target_extra; "
                    "create table public.example(id integer, value text); "
                    "create function public.example_fn(i integer) returns integer "
                    "language sql as 'select i'; "
                    "grant select(id) on public.example to source_reader with grant option;"
                )
                original = transfer.acls(local)
                sql(
                    "grant all on public.example to target_extra; "
                    "grant update(value) on public.example to target_extra; "
                    "grant usage on schema app_private to target_extra; "
                    "grant execute on function public.example_fn(integer) to target_extra; "
                    "revoke execute on function public.example_fn(integer) from public;"
                )
                self.assertNotEqual(original, transfer.acls(local))
                sql("begin;\n" + transfer.reconcile_sql(original) + "\ncommit;")
                self.assertEqual(original, transfer.acls(local))
                # A SQL error aborts the entire import transaction, including earlier writes.
                failed = subprocess.run(
                    ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1"],
                    input="begin; insert into public.example values (1,'fictional'); "
                    "select deliberately_missing(); commit;",
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(failed.returncode, 0)
                self.assertEqual(sql("select count(*) from public.example"), "0")
                # Retention uses the privately observed review date, never submission age alone.
                sql(
                    "create table app_private.alpha_feedback(id uuid primary key, status text, submitted_at timestamptz);"
                    "insert into app_private.alpha_feedback values "
                    "('00000000-0000-4000-8000-000000000001','reviewed','2000-01-01'),"
                    "('00000000-0000-4000-8000-000000000002','new','2000-01-01'),"
                    "('00000000-0000-4000-8000-000000000003','resolved','2000-01-01'),"
                    "('00000000-0000-4000-8000-000000000004','reviewed','2000-01-01');"
                )
                recent = sql("select (now()-interval '1 day')::text")
                records = [
                    {"id": f"00000000-0000-4000-8000-{i:012d}", "reviewed_at": date}
                    for i, date in [
                        (1, "2001-01-01T00:00:00Z"),
                        (2, "2001-01-01T00:00:00Z"),
                        (3, recent),
                    ]
                ]
                sql(retention_plan(records))
                self.assertEqual(sql("select count(*) from app_private.alpha_feedback"), "4")
                sql(retention_plan(records, apply=True))
                self.assertEqual(
                    sql(
                        "select string_agg(right(id::text,1),',' order by id) from app_private.alpha_feedback"
                    ),
                    "2,3,4",
                )
                sql(retention_plan(records, apply=True))
                self.assertEqual(sql("select count(*) from app_private.alpha_feedback"), "3")
            finally:
                run(["pg_ctl", "-D", str(database), "-m", "immediate", "-w", "stop"])


if __name__ == "__main__":
    unittest.main()
