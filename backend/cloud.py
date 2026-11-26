"""Managed rehearsal preflight. Credentials and SQL diagnostics never reach stdout."""

import json
import os
import stat
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PROJECT = "eiitfxbmavmqafqwfxiy"
URL = f"https://{PROJECT}.supabase.co"
STATE = Path.home() / ".local/state/bath-royale-cloud-test"


def require(condition, label):
    if not condition:
        raise RuntimeError(label)


def private_json(path, fields):
    require(not path.is_symlink() and path.is_file(), f"Missing regular file: {path.name}")
    info = path.stat()
    require(
        info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o600,
        f"Require owner-only mode 0600: {path.name}",
    )
    value = json.loads(path.read_text())
    require(
        all(isinstance(value.get(k), str) and value[k] for k in fields),
        f"Missing required fields: {path.name}",
    )
    return value


def connection_env(connection, api, certificate):
    require(api["url"].rstrip("/") == URL, "Unexpected API project; abort")
    parsed = urllib.parse.urlsplit(connection["database_url"])
    require(
        parsed.scheme in ("postgres", "postgresql")
        and urllib.parse.unquote(parsed.username or "") == f"postgres.{PROJECT}"
        and parsed.port == 5432
        and (parsed.hostname or "").endswith(".pooler.supabase.com")
        and parsed.path == "/postgres"
        and bool(parsed.password),
        "Unexpected database target/session pooler; abort",
    )
    require(
        certificate.is_file() and not certificate.is_symlink(),
        "Download project CA from Database Settings to private state root.crt",
    )
    # Ignore URL query parameters: neither credentials nor TLS policy may be overridden.
    env = {k: v for k, v in os.environ.items() if not k.startswith("PG")}
    env.update(
        PGHOST=parsed.hostname,
        PGPORT="5432",
        PGUSER=urllib.parse.unquote(parsed.username),
        PGPASSWORD=urllib.parse.unquote(parsed.password),
        PGDATABASE="postgres",
        PGSSLMODE="verify-full",
        PGSSLROOTCERT=str(certificate.resolve()),
        PGCONNECT_TIMEOUT="15",
        PSQL_HISTORY=os.devnull,
    )
    return env


def sql(env, statement):
    result = subprocess.run(
        ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1"],
        input=statement,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        error = result.stderr.lower()
        category = (
            "network (check hotspot/eduroam)"
            if any(word in error for word in ("timeout", "resolve", "unreachable", "refused"))
            else "TLS certificate/hostname"
            if any(word in error for word in ("certificate", "ssl"))
            else "database authentication/SQL (diagnostics suppressed)"
        )
        raise RuntimeError("Database preflight failed: " + category)
    return result.stdout.strip()


def auth_settings(api):
    req = urllib.request.Request(
        URL + "/auth/v1/settings", headers={"apikey": api["publishable_key"]}
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        result = json.load(response)
    return {key: result.get(key) for key in ("disable_signup", "mailer_autoconfirm")}


def preflight():
    connection = private_json(STATE / "connection.json", ["database_url"])
    api = private_json(STATE / "api.json", ["url", "publishable_key"])
    require(api["url"].rstrip("/") == URL, "Unexpected API project; abort")
    settings = auth_settings(api)
    print("Auth signup enabled:", settings["disable_signup"] is False)
    print("Auth email autoconfirm:", settings["mailer_autoconfirm"] is True)
    env = connection_env(connection, api, STATE / "root.crt")
    # Output deliberately restricted to versions and counts, never row content.
    print("PostgreSQL:", sql(env, "show server_version"))
    print("Auth users:", sql(env, "select count(*) from auth.users"))
    print(
        "Application relations:",
        sql(
            env,
            "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace "
            "where n.nspname in ('public','app_private','bath_royale_migrations') "
            "and c.relkind in ('r','v','m')",
        ),
    )
    require(
        settings["mailer_autoconfirm"] is True and settings["disable_signup"] is False,
        "Enable signup and disable Confirm email in this test project before provisioning",
    )
    print("PASS: read-only managed preflight; no deployment or signup performed")


if __name__ == "__main__":
    try:
        preflight()
    except RuntimeError as error:
        print("FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
    except OSError, ValueError, urllib.error.URLError:
        print("FAIL: preflight operation failed; diagnostics suppressed", file=sys.stderr)
        sys.exit(1)
