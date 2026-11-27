"""Logical export/restore of disposable A2 state, with no additional listeners."""

import json
import uuid

import migration
import poc


def verify():
    if poc.INSTANCE not in ("sync", "protocol", "community"):
        raise RuntimeError("Disposable sync instance required")
    import cloud_transfer

    before = migration.snapshot(poc)
    tables = migration.TABLES
    for table in ("sync_clock", "sync_records", "sync_changes", "sync_receipts", "sync_cursors"):
        migration.require(
            bool(before["app_private." + table]), "Missing portability fixture " + table
        )
    # The actual export allowlist must retain all protocol tables and setval.
    columns = {
        t: list(before[t][0])
        if before[t]
        else json.loads(
            poc.sql(
                "select json_agg(column_name) from information_schema.columns where table_schema='"
                + t.split(".")[0]
                + "' and table_name='"
                + t.split(".")[1]
                + "'"
            )
        )
        for t in tables
    }
    # pg_dump quotes identifiers only when requested, as the transfer CLI does.
    quoted = migration.dump(
        poc, "--data-only", "--quote-all-identifiers", *["--table=" + t for t in tables]
    )
    adapted, _ = cloud_transfer.adapt_data(quoted, columns)
    migration.require("sync_changes_position_seq" in adapted, "Feed sequence excluded")
    schema = migration.dump(
        poc,
        "--schema-only",
        "--schema=auth",
        "--schema=public",
        "--schema=app_private",
        "--schema=bath_royale_migrations",
    )
    database = "a2_restore_" + uuid.uuid4().hex[:12]
    container = poc.PROJECT + "-db"

    def sql(statement):
        return poc.run(
            [
                "podman",
                "exec",
                "-i",
                container,
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
        migration.require(
            migration.snapshot(target) == before, "Restored synchronization rows differ"
        )
        sequence = "select last_value::text||':'||is_called::text from app_private.sync_changes_position_seq"
        migration.require(sql(sequence) == poc.sql(sequence), "Restored sequence differs")
        # Resume a retained receipt and cursor through the restored functions.
        receipt = next(
            r
            for r in before["app_private.sync_receipts"]
            if r["outcome"]["status"] == "acknowledged"
            and any(
                c["subject"] == r["subject"] and c["feed"] == "private"
                for c in before["app_private.sync_cursors"]
            )
        )
        subject = receipt["subject"]
        claims = json.dumps({"sub": subject, "role": "authenticated"})
        prefix = (
            "begin; set local role authenticated; select set_config('request.jwt.claims','"
            + claims
            + "',true); select set_config('request.jwt.claim.sub','"
            + subject
            + "',true); "
        )
        request = json.dumps(receipt["request"]).replace("'", "''")
        result = sql(
            prefix + "select public.sync_submit('" + request + "'::jsonb); rollback;"
        ).splitlines()[-1]
        migration.require(
            json.loads(result) == receipt["outcome"], "Restored receipt replay differs"
        )
        cursor = next(
            c
            for c in before["app_private.sync_cursors"]
            if c["subject"] == subject and c["feed"] == "private"
        )
        response = json.loads(
            sql(
                prefix + "select public.sync_pull('private','" + cursor["id"] + "',100); rollback;"
            ).splitlines()[-1]
        )
        migration.require(response["subject"] == subject, "Restored scoped cursor rejected")
        # Reproduce the xid collision that a restored clock must not mistake for
        # a prior call in this transaction. Roll back all test writes.
        clock = before["app_private.sync_clock"][0]["revision"]
        rev = int(
            sql(
                "begin; update app_private.sync_clock set transaction_id=pg_current_xact_id(); select app_private.sync_revision(); select app_private.sync_revision(); rollback;"
            ).splitlines()[-1]
        )
        migration.require(rev == clock + 1, "Restored xid collision reused revision")
        position = int(sql("select coalesce(max(position),0) from app_private.sync_changes"))
        next_position = int(
            sql(
                "begin; select nextval('app_private.sync_changes_position_seq'); rollback;"
            ).splitlines()[-1]
        )
        migration.require(next_position > position, "Restored watermark would collide")
        print(
            "PASS: complete private sync metadata export/restore, sequence, receipts, cursors and clock collision"
        )
    finally:
        poc.sql('drop database "' + database + '" with (force)')
