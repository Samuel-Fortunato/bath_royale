"""Isolated fictional backend lifecycle. Never print subprocess output or secrets."""

import hashlib
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "bath-royale-poc"
SERVICES = ["db", "auth", "rest"]


def run(args, data=None):
    result = subprocess.run(args, input=data, text=True, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(
            "Command failed: "
            + args[0]
            + " "
            + args[1]
            + " (output suppressed to protect credentials)"
        )
    return result.stdout.strip()


def sql(statement):
    return run(
        [
            "podman",
            "exec",
            "-i",
            "bath-royale-poc-db",
            "psql",
            "-X",
            "-qAt",
            "-U",
            "supabase_admin",
            "-d",
            "postgres",
            "-v",
            "ON_ERROR_STOP=1",
        ],
        statement,
    )


def secure_write(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write(text)


def initialize():
    if STATE.is_symlink() or ROOT == STATE or ROOT in STATE.parents:
        raise RuntimeError("State must be outside the checkout and not a symlink")
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    if STATE.stat().st_uid != os.getuid() or STATE.stat().st_mode & 0o077:
        raise RuntimeError("State directory must be owned by this user and mode 0700")
    path = STATE / "secrets.json"
    if not path.exists():
        try:
            run(["podman", "volume", "inspect", "bath-royale-poc-db-data"])
        except RuntimeError:
            pass
        else:
            raise RuntimeError(
                "Database exists without credentials; recover private state or explicitly clean the PoC"
            )
        values = {
            k: secrets.token_hex(32)
            for k in [
                "POSTGRES_PASSWORD",
                "AUTH_DB_PASSWORD",
                "REST_DB_PASSWORD",
                "JWT_SECRET",
            ]
        }
        secure_write(path, json.dumps(values))
    values = json.loads(path.read_text())
    env_path = STATE / "compose.env"
    if not env_path.exists():
        secure_write(env_path, "".join(k + "=" + v + "\n" for k, v in values.items()))
    for file in [path, env_path, STATE / "accounts.json"]:
        if file.is_symlink() or (
            file.exists() and (file.stat().st_uid != os.getuid() or file.stat().st_mode & 0o077)
        ):
            raise RuntimeError("Credential files must be private regular files owned by this user")
    return values


def compose(*args):
    return run(
        [
            "podman-compose",
            "--env-file",
            str(STATE / "compose.env") if (STATE / "compose.env").exists() else os.devnull,
            "-f",
            str(ROOT / "backend/compose.yml"),
            "-p",
            "bath-royale-poc",
            *args,
        ]
    )


def request(port, path, method="GET", body=None, token=None):
    headers = {"Content-Type": "application/json", "Prefer": "return=representation"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(
        "http://127.0.0.1:" + str(port) + path,
        data=None if body is None else json.dumps(body).encode(),
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        raw = error.read()
        return error.code, json.loads(raw) if raw else None


def wait_for(check, label):
    for _ in range(90):
        try:
            if check():
                return
        except RuntimeError, OSError:
            pass
        time.sleep(1)
    raise RuntimeError(label + " readiness failed")


def bindings():
    for service in SERVICES:
        result = json.loads(run(["podman", "inspect", "bath-royale-poc-" + service]))[0]
        ports = result["NetworkSettings"].get("Ports") or {}
        for entries in ports.values():
            for entry in entries or []:
                if entry["HostIp"] != "127.0.0.1":
                    raise RuntimeError("Non-loopback binding detected")
        if result["HostConfig"].get("Privileged"):
            raise RuntimeError("Privileged container detected")
    print("PASS: rootless containers; published bindings exclusively 127.0.0.1")


def migrate():
    sql(
        "create schema if not exists bath_royale_migrations; "
        "create table if not exists bath_royale_migrations.applied "
        "(name text primary key, sha256 text not null); "
        "revoke all on schema bath_royale_migrations from public, anon, authenticated;"
    )
    for path in sorted((ROOT / "supabase/migrations").glob("*.sql")):
        content = path.read_text()
        digest = hashlib.sha256(content.encode()).hexdigest()
        previous = sql(
            "select sha256 from bath_royale_migrations.applied where name='" + path.name + "'"
        )
        if previous:
            if previous != digest:
                raise RuntimeError("Applied migration changed: " + path.name)
            continue
        sql(
            "begin;\n"
            + content
            + "\ninsert into bath_royale_migrations.applied values ('"
            + path.name
            + "','"
            + digest
            + "');\ncommit;"
        )
    run(["podman", "kill", "--signal", "SIGUSR1", "bath-royale-poc-rest"])
    print("PASS: ordered transactional migrations and checksum validation")


def start():
    values = initialize()
    if run(["podman", "info", "--format", "{{.Host.Security.Rootless}}"]) != "true":
        raise RuntimeError("Rootless Podman required")
    compose("config")  # Validate without printing the expanded, secret-bearing configuration.
    compose("up", "-d", "db")
    wait_for(lambda: sql("select 1") == "1", "PostgreSQL")
    # Runtime role wiring belongs to the local environment, not application migrations.
    sql(
        "alter role supabase_auth_admin password '" + values["AUTH_DB_PASSWORD"] + "';\n"
        "alter role authenticator password '" + values["REST_DB_PASSWORD"] + "';\n"
        "revoke supabase_admin from authenticator;\n"
        "alter role supabase_auth_admin set log_statement = none;\n"
        "alter role authenticator set log_statement = none;"
    )
    compose("up", "-d")
    bindings()
    wait_for(lambda: request(55431, "/health")[0] == 200, "Auth")
    wait_for(lambda: request(55432, "/")[0] == 200, "PostgREST")
    migrate()
    print("Ready: Auth 127.0.0.1:55431; database API 127.0.0.1:55432")


def main():
    command = sys.argv[1] if len(sys.argv) == 2 else ""
    if command not in [
        "start",
        "stop",
        "status",
        "test",
        "migrate",
        "clean",
        "measure",
    ]:
        raise RuntimeError(
            "Usage: python3 backend/poc.py start|stop|status|test|migrate|measure|clean"
        )
    if command == "start":
        start()
    elif command == "test":
        start()
        sys.path.insert(0, str(ROOT / "backend/tests"))
        from authorization import verify

        verify()
    elif command == "migrate":
        migrate()
    elif command == "stop":
        compose("stop")
        print("Stopped project containers; data and credentials retained")
    elif command == "clean":
        # Only exact project resources; never prune or remove arbitrary paths/volumes.
        compose("down", "-v")
        for name in ["secrets.json", "compose.env", "accounts.json"]:
            (STATE / name).unlink(missing_ok=True)
        print("Removed only bath-royale-poc containers/network/volumes and known credential files")
    elif command == "status":
        for service in SERVICES:
            print(
                service
                + ": "
                + run(
                    [
                        "podman",
                        "inspect",
                        "bath-royale-poc-" + service,
                        "--format",
                        "{{.State.Status}}",
                    ]
                )
            )
        bindings()
    elif command == "measure":
        containers = ["bath-royale-poc-" + s for s in SERVICES]
        stats_command = [
            "podman",
            "stats",
            "--no-stream",
            "--format",
            "{{.CPUNano}}",
            *containers,
        ]
        before = [int(value) for value in run(stats_command).splitlines()]
        started = time.monotonic()
        print("Measuring idle CPU over 10 seconds...")
        time.sleep(10)
        after = [int(value) for value in run(stats_command).splitlines()]
        elapsed = time.monotonic() - started
        for name, first, last in zip(containers, before, after, strict=True):
            print(
                name
                + " idle CPU (one core): "
                + str(round((last - first) / (elapsed * 1e7), 3))
                + "%"
            )
        print(
            run(
                [
                    "podman",
                    "stats",
                    "--no-stream",
                    "--format",
                    "{{.Name}} memory={{.MemUsage}}",
                    *["bath-royale-poc-" + s for s in SERVICES],
                ]
            )
        )
        print("Database bytes: " + sql("select pg_database_size(current_database())"))
        print(
            "Extensions: "
            + sql(
                "select string_agg(extname || ':' || extversion, ', ' order by extname) from pg_extension"
            )
        )
        for service in SERVICES:
            print(
                service
                + " image bytes: "
                + run(
                    [
                        "podman",
                        "image",
                        "inspect",
                        json.loads(run(["podman", "inspect", "bath-royale-poc-" + service]))[0][
                            "Image"
                        ],
                        "--format",
                        "{{.Size}}",
                    ]
                )
            )
        print(
            run(
                [
                    "podman",
                    "exec",
                    "bath-royale-poc-db",
                    "du",
                    "-sh",
                    "/var/lib/postgresql/data",
                ]
            )
        )


if __name__ == "__main__":
    os.umask(0o077)
    sys.stdout.reconfigure(line_buffering=True)
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        # Never include HTTP bodies, subprocess output or secret-bearing command arguments.
        print(
            "FAIL: " + str(error)
            if isinstance(error, RuntimeError)
            else "FAIL: local operation failed",
            file=sys.stderr,
        )
        sys.exit(1)
