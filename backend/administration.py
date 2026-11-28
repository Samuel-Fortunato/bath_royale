"""Versioned owner-only administration protocol. No public API or implicit target.

Domain writes retain existing guards, RPCs, importer and synchronization triggers.
Requests and responses use JSON on stdin/stdout; diagnostics never expose SQL.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID

import cloud
import import_catalogue as catalogue

VERSION = 1
ROOT = Path(__file__).resolve().parents[1]
TABLES = [
    "public.bathrooms",
    "public.visits",
    "public.reviews",
    "public.favourites",
    "public.profiles",
    "app_private.moderators",
    "app_private.bathroom_creators",
    "app_private.bathroom_links",
    "app_private.reports",
    "app_private.official_catalogue",
    "app_private.alpha_feedback",
    "app_private.sync_clock",
    "app_private.sync_records",
    "app_private.sync_changes",
    "app_private.sync_receipts",
    "app_private.sync_cursors",
    "bath_royale_migrations.applied",
]
MUTATIONS = {
    "catalogue.apply",
    "catalogue.update",
    "catalogue.hide",
    "catalogue.restore",
    "catalogue.remove",
    "users.grant",
    "users.revoke",
    "feedback.review",
    "reports.hide",
    "reports.restore",
}


class AdminError(RuntimeError):
    pass


def require(value, message="Pedido de administração inválido."):
    if not value:
        raise AdminError(message)


def literal(value):
    return catalogue.literal(value)


def identifier(value):
    return str(UUID(value))


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def tool_binding():
    return hashlib.sha256(
        b"".join(
            (ROOT / name).read_bytes()
            for name in (
                "backend/administration.py",
                "backend/import_catalogue.py",
                "backend/cloud.py",
                "backend/cloud_transfer.py",
                "backend/migration.py",
                "backend/alpha_retention.py",
                "lib/models/content_suggestions.dart",
                "flake.nix",
                "flake.lock",
            )
        )
    ).hexdigest()


class Database:
    def __init__(self, environment, *, state=None, container=None):
        require(environment in {"managed", "development"}, "Seleciona o ambiente explicitamente.")
        self.environment = environment
        self.env = {k: os.environ[k] for k in ("PATH", "HOME", "LANG") if k in os.environ}
        if environment == "managed":
            require(
                state is not None and container is None, "Ligação gerida exige estado explícito."
            )
            state = cloud.state_directory(state)
            connection = cloud.private_json(state / "connection.json", ["database_url"])
            api = cloud.private_json(state / "api.json", ["url", "publishable_key"])
            # Established project allowlist and verify-full; no URL/libpq fallback.
            previous = os.environ.copy()
            try:
                os.environ.clear()
                os.environ.update(self.env)
                self.env = cloud.connection_env(connection, api, state / "root.crt")
            finally:
                os.environ.clear()
                os.environ.update(previous)
            self.target = "supabase:" + cloud.PROJECT
            self.command = ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1"]
        else:
            require(
                state is None
                and isinstance(container, str)
                and re.fullmatch(r"broyale-admin-[a-f0-9]{16}-db", container),
                "Seleciona um contentor descartável A7.2 explícito.",
            )
            result = subprocess.run(
                ["podman", "inspect", container],
                env=self.env,
                capture_output=True,
                text=True,
                check=False,
                timeout=20,
            )
            require(result.returncode == 0, "Contentor de desenvolvimento indisponível.")
            info = json.loads(result.stdout)[0]
            require(
                info["Config"]["Labels"].get("io.broyale.admin.disposable") == container
                and not info["HostConfig"].get("Privileged")
                and not info["HostConfig"].get("PortBindings")
                and info["HostConfig"].get("NetworkMode") == "none",
                "O destino não é um contentor isolado de administração.",
            )
            rootless = subprocess.run(
                ["podman", "info", "--format", "{{.Host.Security.Rootless}}"],
                env=self.env,
                capture_output=True,
                text=True,
                timeout=20,
            )
            require(
                rootless.returncode == 0 and rootless.stdout.strip() == "true",
                "É necessário Podman sem privilégios.",
            )
            self.target = "podman:" + info["Id"]
            self.command = [
                "podman",
                "exec",
                "-i",
                container,
                "env",
                "-u",
                "PGHOST",
                "-u",
                "PGPORT",
                "-u",
                "PGDATABASE",
                "-u",
                "PGUSER",
                "-u",
                "PGOPTIONS",
                "-u",
                "PGSERVICE",
                "-u",
                "PGSERVICEFILE",
                "-u",
                "PGPASSWORD",
                "-u",
                "PGSSLMODE",
                "-u",
                "PGTARGETSESSIONATTRS",
                "-u",
                "PGLOADBALANCEHOSTS",
                "PGPASSFILE=/dev/null",
                "PSQL_HISTORY=/dev/null",
                "psql",
                "-w",
                "-h",
                "/run/postgresql",
                "-p",
                "5432",
                "-X",
                "-qAt",
                "-U",
                "supabase_admin",
                "-d",
                "postgres",
                "-v",
                "ON_ERROR_STOP=1",
            ]

    def sql(self, statement):
        result = subprocess.run(
            self.command,
            input=statement,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
            timeout=60,
        )
        if result.returncode:
            for marker, message in {
                "Stale plan": "O plano ficou desatualizado; inspeciona os registos e cria um novo plano.",
                "Changed preview": "Os registos mudaram; cria um novo plano.",
                "Unsafe deletion": "Eliminação recusada: existem dependências ou um registo oficial. Usa hide ou inspeciona as referências.",
                "Registry drift": "O catálogo diverge do registo oficial. Reconcilia o CSV e o registo antes de alterar.",
                "conflicts with import baseline": "O catálogo diverge da base de importação. Reconcilia os registos antes de aplicar.",
                "Moderator required": "Seleciona --actor com o UUID de um moderador existente e sem bloqueio vigente.",
                "Use official CSV": "Edita esta entrada oficial no CSV; preserva a chave permanente e cria catalogue plan.",
                "Unsupported schema": "O esquema não corresponde às migrações desta aplicação; verifica as versões sem migrar automaticamente.",
                "lock timeout": "A base de dados está ocupada. Inspeciona o estado antes de criar um novo plano.",
            }.items():
                if marker in result.stderr:
                    raise AdminError(message)
            raise AdminError(
                "A operação SQL foi recusada; verifica esquema, dependências e atualidade do plano."
            )
        return result.stdout.strip()

    def read(self, query):
        return json.loads(
            self.sql(
                "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; "
                "SET LOCAL statement_timeout='30s'; "
                + schema_guard()
                + "SELECT ("
                + query
                + ")::text; ROLLBACK;"
            )
        )


def schema_guard():
    expected = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((ROOT / "supabase/migrations").glob("*.sql"))
    }
    return (
        "DO $schema$ BEGIN IF (SELECT jsonb_object_agg(name,sha256) FROM "
        "bath_royale_migrations.applied) IS DISTINCT FROM "
        + literal(canonical(expected))
        + "::jsonb THEN RAISE EXCEPTION 'Unsupported schema'; END IF; END $schema$;\n"
    )


def rows(query):
    return "SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') FROM (" + query + ") x"


def count(table, where="true"):
    return f"(SELECT count(*) FROM {table} WHERE {where})"


def object_sql(fields):
    return (
        "SELECT jsonb_build_object("
        + ",".join(literal(k) + "," + v for k, v in fields.items())
        + ")"
    )


def baseline_sql():
    # Full domain/metadata fingerprints are deliberately conservative. Auth projection
    # excludes password hashes, metadata, tokens and recovery proofs altogether.
    parts = [
        "'accounts', (SELECT md5(coalesce(jsonb_agg(x ORDER BY x::text)::text,'')) FROM "
        "(SELECT jsonb_build_array(id,email,created_at,last_sign_in_at,banned_until) x FROM auth.users) a)"
    ]
    for table in TABLES:
        parts.append(
            literal(table) + ",(SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY "
            "to_jsonb(t)::text)::text,'')) FROM " + table + " t)"
        )
    return "SELECT md5(jsonb_build_object(" + ",".join(parts) + ")::text)"


def dependencies(bathroom):
    b = literal(identifier(bathroom)) + "::uuid"
    pattern = literal("%" + identifier(bathroom) + "%")
    return {
        "visits": count("public.visits", "bathroom_id=" + b),
        "reviews": count("public.reviews", "bathroom_id=" + b),
        "favourites": count("public.favourites", "bathroom_id=" + b),
        "reports": count("app_private.reports", "kind='bathroom' AND target=" + b),
        "links": count("app_private.bathroom_links", f"private_id={b} OR shared_id={b}"),
        "registry": count("app_private.official_catalogue", "bathroom_id=" + b),
        "sync_records": count(
            "app_private.sync_records", f"entity_id={b} OR payload::text LIKE {pattern}"
        ),
        "sync_changes": count(
            "app_private.sync_changes", f"entity_id={b} OR payload::text LIKE {pattern}"
        ),
        "sync_receipts": count(
            "app_private.sync_receipts",
            f"request::text LIKE {pattern} OR outcome::text LIKE {pattern}",
        ),
        "sync_dependents": count(
            "app_private.sync_records",
            f"(entity_type<>'bathroom' OR entity_id<>{b}) AND payload::text LIKE {pattern}",
        )
        + "+"
        + count(
            "app_private.sync_changes",
            f"(entity_type<>'bathroom' OR entity_id<>{b}) AND payload::text LIKE {pattern}",
        ),
    }


def foreign_keys_sql():
    return rows(
        "SELECT conrelid::regclass::text relation, pg_get_constraintdef(oid) definition FROM pg_constraint WHERE contype='f' AND confrelid='public.bathrooms'::regclass ORDER BY conrelid::regclass::text,conname"
    )


def known_references_sql():
    expected = [
        ("public.visits", "bathroom_id"),
        ("public.reviews", "bathroom_id"),
        ("public.favourites", "bathroom_id"),
        ("app_private.bathroom_links", "private_id"),
        ("app_private.bathroom_links", "shared_id"),
        ("app_private.official_catalogue", "bathroom_id"),
    ]
    allowed = " OR ".join(
        "(c.conrelid="
        + literal(table)
        + "::regclass AND c.conkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid=c.conrelid AND attname="
        + literal(column)
        + ")])"
        for table, column in expected
    )
    return (
        "(SELECT count(*)=6 AND bool_and(c.confdeltype='a' AND c.confkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid=c.confrelid AND attname='id')] AND ("
        + allowed
        + ")) FROM pg_constraint c WHERE c.contype='f' AND c.confrelid='public.bathrooms'::regclass)"
    )


def bathroom_sql(bathroom):
    b = literal(identifier(bathroom)) + "::uuid"
    return object_sql(
        {
            "record": "(SELECT to_jsonb(x) FROM (SELECT id,name,emoji,accent_rgb,origin,hidden,account_private,publication_status,verification_status FROM public.bathrooms WHERE id="
            + b
            + ") x)",
            "dependencies": "(" + object_sql(dependencies(bathroom)) + ")",
            "foreign_keys": "(" + foreign_keys_sql() + ")",
        }
    )


def account_sql(account):
    a = literal(identifier(account)) + "::uuid"
    return rows(
        "SELECT u.id,p.username,u.created_at,u.last_sign_in_at,"
        "(u.banned_until>now()) IS TRUE banned, "
        "app_private.account_capabilities(u.id) permissions,"
        + count("public.visits", "owner_id=u.id")
        + " visits,"
        + count("public.reviews", "author_id=u.id")
        + " reviews,"
        + count("public.favourites", "owner_id=u.id")
        + " favourites "
        "FROM auth.users u LEFT JOIN public.profiles p ON p.id=u.id WHERE u.id=" + a
    )


def suggestions():
    # Parse only this explicit constant; fail closed if Dart representation changes.
    source = (ROOT / "lib/models/content_suggestions.dart").read_text()
    block = source.split("final reviewTagSuggestions = List<ReviewTagData>.unmodifiable(\n  [", 1)[
        1
    ].split("].map(ReviewTagData.legacy)", 1)[0]
    labels = re.findall(r"^    '([^'\\]+)',\s*$", block, re.MULTILINE)
    require(len(labels) == 40, "O formato das sugestões da aplicação mudou.")
    return [
        {"emoji": x.split(" ", 1)[0], "label": x.split(" ", 1)[1], "source": "APK"} for x in labels
    ]


def read_query(operation, args):
    limit, offset = args.get("limit", 50), args.get("offset", 0)
    require(type(limit) is int and 1 <= limit <= 200 and type(offset) is int and offset >= 0)
    page = f" LIMIT {limit} OFFSET {offset}"
    if operation == "db.status":
        return object_sql(
            {
                "connected": "true",
                "server_version": "current_setting('server_version')",
                "schema": "(SELECT jsonb_agg(name ORDER BY name) FROM bath_royale_migrations.applied)",
            }
        )
    if operation == "db.stats":
        fields = {
            key: count(table, where)
            for key, table, where in [
                ("registered_accounts", "auth.users", "true"),
                (
                    "not_banned_accounts",
                    "auth.users",
                    "banned_until IS NULL OR banned_until<=now()",
                ),
                ("banned_accounts", "auth.users", "banned_until>now()"),
                ("accounts_ever_signed_in", "auth.users", "last_sign_in_at IS NOT NULL"),
                (
                    "accounts_with_visits",
                    "auth.users",
                    "id IN (SELECT owner_id FROM public.visits)",
                ),
                (
                    "official_bathrooms",
                    "public.bathrooms",
                    "NOT account_private AND origin='curated'",
                ),
                (
                    "community_bathrooms",
                    "public.bathrooms",
                    "NOT account_private AND origin='contribution'",
                ),
                (
                    "visible_bathrooms",
                    "public.bathrooms",
                    "NOT account_private AND NOT hidden AND publication_status='approved'",
                ),
                ("hidden_bathrooms", "public.bathrooms", "NOT account_private AND hidden"),
                ("private_bathrooms", "public.bathrooms", "account_private"),
                ("visits", "public.visits", "true"),
                ("reviews", "public.reviews", "true"),
                ("favourites", "public.favourites", "true"),
                ("feedback", "app_private.alpha_feedback", "true"),
                ("reports", "app_private.reports", "true"),
                ("creators", "app_private.bathroom_creators", "true"),
                ("moderators", "app_private.moderators", "true"),
            ]
        }
        return object_sql(fields)
    if operation == "catalogue.validate":
        entries = catalogue.load(ROOT / "content/official_bathrooms.csv")
        payload = literal(canonical(entries))
        return object_sql(
            {
                "entries": str(len(entries)),
                "valid": "(SELECT bool_and(app_private.valid_tag_emoji(content->>'emoji') AND app_private.grapheme_length(content->>'name') BETWEEN 1 AND 100) FROM jsonb_to_recordset("
                + payload
                + "::jsonb) x(content jsonb))",
            }
        )
    if operation == "catalogue.inspect":
        return bathroom_sql(args["id"])
    if operation == "catalogue.list":
        where = ["NOT account_private"]
        kind, visibility = args.get("kind", "all"), args.get("visibility", "all")
        require(
            kind in {"all", "official", "community"} and visibility in {"all", "visible", "hidden"}
        )
        if kind != "all":
            where.append("origin=" + literal("curated" if kind == "official" else "contribution"))
        if visibility != "all":
            where.append(
                "hidden"
                if visibility == "hidden"
                else "NOT hidden AND publication_status='approved'"
            )
        return rows(
            "SELECT id,name,emoji,accent_rgb,origin,hidden,publication_status FROM public.bathrooms WHERE "
            + " AND ".join(where)
            + " ORDER BY name,id"
            + page
        )
    if operation in {"users.list", "users.creators", "users.moderators"}:
        where = (
            "true"
            if operation == "users.list"
            else "EXISTS(SELECT 1 FROM app_private."
            + ("bathroom_creators" if operation == "users.creators" else "moderators")
            + " m WHERE m.user_id=u.id)"
        )
        return rows(
            "SELECT u.id,p.username,u.created_at,u.last_sign_in_at,(u.banned_until>now()) IS TRUE banned,app_private.account_capabilities(u.id) permissions FROM auth.users u LEFT JOIN public.profiles p ON p.id=u.id WHERE "
            + where
            + " ORDER BY u.created_at,u.id"
            + page
        )
    if operation == "users.inspect":
        return account_sql(args["id"])
    if operation in {"feedback.list", "feedback.inspect"}:
        where = []
        for field, allowed in [
            ("category", {"problem", "suggestion", "other"}),
            ("status", {"new", "reviewed", "resolved"}),
        ]:
            if args.get(field):
                require(args[field] in allowed)
                where.append(field + "=" + literal(args[field]))
        columns = "id,category,status,submitted_at,screen_id,app_version"
        if operation == "feedback.inspect":
            where.append("id=" + literal(identifier(args["id"])) + "::uuid")
            columns += ",description,platform_version"
        return rows(
            "SELECT "
            + columns
            + " FROM app_private.alpha_feedback WHERE "
            + (" AND ".join(where) or "true")
            + " ORDER BY submitted_at DESC,id"
            + page
        )
    if operation in {"reports.list", "reports.inspect"}:
        where = "true"
        columns = "id,kind,target,resolved"
        if operation == "reports.inspect":
            where = "id=" + literal(identifier(args["id"])) + "::uuid"
            columns += ",reason"
        if args.get("status"):
            require(args["status"] in {"open", "resolved"})
            where += " AND " + ("resolved" if args["status"] == "resolved" else "NOT resolved")
        return rows(
            "SELECT " + columns + " FROM app_private.reports WHERE " + where + " ORDER BY id" + page
        )
    if operation == "tags.observed":
        return rows(
            "SELECT *,count(*) OVER(PARTITION BY key) label_variants FROM (SELECT tag->>'key' key,tag->>'label' label,tag->>'emoji' emoji,count(*) uses,count(*) FILTER(WHERE published AND NOT hidden) published_uses FROM public.reviews CROSS JOIN LATERAL jsonb_array_elements(tags) tag GROUP BY 1,2,3) variants ORDER BY uses DESC,key,label,emoji"
            + page
        )
    raise AdminError("Operação de leitura desconhecida.")


def import_preview_sql(entries):
    values = literal(canonical(entries)) + "::jsonb"
    return object_sql(
        {
            "entries": "("
            + rows(
                "SELECT i.key,i.id,i.content->>'name' name,i.content->>'emoji' emoji,i.content->'accent_rgb' accent_rgb,r.applied_content previous,CASE WHEN r.key IS NULL THEN 'create' WHEN (r.applied_content-'hidden')=(i.content-'hidden') THEN 'unchanged' ELSE 'correct' END action FROM jsonb_to_recordset("
                + values
                + ") i(key text,id text,content jsonb) LEFT JOIN app_private.official_catalogue r USING(key) ORDER BY i.key"
            )
            + ")",
            "omitted": "("
            + rows(
                "SELECT key,bathroom_id FROM app_private.official_catalogue WHERE key NOT IN (SELECT x.key FROM jsonb_to_recordset("
                + values
                + ") x(key text)) ORDER BY key"
            )
            + ")",
        }
    )


def mutation_parts(operation, args):
    require(operation in MUTATIONS)
    if operation == "catalogue.update":
        target = literal(identifier(args["id"])) + "::uuid"
        changes = {k: args[k] for k in ("name", "emoji", "accent_rgb") if k in args}
        require(bool(changes), "Seleciona nome, emoji ou cor para editar.")
        for key, value in changes.items():
            require(
                type(value) is int and 0 <= value <= 0xFFFFFF
                if key == "accent_rgb"
                else isinstance(value, str) and bool(value)
            )
        assignments = ",".join(
            key + "=" + (str(value) if key == "accent_rgb" else literal(value))
            for key, value in changes.items()
        )
        body = (
            "DO $edit$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.bathrooms WHERE id="
            + target
            + " AND NOT account_private AND origin='contribution') OR EXISTS(SELECT 1 FROM app_private.official_catalogue WHERE bathroom_id="
            + target
            + ") THEN RAISE EXCEPTION 'Use official CSV'; END IF; UPDATE public.bathrooms SET "
            + assignments
            + " WHERE id="
            + target
            + "; END $edit$;"
        )
        return (
            object_sql(
                {
                    "before": "(" + bathroom_sql(args["id"]) + ")",
                    "changes": literal(canonical(changes)) + "::jsonb",
                }
            ),
            body,
            identifier(args["actor"]),
        )
    if operation == "catalogue.apply":
        entries = catalogue.load(ROOT / "content/official_bathrooms.csv")
        return import_preview_sql(entries), catalogue.plan(entries, apply=True), None
    if operation in {"catalogue.hide", "catalogue.restore", "catalogue.remove"}:
        b = literal(identifier(args["id"])) + "::uuid"
        preview = bathroom_sql(args["id"])
        if operation == "catalogue.remove":
            deps = dependencies(args["id"])
            safe = " AND ".join(
                v + "=0" for k, v in deps.items() if k not in {"sync_records", "sync_changes"}
            )
            body = (
                "DO $remove$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.bathrooms WHERE id="
                + b
                + " AND NOT account_private AND origin='contribution') OR NOT "
                + known_references_sql()
                + " OR NOT ("
                + safe
                + ") THEN RAISE EXCEPTION 'Unsafe deletion'; END IF; DELETE FROM public.bathrooms WHERE id="
                + b
                + "; END $remove$;"
            )
        else:
            hidden = "true" if operation.endswith("hide") else "false"
            body = (
                "DO $visibility$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.bathrooms WHERE id="
                + b
                + " AND NOT account_private) THEN RAISE EXCEPTION 'Unavailable bathroom'; END IF; "
                # Registry must match full baseline before we change either side.
                + "IF EXISTS(SELECT 1 FROM app_private.official_catalogue r JOIN public.bathrooms b ON b.id=r.bathroom_id WHERE b.id="
                + b
                + " AND r.applied_content IS DISTINCT FROM jsonb_build_object("
                + ",".join(literal(f) + ",b." + f for f in catalogue.FIELDS)
                + ")) THEN RAISE EXCEPTION 'Registry drift'; END IF; "
                + "UPDATE public.bathrooms SET hidden="
                + hidden
                + " WHERE id="
                + b
                + "; "
                + "UPDATE app_private.official_catalogue SET applied_content=jsonb_set(applied_content,'{hidden}',"
                + literal(hidden)
                + "::jsonb) WHERE bathroom_id="
                + b
                + "; END $visibility$;"
            )
        return preview, body, identifier(args["actor"])
    actor = identifier(args["actor"])
    if operation in {"users.grant", "users.revoke"}:
        target = literal(identifier(args["id"])) + "::uuid"
        # Existing RPC resolves email; lock and prove a unique exact UUID mapping.
        body = (
            "DO $permission$ DECLARE address text; BEGIN SELECT email INTO address FROM auth.users WHERE id="
            + target
            + "; "
            "IF address IS NULL OR (SELECT count(*) FROM auth.users WHERE lower(email)=lower(btrim(address)))<>1 THEN RAISE EXCEPTION 'Ambiguous account'; END IF; "
            "PERFORM public.grant_bathroom_creation(address,"
            + ("true" if operation.endswith("grant") else "false")
            + "); END $permission$;"
        )
        return account_sql(args["id"]), body, actor
    if operation == "feedback.review":
        require(args.get("status") in {"new", "reviewed", "resolved"})
        query = rows(
            "SELECT id,category,status,submitted_at FROM app_private.alpha_feedback WHERE id="
            + literal(identifier(args["id"]))
            + "::uuid"
        )
        body = (
            "SELECT public.set_alpha_feedback_status("
            + literal(identifier(args["id"]))
            + "::uuid,"
            + literal(args["status"])
            + ");"
        )
        return query, body, actor
    report = literal(identifier(args["id"])) + "::uuid"
    preview = object_sql(
        {
            "report": "(SELECT jsonb_build_object('id',id,'kind',kind,'target',target,'resolved',resolved) FROM app_private.reports WHERE id="
            + report
            + ")",
            "content": "(SELECT CASE WHEN r.kind='bathroom' THEN (SELECT jsonb_build_object('id',id,'name',name,'hidden',hidden) FROM public.bathrooms WHERE id=r.target AND NOT account_private) ELSE (SELECT jsonb_build_object('id',public_id,'hidden',hidden) FROM public.reviews WHERE public_id=r.target) END FROM app_private.reports r WHERE r.id="
            + report
            + ")",
        }
    )
    # Bathroom reports use the same registry consistency path as catalogue visibility.
    body = (
        "DO $report$ DECLARE r app_private.reports; BEGIN SELECT * INTO STRICT r FROM app_private.reports WHERE id="
        + report
        + "; "
        "IF r.kind='bathroom' THEN "
        "IF EXISTS(SELECT 1 FROM app_private.official_catalogue c JOIN public.bathrooms b ON b.id=c.bathroom_id WHERE b.id=r.target AND c.applied_content IS DISTINCT FROM jsonb_build_object("
        + ",".join(literal(f) + ",b." + f for f in catalogue.FIELDS)
        + ")) THEN RAISE EXCEPTION 'Registry drift'; END IF; END IF; "
        + "PERFORM public.moderate_content(r.kind,r.target,"
        + ("true" if operation.endswith("hide") else "false")
        + ",r.id); "
        + "IF r.kind='bathroom' THEN UPDATE app_private.official_catalogue SET applied_content=jsonb_set(applied_content,'{hidden}',"
        + literal("true" if operation.endswith("hide") else "false")
        + "::jsonb) WHERE bathroom_id=r.target; END IF; END $report$;"
    )
    return preview, body, actor


def locks():
    # Same clock-first ordering as domain/import writes. Lock all inspected tables
    # so FK inserts, Auth changes, reports and entitlement changes cannot race.
    return (
        "SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='30s'; "
        "SELECT singleton FROM app_private.sync_clock WHERE singleton FOR UPDATE; "
        "SELECT pg_advisory_xact_lock(74042012); LOCK TABLE auth.users,"
        + ",".join(TABLES)
        + " IN SHARE ROW EXCLUSIVE MODE;\n"
    )


def execute(db, request):
    require(request.get("version") == VERSION)
    operation, args = request["operation"], request.get("args", {})
    require(isinstance(args, dict))
    if operation == "tags.builtins":
        return {"environment": db.environment, "target": db.target, "data": suggestions()}
    if operation not in MUTATIONS:
        data = db.read(read_query(operation, args))
        if operation == "catalogue.validate":
            require(data["valid"], "O CSV contém nomes ou emojis inválidos para o domínio.")
        if operation == "tags.observed":
            builtins = {x["label"].lower() for x in suggestions()}
            for row in data:
                row["matches_current_suggestion"] = row["key"] in builtins
                row["flags"] = []
                if row["label_variants"] > 1:
                    row["flags"].append("variantes da mesma etiqueta")
                if any(ord(c) < 32 or ord(c) in range(0x202A, 0x202F) for c in row["label"]):
                    row["flags"].append("caracteres de controlo/direção")
            # Provenance is not stored. A suggestion match is never proof of origin.
        return {"environment": db.environment, "target": db.target, "data": data}
    preview, body, actor = mutation_parts(operation, args)
    if actor:
        actor = identifier(actor)
    # Validate using existing RPC as the selected moderator even in privileged SQL.
    auth = (
        ""
        if not actor
        else (
            "DO $actor$ BEGIN IF NOT EXISTS(SELECT 1 FROM app_private.moderators m JOIN auth.users u ON u.id=m.user_id WHERE u.id="
            + literal(actor)
            + "::uuid AND (u.banned_until IS NULL OR u.banned_until<=now())) THEN RAISE EXCEPTION 'Moderator required'; END IF; END $actor$; "
            + "SELECT set_config('request.jwt.claim.sub',"
            + literal(actor)
            + ",true); "
            + "SELECT set_config('request.jwt.claims',"
            + literal(canonical({"sub": actor, "role": "authenticated"}))
            + ",true); "
        )
    )
    plan = request.get("plan")
    if plan is None:
        # Do not take writer locks or sequence revisions during preview.
        data = db.read(
            object_sql({"baseline": "(" + baseline_sql() + ")", "preview": "(" + preview + ")"})
        )
        return {
            "version": VERSION,
            "environment": db.environment,
            "target": db.target,
            "operation": operation,
            "args": args,
            "binding": tool_binding(),
            "baseline": data["baseline"],
            "preview": data["preview"],
            "catalogue_sha256": hashlib.sha256(
                (ROOT / "content/official_bathrooms.csv").read_bytes()
            ).hexdigest(),
            "expires_at": (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat(),
        }
    require(request.get("confirmed") is True, "É necessária confirmação explícita do plano.")
    require(
        plan["environment"] == db.environment
        and plan["target"] == db.target
        and plan["operation"] == operation
        and plan["args"] == args
        and plan["binding"] == tool_binding()
        and plan["catalogue_sha256"]
        == hashlib.sha256((ROOT / "content/official_bathrooms.csv").read_bytes()).hexdigest()
        and datetime.now(timezone.utc) < datetime.fromisoformat(plan["expires_at"]),
        "Plano expirado ou destino/conteúdo alterado; cria um novo plano.",
    )
    # Importer is embedded inside this transaction; its domain validation remains
    # authoritative, but its own BEGIN/COMMIT must not release our validation locks.
    if operation == "catalogue.apply":
        require(
            body.startswith("\\set ON_ERROR_STOP on\nBEGIN;\n") and body.endswith("COMMIT;\n"),
            "A interface transacional do importador mudou; atualiza e verifica a integração.",
        )
        body = body.removeprefix("\\set ON_ERROR_STOP on\nBEGIN;\n").removesuffix("COMMIT;\n")
    check = (
        "DO $fresh$ BEGIN IF clock_timestamp()>="
        + literal(plan["expires_at"])
        + "::timestamptz THEN RAISE EXCEPTION 'Stale plan'; END IF; IF ("
        + baseline_sql()
        + ") IS DISTINCT FROM "
        + literal(plan["baseline"])
        + " THEN RAISE EXCEPTION 'Stale plan'; END IF; "
        + "IF ("
        + preview
        + ") IS DISTINCT FROM "
        + literal(canonical(plan["preview"]))
        + "::jsonb THEN RAISE EXCEPTION 'Changed preview'; END IF; END $fresh$; "
    )
    db.sql("BEGIN; " + locks() + schema_guard() + check + auth + body + " COMMIT;")
    return {"environment": db.environment, "operation": operation, "applied": True}


def verify_backup(path, project):
    """Offline prerequisite: existing sealed bundle, current complete scope/schema."""
    import cloud_transfer
    import migration

    require(project == cloud.PROJECT, "O backup tem de corresponder ao projeto gerido autorizado.")
    bundle = cloud_transfer.load_bundle(path)
    require(
        json.loads(bundle["components.json"])["project"] == project,
        "O backup pertence a outro projeto.",
    )
    require(
        cloud_transfer.bundle_scope(bundle) == migration.TABLES,
        "O backup não cobre todas as tabelas atuais. Prepara um backup completo pelo procedimento aprovado.",
    )
    snapshot = json.loads(bundle["before.json"])
    actual = {row["name"]: row["sha256"] for row in snapshot["bath_royale_migrations.applied"]}
    expected = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (ROOT / "supabase/migrations").glob("*.sql")
    }
    require(
        actual == expected, "O backup não corresponde ao esquema atual; prepara um novo backup."
    )
    return {"verified": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=["development", "managed"], required=True)
    parser.add_argument("--state-directory", type=Path)
    parser.add_argument("--development-container")
    parser.add_argument("--verify-backup", type=Path)
    parser.add_argument("--project")
    args = parser.parse_args()
    try:
        if args.verify_backup:
            require(
                args.environment == "managed"
                and args.state_directory is None
                and args.development_container is None,
                "A verificação do backup é offline e não aceita um destino de ligação.",
            )
            print(canonical(verify_backup(args.verify_backup, args.project)))
            return 0
        require(args.project is None, "O projeto só é usado na verificação offline do backup.")
        request = json.load(sys.stdin)
        if request.get("version") == VERSION and request.get("operation") == "tags.builtins":
            require(
                args.state_directory is None,
                "As sugestões APK não exigem credenciais de base de dados.",
            )
            result = {
                "environment": args.environment,
                "target": "application:" + tool_binding(),
                "data": suggestions(),
            }
        else:
            db = Database(
                args.environment, state=args.state_directory, container=args.development_container
            )
            result = execute(db, request)
        print(canonical(result))
        return 0
    except AdminError as error:
        print(canonical({"error": str(error)}))
        return 2
    except (
        RuntimeError,
        OSError,
        ValueError,
        KeyError,
        TypeError,
        IndexError,
        subprocess.TimeoutExpired,
    ):
        print(
            canonical(
                {
                    "error": "Operação recusada. Verifica o destino explícito, o esquema, o moderador, as dependências e a atualidade do plano."
                }
            )
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
