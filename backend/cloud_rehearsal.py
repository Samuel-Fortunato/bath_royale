"""Bounded managed fictional-data rehearsal; private state and fail-fast operations."""

import hashlib
import importlib
import json
import os
import stat
import sys
import urllib.error
import urllib.request

import cloud
import poc


def managed():
    cloud.preflight()
    api = cloud.private_json(cloud.STATE / "api.json", ["url", "publishable_key"])
    env = cloud.connection_env(
        cloud.private_json(cloud.STATE / "connection.json", ["database_url"]),
        api,
        cloud.STATE / "root.crt",
    )

    def request(port, path, method="GET", body=None, token=None):
        if path == "/signup":
            flags = cloud.auth_settings(api)
            cloud.require(
                flags == {"disable_signup": False, "mailer_autoconfirm": True},
                "No-email signup guard failed",
            )
        headers = {
            "apikey": api["publishable_key"],
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }
        if token:
            headers["Authorization"] = "Bearer " + token
        prefix = "/auth/v1" if port == 1 else "/rest/v1"
        req = urllib.request.Request(
            cloud.URL + prefix + path,
            data=None if body is None else json.dumps(body).encode(),
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                raw = response.read()
                return response.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read()
            return error.code, json.loads(raw) if raw else None

    # Fresh module instance, no changes to the two preserved local installations.
    import types

    remote = types.SimpleNamespace(
        AUTH_PORT=1,
        REST_PORT=2,
        STATE=cloud.STATE,
        ROOT=poc.ROOT,
        secure_write=poc.secure_write,
        request=request,
        sql=lambda statement: cloud.sql(env, statement),
        env=env,
    )
    return remote


def validate_accounts(path):
    cloud.require(not path.is_symlink() and path.is_file(), "Missing regular accounts file")
    info = path.stat()
    cloud.require(
        info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o600,
        "Accounts file must be owner-only mode 0600",
    )
    accounts = json.loads(path.read_text())
    cloud.require(
        isinstance(accounts, list)
        and len(accounts) == 2
        and all(isinstance(a, dict) for a in accounts),
        "Expected two fictional accounts",
    )
    cloud.require(
        {a.get("email") for a in accounts}
        == {"bath-royale-fictional-a@example.invalid", "bath-royale-fictional-b@example.invalid"}
        and all(isinstance(a.get("password"), str) and a["password"] for a in accounts),
        "Unexpected fictional account credentials",
    )
    return accounts


def prepare(remote):
    # Inventory before any mutation; reject non-rehearsal relations and identities.
    relations = remote.sql(
        "select n.nspname||'.'||c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace "
        "where n.nspname in ('public','app_private','bath_royale_migrations') "
        "and c.relkind in ('r','v','m') order by 1"
    ).splitlines()
    allowed = {"public." + t for t in ["profiles", "bathrooms", "visits", "reviews", "favourites"]}
    allowed |= {"app_private.moderators", "bath_royale_migrations.applied"}
    cloud.require(set(relations) <= allowed, "Unrelated application relations; abort")
    count = int(remote.sql("select count(*) from auth.users"))
    if count:
        cloud.require(
            (cloud.STATE / "accounts.json").exists(),
            "Existing users without retained credentials; abort",
        )
        accounts = validate_accounts(cloud.STATE / "accounts.json")
        emails = ",".join("'" + a["email"].replace("'", "''") + "'" for a in accounts)
        cloud.require(
            remote.sql(f"select count(*) from auth.users where email not in ({emails})") == "0",
            "Unrelated Auth users; abort",
        )
    remote.sql(
        "begin; create schema if not exists bath_royale_migrations; "
        "create table if not exists bath_royale_migrations.applied (name text primary key, sha256 text not null); "
        "revoke all on schema bath_royale_migrations from public, anon, authenticated; commit;"
    )
    for path in sorted((poc.ROOT / "supabase/migrations").glob("*.sql")):
        content = path.read_text()
        digest = hashlib.sha256(content.encode()).hexdigest()
        previous = remote.sql(
            "select sha256 from bath_royale_migrations.applied where name='" + path.name + "'"
        )
        if previous:
            cloud.require(previous == digest, "Applied migration checksum changed")
        else:
            cloud.require(not relations, "Existing untracked application objects; abort")
            remote.sql(
                "begin;\n"
                + content
                + "\ninsert into bath_royale_migrations.applied values ('"
                + path.name
                + "','"
                + digest
                + "'); notify pgrst, 'reload schema'; commit;"
            )
    print("PASS: managed migration checksums; no-email guard before each signup", flush=True)
    sys.modules["poc"] = remote
    sys.path.insert(0, str(poc.ROOT / "backend/tests"))
    suite = importlib.import_module("authorization")
    suite.verify(check_expiry=False)


if __name__ == "__main__":
    os.umask(0o077)
    sys.stdout.reconfigure(line_buffering=True)
    try:
        prepare(managed())
    except (RuntimeError, OSError, ValueError) as error:
        print(
            "FAIL: "
            + (
                str(error)
                if isinstance(error, RuntimeError)
                else "operation failed; diagnostics suppressed"
            ),
            file=sys.stderr,
        )
        sys.exit(1)
