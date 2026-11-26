"""Fail-fast local logical portability rehearsal; no source data writes or volume copies."""

import base64
import hashlib
import importlib.util
import json
import os
import sys
import time

import poc


def installation(name):
    os.environ["POC_INSTANCE"] = name
    spec = importlib.util.spec_from_file_location("poc_" + name, poc.ROOT / "backend/poc.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(value, label):
    if not value:
        raise RuntimeError(label)


TABLES = [
    "auth.users",
    "auth.identities",
    "public.profiles",
    "public.bathrooms",
    "public.visits",
    "public.reviews",
    "public.favourites",
    "app_private.moderators",
    "bath_royale_migrations.applied",
]


def snapshot(env):
    # Canonical complete rows include hashes privately; never print this structure.
    return {
        table: json.loads(
            env.sql(
                f"select coalesce(jsonb_agg(r order by r::text),'[]') from "
                f"(select to_jsonb(t) r from {table} t) x"
            )
        )
        for table in TABLES
    }


def inventory(env):
    queries = {
        "schemas": "select nspname from pg_namespace where nspname in "
        "('public','auth','app_private','bath_royale_migrations') order by 1",
        "tables": "select n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity "
        "from pg_class c join pg_namespace n on n.oid=c.relnamespace where "
        "n.nspname in ('public','app_private','bath_royale_migrations') and c.relkind='r' order by 1,2",
        "functions": "select p.proname,pg_get_functiondef(p.oid) from pg_proc p join "
        "pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','app_private') "
        "order by p.proname,pg_get_function_identity_arguments(p.oid)",
        "triggers": "select event_object_table,trigger_name,action_statement from "
        "information_schema.triggers where trigger_schema='public' order by 1,2,3",
        "roles": "select rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,"
        "rolreplication,rolbypassrls,rolconfig from pg_roles order by rolname",
        "memberships": "select roleid::regrole::text,member::regrole::text,admin_option "
        "from pg_auth_members order by 1,2",
        "extensions": "select extname,extversion from pg_extension order by 1",
        "policies": "select * from pg_policies order by schemaname,tablename,policyname",
        "constraints": "select n.nspname,c.relname,k.conname,pg_get_constraintdef(k.oid),"
        "k.convalidated from pg_constraint k join pg_class c on c.oid=k.conrelid "
        "join pg_namespace n on n.oid=c.relnamespace where n.nspname in "
        "('public','app_private') order by 1,2,3",
        "grants": "select table_schema,table_name,grantee,privilege_type from "
        "information_schema.table_privileges where table_schema in "
        "('public','app_private','bath_royale_migrations') order by 1,2,3,4",
        "columns": "select table_schema,table_name,column_name,grantee,privilege_type from "
        "information_schema.column_privileges where table_schema in "
        "('public','app_private') order by 1,2,3,4,5",
        "auth_migrations": "select * from auth.schema_migrations order by version",
        "server": "select version()",
    }
    result = {name: env.sql(query) for name, query in queries.items()}
    # pg_dump flattens the nested AND in this one CHECK. Normalize only that
    # known equivalent expression; retain every other definition verbatim.
    result["constraints"] = result["constraints"].replace(
        "CHECK ((((char_length(comment) >= 1) AND (char_length(comment) <= 500)) "
        "AND (comment = btrim(comment))))",
        "CHECK (((char_length(comment) >= 1) AND (char_length(comment) <= 500) "
        "AND (comment = btrim(comment))))",
    )
    return result


def dump(env, *args):
    return (
        env.run(
            [
                "podman",
                "exec",
                env.PROJECT + "-db",
                "pg_dump",
                "-U",
                "supabase_admin",
                "-d",
                "postgres",
                "--no-owner",
                *args,
            ]
        )
        + "\n"
    )


def login(env, account):
    status, session = env.request(env.AUTH_PORT, "/token?grant_type=password", "POST", account)
    require(status == 200 and "access_token" in session, "Original-password login failed")
    return session


def check_sessions(destination, accounts, old):
    for account, previous in zip(accounts, old, strict=True):
        claims = json.loads(
            base64.urlsafe_b64decode(previous["access_token"].split(".")[1] + "===")
        )
        require(claims["exp"] > time.time(), "Source token expired before isolation check")
        session = login(destination, account)
        require(session["user"]["id"] == previous["user"]["id"], "Auth UUID changed")
        require(
            destination.request(destination.REST_PORT, "/visits", token=previous["access_token"])[0]
            == 401,
            "Source access token authorized destination",
        )
        require(
            destination.request(
                destination.AUTH_PORT,
                "/token?grant_type=refresh_token",
                "POST",
                {"refresh_token": previous["refresh_token"]},
            )[0]
            in (400, 401),
            "Source refresh session migrated",
        )
        status, refreshed = destination.request(
            destination.AUTH_PORT,
            "/token?grant_type=refresh_token",
            "POST",
            {"refresh_token": session["refresh_token"]},
        )
        require(
            status == 200 and refreshed["user"]["id"] == previous["user"]["id"],
            "Destination refresh failed",
        )
        require(
            destination.request(destination.REST_PORT, "/visits", token=refreshed["access_token"])[
                0
            ]
            == 200,
            "Refreshed API session failed",
        )


def verify_exports(bundle, files):
    for name, record in files.items():
        require(
            hashlib.sha256((bundle / name).read_bytes()).hexdigest() == record["sha256"],
            "Export checksum mismatch",
        )


def rehearse():
    source, target = installation("source"), installation("destination")
    source.start()
    require((source.STATE / "accounts.json").exists(), "Run source fictional tests first")
    # Refuse to reuse an old destination, including after an interrupted rehearsal.
    try:
        target.run(["podman", "volume", "inspect", target.PROJECT + "-db-data"])
    except RuntimeError:
        pass
    else:
        raise RuntimeError("Destination exists; explicitly clean only destination before retry")
    target.start(migrations=False)
    source_secrets, target_secrets = source.initialize(), target.initialize()
    require(
        all(source_secrets[k] != target_secrets[k] for k in source_secrets),
        "Destination credentials must be independent",
    )
    print("PASS: independently initialized destination and credentials", flush=True)
    accounts = json.loads((source.STATE / "accounts.json").read_text())
    old = [login(source, account) for account in accounts]
    before = snapshot(source)
    require(
        len(before["auth.users"]) == 2 and len(before["public.reviews"]) >= 2,
        "Expected existing A/B sample required",
    )
    resources = source.run(
        [
            "podman",
            "stats",
            "--no-stream",
            "--format",
            "{{.Name}} memory={{.MemUsage}} cpu={{.CPU}}",
            *[env.PROJECT + "-" + service for env in (source, target) for service in env.SERVICES],
        ]
    )
    # Freeze every service writer before exporting; DB remains up for logical tools only.
    source.compose("stop", "auth", "rest")
    bundle = source.STATE / ("export-" + str(time.time_ns()))
    bundle.mkdir(mode=0o700)
    started = time.monotonic()
    schema = dump(
        source,
        "--schema-only",
        "--clean",
        "--if-exists",
        "--schema=public",
        "--schema=app_private",
        "--schema=bath_royale_migrations",
    )
    data = dump(source, "--data-only", *["--table=" + table for table in TABLES])
    for name, content in [("schema.sql", schema), ("data.sql", data)]:
        source.secure_write(bundle / name, content)
    inv = inventory(source)
    source.secure_write(bundle / "inventory.json", json.dumps(inv, indent=2))
    source.secure_write(bundle / "compose.yml", (poc.ROOT / "backend/compose.yml").read_text())
    source.secure_write(
        bundle / "components.json",
        json.dumps(
            {
                "images": [
                    line.strip()
                    for line in (poc.ROOT / "backend/compose.yml").read_text().splitlines()
                    if line.strip().startswith("image:")
                ],
                "pg_dump": source.run(
                    ["podman", "exec", source.PROJECT + "-db", "pg_dump", "--version"]
                ),
                "nix_lock_sha256": hashlib.sha256(
                    (poc.ROOT / "flake.lock").read_bytes()
                ).hexdigest(),
                "source_project": source.PROJECT,
                "destination_project": target.PROJECT,
                "scope": TABLES,
                "sessions": "excluded; fresh login required",
            },
            indent=2,
        ),
    )
    export_seconds = round(time.monotonic() - started, 3)
    files = {
        path.name: {
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        for path in bundle.iterdir()
    }
    source.secure_write(bundle / "manifest.json", json.dumps(files, indent=2))
    source.compose("stop")
    require(
        all(
            source.run(
                [
                    "podman",
                    "inspect",
                    source.PROJECT + "-" + service,
                    "--format",
                    "{{.State.Running}}",
                ]
            )
            == "false"
            for service in source.SERVICES
        ),
        "Source must be stopped",
    )
    target.compose("stop", "auth", "rest")
    started = time.monotonic()
    verify_exports(bundle, files)
    target.sql(
        "begin;\n"
        + (bundle / "schema.sql").read_text()
        + "\nset local session_replication_role=replica;\n"
        + (bundle / "data.sql").read_text()
        + "\ncommit;"
    )
    restore_seconds = round(time.monotonic() - started, 3)
    require(snapshot(target) == before, "Restored rows differ (IDs/content/hashes/timestamps)")
    require(inventory(target) == inv, "Restored schema/roles/grants/policies differ")
    # Force PostgreSQL to recheck every restored FK rather than trusting validated flags.
    for table in TABLES:
        constraints = json.loads(
            target.sql(
                f"select coalesce(json_agg(x),'[]') from (select "
                f"conname,pg_get_constraintdef(oid) definition from pg_constraint where conrelid='{table}'"
                "::regclass and contype='f') x"
            )
        )
        for constraint in constraints:
            name, definition = constraint["conname"], constraint["definition"]
            target.sql(
                f'begin; alter table {table} drop constraint "{name}"; '
                f'alter table {table} add constraint "{name}" {definition}; rollback;'
            )
    orphan_count = target.sql(
        "select count(*) from public.reviews r left join public.visits v "
        "on (r.visit_id,r.author_id,r.bathroom_id)=(v.id,v.owner_id,v.bathroom_id) where v.id is null"
    )
    require(orphan_count == "0", "Orphaned or mismatched review relationships")
    print(
        "PASS: complete row, identity/hash, timestamp, migration and inventory comparison",
        flush=True,
    )
    target.secure_write(target.STATE / "accounts.json", json.dumps(accounts))
    target.start()  # Migrated history must prevent initial migration reapplication.
    check_sessions(target, accounts, old)
    # Auth updates last_sign_in/session state; app records must remain exact.
    require(
        all(snapshot(target)[t] == before[t] for t in TABLES if not t.startswith("auth.")),
        "Application data changed during login",
    )
    restart_before = snapshot(target)
    target.compose("stop")
    target.start()
    require(snapshot(target) == restart_before, "Restart changed restored records")
    require(
        all(login(target, a)["user"]["id"] == old[i]["user"]["id"] for i, a in enumerate(accounts)),
        "Restart login identity changed",
    )
    print(
        "PASS: original passwords/UUIDs, refresh, source-token rejection and independent restart",
        flush=True,
    )
    # Only now allow the destructive fixture-based matrix on disposable destination.
    sys.modules["poc"] = target
    sys.path.insert(0, str(poc.ROOT / "backend/tests"))
    from authorization import verify

    verify(existing_only=True)
    from authorization import COUNT

    report = {
        "exports": files,
        "export_seconds": export_seconds,
        "restore_seconds": restore_seconds,
        "rows": {table: len(rows) for table, rows in before.items()},
        "both_running_resources": resources,
        "source_stopped": True,
        "preservation": "exact",
        "authorization_assertions": COUNT,
        "object_storage": "not selected; untested",
    }
    source.secure_write(bundle / "evidence.json", json.dumps(report, indent=2))
    print(json.dumps(report, indent=2), flush=True)
    print("Private export: " + str(bundle), flush=True)


if __name__ == "__main__":
    os.umask(0o077)
    sys.stdout.reconfigure(line_buffering=True)
    try:
        rehearse()
    except (RuntimeError, OSError, ValueError) as error:
        print(
            "FAIL: "
            + (str(error) if isinstance(error, RuntimeError) else "local operation failed")
            + "; source retained, no automatic cleanup",
            file=sys.stderr,
        )
        raise SystemExit(1) from None
