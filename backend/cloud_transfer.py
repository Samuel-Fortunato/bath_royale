"""Managed logical export, fresh local restore and independent preservation verification.

Derived from the private Phase 2.1C scripts; never runs the fixture matrix or cleanup.
All bundles contain sensitive material and must stay outside the checkout.
"""

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import cloud
import migration
import poc

require = cloud.require
SCHEMAS = "('public','app_private','bath_royale_migrations')"
SESSIONS = {"auth.sessions", "auth.refresh_tokens", "auth.mfa_amr_claims"}
EMPTY_OMISSIONS = {
    "auth.custom_oauth_providers",
    *(
        "storage." + name
        for name in (
            "buckets",
            "bucket_lifecycle_states",
            "buckets_analytics",
            "buckets_vectors",
            "lifecycle_abandoned_artifacts",
            "objects",
            "s3_multipart_uploads",
            "s3_multipart_uploads_parts",
            "vector_indexes",
        )
    ),
}
REALTIME_GRANT = 'GRANT SET ON PARAMETER "log_min_messages" TO "supabase_realtime_admin";'
INVENTORY_KEYS = (
    "schemas",
    "tables",
    "functions",
    "triggers",
    "policies",
    "constraints",
    "grants",
    "columns",
)
AUTH_COLUMNS = (
    "select table_schema||'.'||table_name tab,column_name col,data_type,udt_name "
    "from information_schema.columns order by 1,ordinal_position"
)
OBJECTS = f"""
select 'TABLE '||quote_ident(n.nspname)||'.'||quote_ident(c.relname) object,
coalesce(c.relacl,acldefault('r',c.relowner)) acl
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname in {SCHEMAS} and c.relkind in ('r','v','m')
union all
select 'FUNCTION '||quote_ident(n.nspname)||'.'||quote_ident(p.proname)||'('||
pg_get_function_identity_arguments(p.oid)||')',coalesce(p.proacl,acldefault('f',p.proowner))
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in {SCHEMAS}
union all
select 'SCHEMA '||quote_ident(nspname),coalesce(nspacl,acldefault('n',nspowner))
from pg_namespace where nspname in {SCHEMAS}
"""
ACL = f"""select x.object,a.privilege_type,a.is_grantable,
case when a.grantee=0 then 'PUBLIC' else quote_ident(pg_get_userbyid(a.grantee)) end role
from ({OBJECTS}) x cross join lateral aclexplode(x.acl) a"""
COLUMN_ACL = f"""select quote_ident(n.nspname)||'.'||quote_ident(c.relname) tab,
quote_ident(attname) col,a.privilege_type,a.is_grantable,
case when a.grantee=0 then 'PUBLIC' else quote_ident(pg_get_userbyid(a.grantee)) end role
from pg_attribute at join pg_class c on c.oid=at.attrelid
join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(at.attacl) a
where n.nspname in {SCHEMAS}"""


def private_path(path, directory=False):
    require(not path.is_symlink(), "Symlink refused")
    info = path.stat()
    require(
        info.st_uid == os.getuid()
        and stat.S_IMODE(info.st_mode) == (0o700 if directory else 0o600),
        "Private owner/mode required",
    )
    require(
        stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode),
        "Regular private path required",
    )


def outside_checkout(path):
    resolved = path.resolve()
    require(
        resolved != poc.ROOT and poc.ROOT not in resolved.parents,
        "Private state/bundles must be outside checkout",
    )
    return resolved


def write_json(path, value):
    poc.secure_write(path, json.dumps(value, indent=2) + "\n")


def seal(directory):
    records = {
        p.name: {"bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
        for p in directory.iterdir()
        if p.name != "manifest.json"
    }
    write_json(directory / "manifest.json", {"format": 1, "files": records})


def load_bundle(directory, required=None):
    outside_checkout(directory)
    private_path(directory, directory=True)
    private_path(directory / "manifest.json")
    manifest = json.loads((directory / "manifest.json").read_text())
    require(isinstance(manifest, dict) and manifest.get("format") == 1, "Unsupported bundle format")
    records = manifest["files"]
    require(isinstance(records, dict), "Invalid manifest records")
    if required is None:
        required = {
            "roles.sql",
            "schema.sql",
            "data.sql",
            "before.json",
            "inventory.json",
            "acls.json",
            "columns.json",
            "components.json",
        }
    require(required <= records.keys(), "Incomplete bundle")
    require(
        set(records) == {p.name for p in directory.iterdir()} - {"manifest.json"},
        "Unmanifested/missing bundle files",
    )
    for name, record in records.items():
        require(Path(name).name == name and name not in (".", ".."), "Invalid manifest name")
        require(
            isinstance(record, dict)
            and type(record.get("bytes")) is int
            and record["bytes"] >= 0
            and isinstance(record.get("sha256"), str),
            "Invalid file record",
        )
        path = directory / name
        private_path(path)
        content = path.read_bytes()
        require(
            len(content) == record["bytes"]
            and hashlib.sha256(content).hexdigest() == record["sha256"],
            "Bundle checksum mismatch",
        )
    return {name: (directory / name).read_text() for name in required}


def json_query(env, query):
    return json.loads(
        env.sql("set search_path=''; select coalesce(json_agg(x),'[]') from (" + query + ") x")
    )


def acls(env):
    # Expand implicit defaults too: NULL proacl includes PUBLIC EXECUTE.
    return {
        "objects": sorted(json_query(env, ACL), key=lambda x: json.dumps(x, sort_keys=True)),
        "columns": sorted(json_query(env, COLUMN_ACL), key=lambda x: json.dumps(x, sort_keys=True)),
    }


def inventory(env):
    return migration.inventory(SimpleNamespace(sql=lambda q: env.sql("set search_path='';" + q)))


def managed(state, project):
    private_path(state, directory=True)
    outside_checkout(state)
    require(re.fullmatch("[a-z]{20}", project), "Explicit managed project reference required")
    # Reuse the reviewed endpoint/TLS guard without changing its project defaults globally.
    import importlib.util

    spec = importlib.util.spec_from_file_location("transfer_cloud", poc.ROOT / "backend/cloud.py")
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    guard.PROJECT, guard.URL = project, f"https://{project}.supabase.co"
    connection = guard.private_json(state / "connection.json", ["database_url"])
    api = guard.private_json(state / "api.json", ["url", "publishable_key"])
    private_path(state / "root.crt")
    env = guard.connection_env(connection, api, state / "root.crt")
    remote = SimpleNamespace(env=env, sql=lambda q: cloud.sql(env, q))
    # No Auth readiness/signup requirement: export is read-only and may follow signup closure.
    require(remote.sql("select current_database()") == "postgres", "Unexpected database")
    return remote


def filtered_script(script):
    require("pg_dump" in script, "CLI did not produce a dump script")
    # Preserve every CLI exclusion/filter; only libpq exports are replaced by verified env.
    return "\n".join(line for line in script.splitlines() if not line.startswith("export PG"))


def export_bundle(args):
    directory = args.bundle
    outside_checkout(directory)
    private_path(directory.parent, directory=True)
    require(not directory.exists() and not directory.is_symlink(), "Bundle already exists")
    remote = managed(args.source_state, args.project)
    directory.mkdir(mode=0o700)
    before = migration.snapshot(remote)
    write_json(directory / "before.json", before)
    write_json(directory / "inventory.json", inventory(remote))
    write_json(directory / "acls.json", acls(remote))
    write_json(directory / "columns.json", json_query(remote, AUTH_COLUMNS))
    require(poc.run(["supabase", "--version"]) == "2.111.0", "Require locked Supabase CLI 2.111.0")
    require("17.12" in poc.run(["pg_dump", "--version"]), "Require locked pg_dump 17.12")
    for name, flags in [
        ("roles", ["--role-only"]),
        ("schema", []),
        ("data", ["--data-only", "--use-copy"]),
    ]:
        script = filtered_script(
            poc.run(
                [
                    "supabase",
                    "db",
                    "dump",
                    "--db-url",
                    "postgresql://postgres:placeholder@127.0.0.1:5432/postgres",
                    "--dry-run",
                    *flags,
                ]
            )
        )
        poc.secure_write(directory / (name + "-command.sh"), script)
        result = subprocess.run(
            ["bash", "-e", "-o", "pipefail"],
            input=script,
            env=remote.env,
            text=True,
            capture_output=True,
            check=False,
        )
        require(result.returncode == 0, "Filtered export failed; diagnostics suppressed")
        poc.secure_write(directory / (name + ".sql"), result.stdout)
    require(migration.snapshot(remote) == before, "Source changed during export")
    write_json(
        directory / "components.json",
        {
            "project": args.project,
            "cli": "2.111.0",
            "pg_dump": "17.12",
            "flake_lock_sha256": hashlib.sha256((poc.ROOT / "flake.lock").read_bytes()).hexdigest(),
            "compose_sha256": hashlib.sha256(
                (poc.ROOT / "backend/compose.yml").read_bytes()
            ).hexdigest(),
            "scope": migration.TABLES,
            "consistency": "operator-quiesced; not a maintenance lock",
        },
    )
    seal(directory)
    load_bundle(directory)
    print("PASS: private filtered export sealed; no source writes")


def adapt_data(text, columns):
    """Fail closed on unknown or populated incompatible sections; retain originals."""
    lines = text.splitlines(keepends=True)
    out, decisions, seen = [], [], set()
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if line.startswith("COPY "):
            match = re.fullmatch(
                r'COPY "([^"]+)"\."([^"]+)" \(("[^"]+"(?:, "[^"]+")*)\) FROM stdin;\n?', line
            )
            require(match is not None, "Unrecognized COPY header")
            table = match[1] + "." + match[2]
            require(table not in seen, "Duplicate COPY section")
            seen.add(table)
            cols = re.findall(r'"([^"]+)"', match[3])
            section = [line]
            while i < len(lines) and lines[i].rstrip("\r\n") != "\\.":
                section.append(lines[i])
                i += 1
            require(i < len(lines), "Unterminated COPY section")
            section.append(lines[i])
            i += 1
            count = len(section) - 2
            if table in SESSIONS:
                decisions.append([table, count, "session exclusion; fresh login required"])
            elif table in EMPTY_OMISSIONS:
                require(count == 0, "Populated unsupported Auth/Storage section")
                decisions.append([table, 0, "explicit empty compatibility omission"])
            else:
                require(
                    count == 0 or table in migration.TABLES,
                    "Populated section outside verified preservation scope",
                )
                require(
                    table in columns and set(cols) <= set(columns[table]),
                    "Unsupported COPY table/columns",
                )
                out.extend(section)
        elif "setval" in line:
            # Preserve the private feed position sequence; excluding it breaks resumed pulls.
            if re.fullmatch(
                r"SELECT pg_catalog.setval\('(?:\"app_private\"\.\"sync_changes_position_seq\"|app_private.sync_changes_position_seq)', \d+, (?:true|false)\);\n?",
                line,
            ):
                out.append(line)
                continue
            require(
                re.fullmatch(
                    r"SELECT pg_catalog.setval\('(?:\"auth\"\.\"refresh_tokens_id_seq\"|auth.refresh_tokens_id_seq)', \d+, (?:true|false)\);\n?",
                    line,
                ),
                "Unreviewed sequence reset",
            )
            decisions.append(["auth.refresh_tokens_id_seq", 0, "excluded session sequence"])
        else:
            out.append(line)
    require(set(migration.TABLES) <= seen, "Missing preservation COPY sections")
    return "".join(out), decisions


def destination(name, ports=None):
    require(re.fullmatch(r"[a-z][a-z0-9-]{0,31}", name) is not None, "Invalid destination name")
    target = migration.installation("destination")
    target.PROJECT = "bath-royale-migration-" + name
    target.STATE = (
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / target.PROJECT
    )
    outside_checkout(target.STATE)
    if ports:
        require(
            len(set(ports)) == 2 and all(1024 <= p <= 65535 for p in ports),
            "Two distinct unprivileged loopback ports required",
        )
        target.AUTH_PORT, target.REST_PORT = ports
    return target


def fresh_target(target):
    require(not target.STATE.exists() and not target.STATE.is_symlink(), "Destination state exists")
    require(
        target.run(["podman", "info", "--format", "{{.Host.Security.Rootless}}"]) == "true",
        "Rootless Podman required",
    )
    # Successful full listings distinguish absence from daemon/permission failures.
    for args in (
        ["ps", "-a", "--format", "{{.Names}}"],
        ["volume", "ls", "--format", "{{.Name}}"],
        ["network", "ls", "--format", "{{.Name}}"],
    ):
        names = target.run(["podman", *args]).splitlines()
        require(
            not any(n == target.PROJECT or n.startswith(target.PROJECT + "-") for n in names),
            "Destination resources exist; refusing reuse",
        )


def grants(source):
    commands = []
    for row in source["objects"]:
        commands.append(
            "GRANT "
            + row["privilege_type"]
            + " ON "
            + row["object"]
            + " TO "
            + row["role"]
            + (" WITH GRANT OPTION" if row["is_grantable"] else "")
            + ";"
        )
    for row in source["columns"]:
        commands.append(
            "GRANT "
            + row["privilege_type"]
            + " ("
            + row["col"]
            + ") ON TABLE "
            + row["tab"]
            + " TO "
            + row["role"]
            + (" WITH GRANT OPTION" if row["is_grantable"] else "")
            + ";"
        )
    return "\n".join(commands)


def reconcile_sql(source):
    # Executed after schema import, inside the same transaction. Include defaults and columns.
    return f"""DO $reconcile$
DECLARE privilege_record record;
BEGIN
FOR privilege_record IN {ACL} LOOP
EXECUTE 'REVOKE ALL ON '||privilege_record.object||' FROM '||privilege_record.role||' CASCADE';
END LOOP;
FOR privilege_record IN {COLUMN_ACL} LOOP
EXECUTE 'REVOKE '||privilege_record.privilege_type||' ('||privilege_record.col||') ON TABLE '||privilege_record.tab||' FROM '||privilege_record.role||' CASCADE';
END LOOP;
END; $reconcile$;
""" + grants(source)


def preservation(target, bundle, revalidate=True):
    require(migration.snapshot(target) == json.loads(bundle["before.json"]), "Complete rows differ")
    actual, expected = inventory(target), json.loads(bundle["inventory.json"])
    for key in INVENTORY_KEYS:
        require(actual[key] == expected[key], "Application inventory differs: " + key)
    require(acls(target) == json.loads(bundle["acls.json"]), "Effective ACLs differ")
    # Roles/memberships/extensions/Auth migrations/server differ intentionally; retain inventory.
    if revalidate:
        for table in migration.TABLES:
            constraints = json_query(
                target,
                "select conname,pg_get_constraintdef(oid) definition "
                f"from pg_constraint where conrelid='{table}'::regclass and contype='f'",
            )
            for row in constraints:
                name = '"' + row["conname"].replace('"', '""') + '"'
                target.sql(
                    "begin; set local search_path=''; "
                    + f"alter table {table} drop constraint {name}; "
                    f"alter table {table} add constraint {name} {row['definition']}; rollback;"
                )


def restore_bundle(args):
    require(args.disposable, "Explicit --disposable acknowledgement required")
    bundle = load_bundle(args.bundle)
    components = json.loads(bundle["components.json"])
    require(
        components["compose_sha256"]
        == hashlib.sha256((poc.ROOT / "backend/compose.yml").read_bytes()).hexdigest(),
        "Target component pins changed",
    )
    target = destination(args.destination, (args.auth_port, args.rest_port))
    fresh_target(target)
    # Reserve once, before bootstrap: interrupted/failed targets cannot be silently reused.
    target.STATE.mkdir(mode=0o700, parents=True)
    write_json(
        target.STATE / "transfer.json",
        {
            "bundle_sha256": hashlib.sha256(
                (args.bundle / "manifest.json").read_bytes()
            ).hexdigest(),
            "destination": args.destination,
            "auth_port": args.auth_port,
            "rest_port": args.rest_port,
        },
    )
    target.start(migrations=False)
    target.compose("stop", "auth", "rest")
    require(target.sql("select count(*) from auth.users") == "0", "Destination has Auth users")
    require(
        target.sql(
            f"select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace "
            f"where n.nspname in {SCHEMAS} and c.relkind in ('r','v','m')"
        )
        == "0",
        "Destination has application relations",
    )
    target_columns = {
        (r["tab"], r["col"]): (r["data_type"], r["udt_name"])
        for r in json_query(target, AUTH_COLUMNS)
    }
    columns = {}
    for row in json.loads(bundle["columns.json"]):
        table, col = row["tab"], row["col"]
        if table in migration.TABLES and not table.startswith("auth."):
            columns.setdefault(table, []).append(col)  # Created by imported schema.
        elif target_columns.get((table, col)) == (row["data_type"], row["udt_name"]):
            columns.setdefault(table, []).append(col)
    data, decisions = adapt_data(bundle["data.sql"], columns)
    roles = bundle["roles.sql"].replace(
        REALTIME_GRANT, "-- Realtime absent: parameter grant omitted."
    )
    decisions.append(
        ["supabase_realtime_admin", 0, "reduced target: omit only log_min_messages grant"]
    )
    # Evidence goes into fresh destination state, never changes a sealed export bundle.
    for name, content in [
        ("roles-restore.sql", roles),
        ("data-restore.sql", data),
        ("acl-reconcile.sql", reconcile_sql(json.loads(bundle["acls.json"]))),
    ]:
        poc.secure_write(target.STATE / name, content)
    write_json(target.STATE / "compatibility.json", decisions)
    target.sql(
        "begin;\n"
        + roles
        + "\n"
        + bundle["schema.sql"]
        + "\nset local session_replication_role=replica;\n"
        + data
        + "\n"
        + (target.STATE / "acl-reconcile.sql").read_text()
        + "\ncommit;"
    )
    preservation(target, bundle)
    write_json(target.STATE / "target-inventory.json", inventory(target))
    write_json(target.STATE / "after.json", migration.snapshot(target))
    seal(target.STATE)
    print("PASS: atomic restore, ACL reconciliation, exact preservation and FK revalidation")
    print("Destination DB retained; Auth/API remain stopped; no fixture matrix executed")


def verify_bundle(args):
    bundle = load_bundle(args.bundle)
    if args.destination:
        target = destination(args.destination)
        private_path(target.STATE, directory=True)
        evidence = load_bundle(
            target.STATE,
            required={
                "transfer.json",
                "roles-restore.sql",
                "data-restore.sql",
                "acl-reconcile.sql",
                "compatibility.json",
                "target-inventory.json",
                "after.json",
            },
        )
        receipt = json.loads(evidence["transfer.json"])
        require(
            receipt["destination"] == args.destination
            and receipt["bundle_sha256"]
            == hashlib.sha256((args.bundle / "manifest.json").read_bytes()).hexdigest(),
            "Destination/bundle binding differs",
        )
        for service in ("auth", "rest"):
            require(
                target.run(
                    [
                        "podman",
                        "inspect",
                        target.PROJECT + "-" + service,
                        "--format",
                        "{{.State.Running}}",
                    ]
                )
                == "false",
                "Stop destination writers before exact preservation verification",
            )
        preservation(target, bundle)
        print("PASS: exact rows, application definitions, effective ACLs and rolled-back FK checks")
        if args.runtime:
            require(
                args.accounts and args.source_sessions,
                "Private accounts and source sessions required",
            )
            import cloud_rehearsal

            private_path(args.accounts)
            private_path(args.source_sessions)
            accounts = cloud_rehearsal.validate_accounts(args.accounts)
            sessions = json.loads(args.source_sessions.read_text())
            require(
                isinstance(sessions, list) and len(sessions) == len(accounts),
                "Expected source A/B sessions",
            )
            target.AUTH_PORT, target.REST_PORT = receipt["auth_port"], receipt["rest_port"]
            before = json.loads(bundle["before.json"])
            try:
                target.start(migrations=False)
                migration.check_sessions(target, accounts, sessions)
                require(
                    all(
                        migration.snapshot(target)[t] == before[t]
                        for t in migration.TABLES
                        if not t.startswith("auth.")
                    ),
                    "Login changed application rows",
                )
                restart = migration.snapshot(target)
                target.compose("stop")
                target.start(migrations=False)
                require(migration.snapshot(target) == restart, "Restart changed rows")
                for account, previous in zip(accounts, sessions, strict=True):
                    require(
                        migration.login(target, account)["user"]["id"] == previous["user"]["id"],
                        "Restart identity changed",
                    )
            finally:
                target.compose("stop")
            print("PASS: original-password/UUID login, refresh, source-token rejection and restart")
    else:
        require(not args.runtime, "Runtime verification requires a destination")
        print("PASS: offline bundle permissions, completeness, sizes and checksums")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="operation", required=True)
    export = sub.add_parser(
        "export", help="Read-only managed export; operator must quiesce writers"
    )
    export.add_argument("--source-state", type=Path, required=True)
    export.add_argument("--project", required=True)
    export.add_argument("--quiesced", action="store_true", required=True)
    restore = sub.add_parser(
        "restore", help="Bootstrap and import into a never-used disposable target"
    )
    restore.add_argument("--destination", required=True)
    restore.add_argument("--disposable", action="store_true", required=True)
    restore.add_argument("--auth-port", type=int, required=True)
    restore.add_argument("--rest-port", type=int, required=True)
    verify = sub.add_parser(
        "verify", help="Offline bundle check; optional local preservation checks"
    )
    verify.add_argument("--destination")
    verify.add_argument(
        "--runtime",
        action="store_true",
        help="Opt in to local login/session writes and stop/start after preservation",
    )
    verify.add_argument("--accounts", type=Path)
    verify.add_argument("--source-sessions", type=Path)
    for command in (export, restore, verify):
        command.add_argument("--bundle", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        {"export": export_bundle, "restore": restore_bundle, "verify": verify_bundle}[
            args.operation
        ](args)
    except RuntimeError, OSError, ValueError, KeyError, TypeError, IndexError, AttributeError:
        # SQL exceptions and paths may contain data/secrets: no traceback or raw diagnostics.
        print(
            "FAIL: transfer guard/operation failed; private state retained; no automatic cleanup",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
