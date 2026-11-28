"""A7.2 fresh rootless database rehearsal. Never opens retained or managed data.

Only this command creates disposable infrastructure. The administration protocol
itself cannot create a target, migrate a schema or invoke fixtures.
"""

import contextlib
import copy
import hashlib
import json
import os
import secrets
import subprocess
import tempfile
import time
import uuid
from pathlib import Path
from unittest.mock import patch

import administration as admin
import import_catalogue as catalogue


def check(value, label):
    if not value:
        raise RuntimeError("Administration rehearsal failed: " + label)


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, check=False, **kwargs)
    check(result.returncode == 0, command[0] + " (diagnostics suppressed)")
    return result.stdout.strip()


def rejected(callback, label):
    try:
        callback()
    except admin.AdminError, RuntimeError, ValueError:
        return
    raise RuntimeError("Expected refusal: " + label)


def verify(db):
    def read(operation, args=None):
        return admin.execute(db, {"version": 1, "operation": operation, "args": args or {}})["data"]

    def plan(operation, args=None):
        return admin.execute(db, {"version": 1, "operation": operation, "args": args or {}})

    def apply(value):
        return admin.execute(
            db,
            {
                "version": 1,
                "operation": value["operation"],
                "args": value["args"],
                "plan": value,
                "confirmed": True,
            },
        )

    actor, account, bathroom, report, feedback = [str(uuid.uuid4()) for _ in range(5)]
    db.sql(
        f"INSERT INTO auth.users(id,email) VALUES('{actor}','moderator@example.invalid'),('{account}','account@example.invalid'); "
        f"INSERT INTO public.profiles(id,username) VALUES('{actor}','admin_test'),('{account}','account_test'); "
        f"INSERT INTO app_private.moderators VALUES('{actor}');"
    )
    check(read("db.status")["connected"], "actual connectivity")
    before = db.sql(admin.baseline_sql())
    official = plan("catalogue.apply")
    check(db.sql(admin.baseline_sql()) == before, "plan is read-only")
    check(len(official["preview"]["entries"]) == 30, "exact CSV preview")
    apply(official)
    check(read("db.stats")["official_bathrooms"] == 30, "official importer")
    identifier = official["preview"]["entries"][0]["id"]
    selected = {"id": identifier, "actor": actor}
    apply(plan("catalogue.hide", selected))
    check(read("catalogue.inspect", {"id": identifier})["record"]["hidden"], "hide")
    # Reimport must preserve moderation while retaining the full registry baseline.
    apply(plan("catalogue.apply"))
    check(
        read("catalogue.inspect", {"id": identifier})["record"]["hidden"],
        "reimport preserves hidden",
    )
    check(
        db.sql(
            "SELECT applied_content->>'hidden' FROM app_private.official_catalogue WHERE bathroom_id="
            + admin.literal(identifier)
        )
        == "true",
        "registry visibility consistency",
    )
    apply(plan("catalogue.restore", selected))
    check(not read("catalogue.inspect", {"id": identifier})["record"]["hidden"], "restore")
    check(
        db.sql(
            "SELECT count(*) FROM app_private.sync_changes WHERE feed='catalogue' AND entity_id="
            + admin.literal(identifier)
            + " AND deleted"
        )
        != "0",
        "visibility removal markers retained",
    )
    rejected(lambda: apply(plan("catalogue.remove", selected)), "official registry deletion")
    # Appearance corrections keep permanent UUID and every dependent record.
    entries = catalogue.load(catalogue.ROOT / "content/official_bathrooms.csv")
    corrected = copy.deepcopy(entries)
    corrected[0]["content"].update(name="DLC corrigido", emoji="👑", accent_rgb=0x123456)
    with patch.object(catalogue, "load", return_value=corrected):
        apply(plan("catalogue.apply"))
    check(
        read("catalogue.inspect", {"id": corrected[0]["id"]})["record"]["name"] == "DLC corrigido",
        "identity-preserving correction",
    )
    with patch.object(catalogue, "load", return_value=entries[1:]):
        omitted = plan("catalogue.apply")
        check(len(omitted["preview"]["omitted"]) == 1, "CSV omission explained")
        apply(omitted)
    check(
        read("catalogue.inspect", {"id": entries[0]["id"]})["record"] is not None,
        "omission is not deletion",
    )
    apply(plan("catalogue.apply"))
    # External drift is rejected by both visibility management and the importer.
    db.sql(
        "UPDATE public.bathrooms SET name='External drift' WHERE id=" + admin.literal(identifier)
    )
    rejected(lambda: apply(plan("catalogue.hide", selected)), "registry drift on moderation")
    rejected(lambda: apply(plan("catalogue.apply")), "registry drift on import")
    db.sql(
        "UPDATE public.bathrooms SET name="
        + admin.literal(official["preview"]["entries"][0]["name"])
        + " WHERE id="
        + admin.literal(identifier)
    )
    # Stale and rebound plans cannot run even if explicitly confirmed.
    stale = plan("users.grant", {"id": account, "actor": actor})
    db.sql(
        f"INSERT INTO public.bathrooms(id,name,emoji,community,origin,publication_status) VALUES('{bathroom}','Disposable community','🚽',true,'contribution','approved');"
    )
    rejected(lambda: apply(stale), "stale baseline")
    rebound = plan("users.grant", {"id": account, "actor": actor})
    rebound["target"] = "podman:different-container"
    rejected(lambda: apply(rebound), "different database")
    concurrent = plan("users.grant", {"id": account, "actor": actor})
    writer = subprocess.Popen(
        db.command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=db.env,
        text=True,
    )
    try:
        writer.stdin.write(
            "BEGIN; SELECT singleton FROM app_private.sync_clock WHERE singleton FOR UPDATE; SELECT 'writer-locked'; SELECT pg_sleep(0.3); UPDATE public.bathrooms SET name='Concurrent writer' WHERE id="
            + admin.literal(bathroom)
            + "; COMMIT;\n"
        )
        writer.stdin.flush()
        check(
            writer.stdout.readline().strip() == "t"
            and writer.stdout.readline().strip() == "writer-locked",
            "concurrent writer owns domain lock",
        )
        rejected(lambda: apply(concurrent), "writer commits while apply waits for lock")
        writer.stdin.close()
        writer.wait(timeout=10)
        check(writer.returncode == 0, "concurrent domain writer committed")
    finally:
        if writer.poll() is None:
            writer.kill()
            writer.wait()
        writer.stdout.close()
        writer.stderr.close()
    no_actor = plan("users.grant", {"id": account, "actor": account})
    rejected(lambda: apply(no_actor), "ordinary account cannot act as moderator")
    apply(plan("users.grant", {"id": account, "actor": actor}))
    check(read("users.inspect", {"id": account})[0]["permissions"]["create_bathroom"], "grant")
    check(
        db.sql(
            "SELECT count(*) FROM app_private.sync_records WHERE subject="
            + admin.literal(account)
            + " AND entity_type='capabilities'"
        )
        == "1",
        "permission synchronization",
    )
    apply(plan("users.revoke", {"id": account, "actor": actor}))
    check(not read("users.inspect", {"id": account})[0]["permissions"]["create_bathroom"], "revoke")
    # Each dependency category is independently refused; references arriving after
    # preview invalidate the plan before any change can commit.
    selected = {"id": bathroom, "actor": actor}
    clean_plan = plan("catalogue.remove", selected)
    db.sql(
        f"INSERT INTO public.visits(owner_id,bathroom_id,visited_at) VALUES('{account}','{bathroom}',now());"
    )
    rejected(lambda: apply(clean_plan), "concurrent dependency")
    rejected(lambda: apply(plan("catalogue.remove", selected)), "visits prevent removal")
    visit = db.sql("SELECT id FROM public.visits WHERE bathroom_id=" + admin.literal(bathroom))
    db.sql(
        f'INSERT INTO public.reviews(visit_id,bathroom_id,author_id,rating,paper,hygiene,comfort,aesthetics,tags,published) VALUES(\'{visit}\',\'{bathroom}\',\'{account}\',3,1,2,2,2,\'[{{"emoji":"👑","label":"Trono real","key":"trono real","version":1}}]\',true);'
    )
    review = db.sql("SELECT public_id FROM public.reviews WHERE visit_id=" + admin.literal(visit))
    db.sql(
        f"INSERT INTO app_private.reports(id,reporter,kind,target,reason) VALUES('{report}','{actor}','review','{review}','Rever conteúdo');"
    )
    apply(plan("reports.hide", {"id": report, "actor": actor}))
    check(
        db.sql("SELECT hidden FROM public.reviews WHERE public_id=" + admin.literal(review)) == "t",
        "reported review hide",
    )
    apply(plan("reports.restore", {"id": report, "actor": actor}))
    check(read("reports.inspect", {"id": report})[0]["resolved"], "report resolved")
    check(
        read("tags.observed")[0]["uses"] == 1 and len(read("tags.builtins")) == 40,
        "tags and APK suggestions",
    )
    db.sql(f"INSERT INTO public.favourites(owner_id,bathroom_id) VALUES('{account}','{bathroom}');")
    check(
        read("catalogue.inspect", {"id": bathroom})["dependencies"]["favourites"] == 1,
        "dependency inventory",
    )
    # A separate unreferenced community record can be deleted, with public tombstone.
    removable = str(uuid.uuid4())
    db.sql(
        f"INSERT INTO public.bathrooms(id,name,emoji,community,origin,publication_status) VALUES('{removable}','Safe removal','🚽',true,'contribution','approved');"
    )
    apply(
        plan(
            "catalogue.update",
            {
                "id": removable,
                "actor": actor,
                "name": "Edited community",
                "emoji": "👑",
                "accent_rgb": 0x123456,
            },
        )
    )
    check(
        read("catalogue.inspect", {"id": removable})["record"]["name"] == "Edited community",
        "community appearance edit",
    )
    db.sql(
        "CREATE TABLE public.unexpected_dependency(id uuid REFERENCES public.bathrooms(id) ON DELETE CASCADE); INSERT INTO public.unexpected_dependency VALUES("
        + admin.literal(removable)
        + ");"
    )
    rejected(
        lambda: apply(plan("catalogue.remove", {"id": removable, "actor": actor})),
        "unknown cascading reference",
    )
    db.sql("DROP TABLE public.unexpected_dependency;")
    apply(plan("catalogue.remove", {"id": removable, "actor": actor}))
    check(read("catalogue.inspect", {"id": removable})["record"] is None, "safe permanent removal")
    check(
        db.sql(
            "SELECT count(*) FROM app_private.sync_changes WHERE entity_id="
            + admin.literal(removable)
            + " AND feed='catalogue' AND deleted"
        )
        == "1",
        "permanent tombstone",
    )
    db.sql(
        f"INSERT INTO app_private.alpha_feedback(id,retry_hash,category,description,app_version,platform_version,screen_id) VALUES('{feedback}',decode('00','hex'),'problem','Descrição privada de teste','test','test','other');"
    )
    listing = read("feedback.list")
    check(
        "retry_hash" not in json.dumps(listing) and "description" not in json.dumps(listing),
        "feedback minimal list",
    )
    check("reporter" not in json.dumps(read("reports.list")), "reporter privacy")
    apply(plan("feedback.review", {"id": feedback, "actor": actor, "status": "reviewed"}))
    check(
        read("feedback.inspect", {"id": feedback})[0]["status"] == "reviewed", "feedback review RPC"
    )
    apply(plan("feedback.review", {"id": feedback, "actor": actor, "status": "new"}))
    check(read("feedback.inspect", {"id": feedback})[0]["status"] == "new", "feedback reopen RPC")
    for operation in (
        "catalogue.list",
        "users.list",
        "users.creators",
        "users.moderators",
        "reports.list",
        "feedback.list",
        "tags.observed",
        "catalogue.validate",
    ):
        read(operation)
    check(
        "encrypted_password" not in json.dumps(read("users.list")), "account credential exclusion"
    )
    print(
        "PASS: fresh database, read-only previews, importer/corrections/omissions, registry consistency, hide/restore feeds, guarded deletion/tombstones, stale/concurrent/rebound plans, moderator authorization, creator permissions, tags, feedback and report privacy"
    )

    return {
        "actor": actor,
        "account": account,
        "bathroom": bathroom,
        "feedback": feedback,
        "report": report,
    }


@contextlib.contextmanager
def disposable():
    container = "broyale-admin-" + uuid.uuid4().hex[:16] + "-db"
    image = "docker.io/supabase/postgres@sha256:5a4314708484bec672de2c09653a5c01fb1c84a998564ac231b0325e2238ed5b"
    created = None
    with tempfile.TemporaryDirectory(prefix="broyale-admin-test-") as directory:
        path = Path(directory) / "bootstrap.env"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            stream.write("POSTGRES_PASSWORD=" + secrets.token_hex(32) + "\nPOSTGRES_DB=postgres\n")
        try:
            created = run(
                [
                    "podman",
                    "run",
                    "-d",
                    "--name",
                    container,
                    "--label",
                    "io.broyale.admin.disposable=" + container,
                    "--network",
                    "none",
                    "--env-file",
                    str(path),
                    "--tmpfs",
                    "/var/lib/postgresql/data:rw",
                    image,
                    "postgres",
                    "-c",
                    "config_file=/etc/postgresql/postgresql.conf",
                    "-c",
                    "log_statement=none",
                    "-c",
                    "log_min_error_statement=panic",
                ]
            )
            db = admin.Database("development", container=container)
            # Deliberately hostile container-side libpq defaults must be ignored.
            db.command[3:3] = [
                "--env",
                "PGHOST=invalid.example.invalid",
                "--env",
                "PGSERVICE=invalid-service",
                "--env",
                "PGOPTIONS=-c default_transaction_read_only=on",
            ]
            deadline = time.monotonic() + 120
            while True:
                try:
                    db.sql("SELECT 1;")
                    break
                except admin.AdminError:
                    check(time.monotonic() < deadline, "database readiness")
                    time.sleep(1)
            # Native Auth normally adds banned_until on first startup. This SQL-only
            # fixture adds that compatibility column; no Auth credentials are created.
            db.sql("ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS banned_until timestamptz;")
            # No Auth/API servers are started and no ports are published.
            db.sql(
                "CREATE SCHEMA bath_royale_migrations; CREATE TABLE bath_royale_migrations.applied(name text PRIMARY KEY,sha256 text NOT NULL);"
            )
            for migration in sorted((admin.ROOT / "supabase/migrations").glob("*.sql")):
                sql = migration.read_text()
                db.sql(
                    "BEGIN;\n"
                    + sql
                    + "\nINSERT INTO bath_royale_migrations.applied VALUES("
                    + admin.literal(migration.name)
                    + ","
                    + admin.literal(hashlib.sha256(sql.encode()).hexdigest())
                    + "); COMMIT;"
                )
            yield db, container
        finally:
            if created:
                run(["podman", "rm", "-f", "-v", created])
    print(
        "PASS: removed only the newly created container/anonymous volumes and temporary bootstrap file"
    )


def main():
    with disposable() as (db, container):
        verify(db)


if __name__ == "__main__":
    main()
