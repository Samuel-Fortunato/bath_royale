"""Version 1 supervised backup session; SQL/format remain application-owned.

The parent keeps a database advisory lock until EOF/finish. Export uses a separate
transaction with the approved complete SHARE lock scope, checked every second.
Only explicit A7.2 disposable sources are accepted in development.
"""

import argparse
import contextlib
import json
import os
import selectors
import shutil
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path

import administration as admin
import cloud_transfer as transfer
import migration

KEY = 74042073


class Session:
    def __init__(self, db):
        self.process = subprocess.Popen(
            db.command,
            env=db.env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = b""

    def query(self, sql, timeout=25):
        marker = uuid.uuid4().hex
        self.process.stdin.write((sql + "\nSELECT '" + marker + "';\n").encode())
        self.process.stdin.flush()
        deadline = time.monotonic() + timeout
        lines = []
        while True:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                if line == marker.encode():
                    return b"\n".join(lines).decode().strip()
                lines.append(line)
            admin.require(time.monotonic() < deadline, "A sessão de backup não respondeu.")
            events = self.selector.select(max(0, deadline - time.monotonic()))
            admin.require(bool(events), "O tempo da sessão de backup esgotou-se.")
            data = os.read(self.process.stdout.fileno(), 65536)
            admin.require(bool(data), "A ligação de consistência foi perdida.")
            self.buffer += data

    def close(self):
        try:
            if self.process.poll() is None:
                self.query("ROLLBACK; SELECT pg_advisory_unlock_all();", timeout=3)
        except RuntimeError, OSError:
            pass
        finally:
            with contextlib.suppress(OSError):
                self.process.stdin.close()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
            self.selector.close()
            self.process.stdout.close()


def ownership(session, *, transaction=False):
    # Check the same physical backend and its actual granted locks, not just a flag.
    scope = migration.TABLES + sorted(transfer.SESSIONS)
    relations = ",".join(admin.literal(t) + "::regclass" for t in scope)
    return json.loads(
        session.query(
            "SELECT json_build_object('pid',pg_backend_pid(),'advisory',"
            f"EXISTS(SELECT 1 FROM pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory' "
            f"AND objid={KEY} AND classid=0 AND objsubid=1 AND granted),'xid',"
            + ("pg_current_xact_id()::text" if transaction else "NULL")
            + ",'tables',"
            + (
                "(SELECT count(DISTINCT relation) FROM pg_locks WHERE pid=pg_backend_pid() "
                f"AND mode='ShareLock' AND granted AND relation IN ({relations}))"
                if transaction
                else "0"
            )
            + ");"
        )
    )


def locked_export(session, command, env, *, limit=150):
    scope = migration.TABLES + sorted(transfer.SESSIONS)
    session.query(
        "BEGIN; SET LOCAL lock_timeout='20s'; SET LOCAL statement_timeout='25s'; "
        "SET LOCAL idle_in_transaction_session_timeout='180s'; LOCK TABLE "
        + ",".join(scope)
        + " IN SHARE MODE; "
        + admin.schema_guard()
    )
    owner = ownership(session, transaction=True)
    admin.require(owner["advisory"] and owner["tables"] == len(scope), "Bloqueios incompletos.")
    child = None
    try:
        child = subprocess.Popen(
            command,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.monotonic() + limit
        while True:
            admin.require(
                ownership(session, transaction=True) == owner,
                "O proprietário dos bloqueios mudou; backup rejeitado.",
            )
            if child.poll() is not None:
                admin.require(child.returncode == 0, "A exportação falhou; backup rejeitado.")
                break
            admin.require(time.monotonic() < deadline, "A exportação excedeu o limite.")
            time.sleep(1)
    finally:
        if child is not None:
            # Also stop pipeline descendants after failure/interruption.
            with contextlib.suppress(ProcessLookupError):
                os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(child.pid, signal.SIGKILL)
                child.wait()
        session.query("ROLLBACK;", timeout=5)


def metadata(bundle, target, environment):
    files = transfer.load_bundle(bundle)
    scope = transfer.bundle_scope(files)
    snapshot = json.loads(files["before.json"])
    return {
        "version": 1,
        "target": target,
        "environment": environment,
        "scope": scope,
        "schema": {r["name"]: r["sha256"] for r in snapshot["bath_royale_migrations.applied"]},
        "bundle_sha256": admin.hashlib.sha256((bundle / "manifest.json").read_bytes()).hexdigest(),
        "components": json.loads(files["components.json"]),
    }


def worker(args, db):
    # Explicit guarded adapter, same native CLI filtering/format as managed exports.
    def dump(script, remote):
        command = ["bash", "-e", "-o", "pipefail"]
        if args.environment == "development":
            command = db.command[: db.command.index("psql")] + [
                "PGHOST=/run/postgresql",
                "PGPORT=5432",
                "PGDATABASE=postgres",
                "PGUSER=supabase_admin",
                "PGOPTIONS=-c lock_timeout=20000 -c statement_timeout=120000",
                "PATH="
                + str(Path(shutil.which("pg_dump")).resolve().parent)
                + ":/usr/local/bin:/usr/bin:/bin",
                *command,
            ]
        return subprocess.run(
            command,
            input=script,
            env=remote.env,
            text=True,
            capture_output=True,
            check=False,
            timeout=120,
        )

    args.project = db.target.removeprefix("supabase:")
    args.legacy_core = False
    transfer.export_bundle(
        args,
        remote=db,
        dump_runner=dump,
        consistency="supervised complete SHARE locks; multiple snapshots",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", required=True, choices=["managed", "development"])
    parser.add_argument("--state-directory", type=Path)
    parser.add_argument("--development-container")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--bundle", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    session = None
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(2))
    try:
        db = admin.Database(
            args.environment, state=args.state_directory, container=args.development_container
        )
        if args.worker:
            admin.require(args.bundle is not None, "Falta o bundle de trabalho.")
            worker(args, db)
            return 0
        admin.require(args.bundle is None, "O bundle é selecionado pelo protocolo.")
        session = Session(db)
        acquired = session.query(
            "SET statement_timeout='25s'; SET idle_session_timeout='120s'; "
            f"SELECT pg_try_advisory_lock({KEY});"
        )
        admin.require(acquired == "t", "Já existe uma operação de backup neste projeto.")
        if args.environment == "managed":
            admin.require(
                session.query(
                    "SELECT current_database()='postgres' AND session_user='postgres' AND "
                    "(SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid());"
                )
                == "t",
                "A sessão não comprovou a base de dados/utilizador/TLS esperados.",
            )
        owner = ownership(session)
        admin.require(owner["advisory"], "Falta o bloqueio entre computadores.")
        print(json.dumps({"version": 1, "target": db.target}), flush=True)
        selector = selectors.DefaultSelector()
        selector.register(sys.stdin, selectors.EVENT_READ)
        try:
            while True:
                admin.require(ownership(session) == owner, "A sessão de backup foi perdida.")
                if not selector.select(5):
                    continue
                line = sys.stdin.readline()
                if not line:
                    break
                request = json.loads(line)
                if request == {"operation": "check"}:
                    print(json.dumps({"alive": True}), flush=True)
                    continue
                if request == {"operation": "finish"}:
                    print(json.dumps({"finished": True}), flush=True)
                    break
                admin.require(
                    set(request) == {"operation", "bundle"} and request["operation"] == "export",
                    "Pedido de backup inválido.",
                )
                bundle = Path(request["bundle"])
                command = [
                    sys.executable,
                    str(Path(__file__).resolve()),
                    "--worker",
                    "--environment",
                    args.environment,
                    "--bundle",
                    str(bundle),
                ]
                if args.environment == "managed":
                    command += ["--state-directory", str(args.state_directory)]
                else:
                    command += ["--development-container", args.development_container]
                locked_export(session, command, db.env)
                print(json.dumps(metadata(bundle, db.target, args.environment)), flush=True)
        finally:
            selector.close()
        return 0
    except RuntimeError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired:
        print(
            json.dumps(
                {"error": "A sessão/exportação de backup falhou; nenhum backup foi publicado."}
            ),
            flush=True,
        )
        return 2
    finally:
        if session is not None:
            session.close()


if __name__ == "__main__":
    sys.exit(main())
