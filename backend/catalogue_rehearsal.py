"""A5.2 disposable catalogue assertions. Never selects retained development."""

import copy
import json
import uuid

import cloud_transfer
import migration
import poc
from import_catalogue import ROOT, identity, literal, load, plan


def check(value, label):
    if not value:
        raise RuntimeError(label)


def snapshot():
    return migration.snapshot(poc)


def fails(sql, label):
    before = snapshot()
    try:
        poc.sql(sql)
    except RuntimeError:
        pass
    else:
        raise RuntimeError("Expected rejection: " + label)
    check(snapshot() == before, "Failed import changed state: " + label)


def restore():
    before = snapshot()
    columns = {
        t: json.loads(
            poc.sql(
                "select json_agg(column_name order by ordinal_position) from information_schema.columns where table_schema="
                + literal(t.split(".")[0])
                + " and table_name="
                + literal(t.split(".")[1])
            )
        )
        for t in migration.TABLES
    }
    data = migration.dump(
        poc, "--data-only", "--quote-all-identifiers", *["--table=" + t for t in migration.TABLES]
    )
    adapted, _ = cloud_transfer.adapt_data(data, columns)
    schema = migration.dump(
        poc,
        "--schema-only",
        *["--schema=" + s for s in ("auth", "public", "app_private", "bath_royale_migrations")],
    )
    database = "catalogue_restore_" + uuid.uuid4().hex[:12]

    def sql(statement):
        return poc.run(
            [
                "podman",
                "exec",
                "-i",
                poc.PROJECT + "-db",
                "psql",
                "-X",
                "-qAt",
                "-U",
                "supabase_admin",
                "-d",
                database,
                "-v",
                "ON_ERROR_STOP=1",
            ],
            statement,
        )

    class Target:
        pass

    target = Target()
    target.sql = sql
    poc.sql('create database "' + database + '" template template0')
    try:
        sql(
            'drop schema public; create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions; create extension if not exists "uuid-ossp" with schema extensions;'
        )
        sql(
            "begin;\n"
            + schema
            + "\nset local session_replication_role=replica;\n"
            + adapted
            + "\ncommit;"
        )
        check(
            migration.snapshot(target) == before, "Restored catalogue baseline/domain/feed differs"
        )
    finally:
        poc.sql('drop database "' + database + '"')
    print("PASS: populated catalogue registry/domain/feed logical export and isolated restoration")


def verify():
    entries = load(ROOT / "content/official_bathrooms.csv")
    before = snapshot()
    poc.sql(plan(entries))
    check(snapshot() == before, "Dry run changed data")
    poc.sql(plan(entries, apply=True))
    imported = snapshot()
    check(len(imported["public.bathrooms"]) == 34, "Catalogue count")
    check(
        all(not imported[t] for t in ("public.visits", "public.reviews", "public.favourites")),
        "Synthetic activity",
    )
    poc.sql(plan(entries, apply=True))
    check(snapshot() == imported, "Repeated import changed data or feeds")
    status, catalogue = poc.request(poc.REST_PORT, "/rpc/public_catalogue", "POST", {})
    check(status == 200 and len(catalogue) == 34, "Anonymous catalogue projection")
    expected = {e["id"]: e["content"] for e in entries}
    for b in catalogue:
        e = expected[b["id"]]
        check(
            b["classification"] == "official"
            and all(b[f] == e[f] for f in ("name", "emoji", "accent_rgb")),
            "Exact official identity",
        )
    status, feed = poc.request(
        poc.REST_PORT, "/rpc/sync_pull", "POST", dict(feed="catalogue", page_size=100)
    )
    check(
        status == 200
        and len(feed["changes"]) == 34
        and all(
            c["payload"]["classification"] == "official"
            and c["payload"]["accent_rgb"] == expected[c["entityId"]]["accent_rgb"]
            for c in feed["changes"]
        ),
        "Shared feed",
    )
    # Historical identity and real domain associations must survive corrections.
    actor, legacy = str(uuid.uuid4()), str(uuid.uuid4())
    poc.sql(
        f"insert into auth.users(id,email) values('{actor}','catalogue-test@example.invalid'); insert into public.bathrooms(id,name,emoji,accent,origin,community,publication_status) values('{legacy}','Historical bathroom','📚',5,'contribution',true,'approved'); insert into public.visits(id,owner_id,bathroom_id,visited_at) values(gen_random_uuid(),'{actor}','{entries[0]['id']}',now()); insert into public.reviews(id,visit_id,bathroom_id,author_id,rating,paper,hygiene,comfort,aesthetics,tags) select gen_random_uuid(),id,bathroom_id,owner_id,2.7,0,1,2,3,'[]' from public.visits; insert into public.favourites(owner_id,bathroom_id) values('{actor}','{entries[0]['id']}');"
    )
    activity = {t: snapshot()[t] for t in ("public.visits", "public.reviews", "public.favourites")}
    corrected = copy.deepcopy(entries)
    corrected[0]["content"].update(name="DLC corrigido", emoji="🧑🏽‍🚀", accent_rgb=0x123ABC)
    before = snapshot()
    poc.sql(plan(corrected))
    check(snapshot() == before, "Correction dry run")
    poc.sql(plan(corrected, apply=True))
    check(
        all(snapshot()[t] == rows for t, rows in activity.items()), "Historical activity rewritten"
    )
    check(
        next(b for b in snapshot()["public.bathrooms"] if b["id"] == legacy)["accent_rgb"] is None,
        "Historical RGB fallback changed",
    )
    poc.sql(plan(entries, apply=True))
    # Name collision, UUID collision, external drift, invalid grapheme, registry drift.
    duplicate = copy.deepcopy(entries)
    duplicate[0]["content"]["name"] = "Historical bathroom"
    fails(plan(duplicate, True), "normalized name")
    unknown = copy.deepcopy(entries[:1])
    unknown[0]["key"] = "new-key"
    unknown[0]["id"] = identity("ua-dlc")
    fails(plan(unknown, True), "UUID")
    bad = copy.deepcopy(entries)
    bad[0]["content"]["emoji"] = "👑👑"
    fails(plan(bad, True), "emoji")
    poc.sql(
        "update public.bathrooms set name='External edit' where id=" + literal(entries[0]["id"])
    )
    fails(plan(entries, True), "external drift")
    poc.sql("update public.bathrooms set name='DLC' where id=" + literal(entries[0]["id"]))
    for role in ("anon", "authenticated", "service_role"):
        check(
            poc.sql(
                "select has_table_privilege("
                + literal(role)
                + ",'app_private.official_catalogue','select,insert,update,delete')"
            )
            == "f",
            "Registry client privilege",
        )
    restore()
    print(
        "PASS: 34 exact official identities/RGB/emoji, empty initial activity, dry run, idempotency, correction preservation, conflicts, anonymous projections and client denial"
    )


if __name__ == "__main__":
    if poc.INSTANCE != "catalogue":
        raise RuntimeError("Only POC_INSTANCE=catalogue disposable infrastructure is allowed")
    poc.start()
    try:
        check(
            poc.sql("select count(*) from public.bathrooms") == "0",
            "Disposable catalogue must start empty; never reset retained state",
        )
        verify()
    finally:
        poc.compose("stop")
