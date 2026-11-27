"""Idempotent fictional data for the isolated fixtures instance, never a managed URL."""

import argparse
import base64
import json
import os
import stat
import uuid
from pathlib import Path

import poc

NAMES = ("rei", "duque", "cavaleiro", "escudeiro", "novato")
BATHROOMS = (
    ("Biblioteca da Vila Inventada · piso 0", "📚", "curated"),
    ("Museu do Azulejo Imaginário", "🏛️", "curated"),
    ("Jardim dos Patos de Borracha", "🌿", "curated"),
    ("Café Trono de Ouro", "👑", "contribution"),
    ("Mercado das Nuvens · ala nascente", "🌈", "contribution"),
    ("Oficina do Parafuso Perdido", "🔧", "contribution"),
    ("Pavilhão da Ciência Faz-de-Conta", "🧪", "curated"),
    ("Quiosque da Rotunda Inexistente", "🚽", "contribution"),
    ("Biblioteca Centenária das Histórias Impossíveis · corredor das mil portas", "🏰", "curated"),
    (
        "Terminal Intergaláctico · instalações da sala de partidas e chegadas",
        "🧑🏽‍🚀",
        "contribution",
    ),
    ("Pátio das Laranjeiras · junto à fonte dos desejos", "🍊", "curated"),
    ("Galeria da Porta Misteriosa · sem avaliações", "🚪", "contribution"),
)
COMMENTS = (
    "Tudo limpo, papel à vontade e uma porta que fecha. Pequenos luxos da vida.",
    "O autoclismo canta mais alto do que o rádio. Cumpre a missão.",
    "Um espelho digno de uma sessão fotográfica e sabonete com cheiro a limão.",
    "A fila era curta, mas o papel estava a chegar ao fim. Leva precaução.",
    "Silencioso e confortável. Quase pedi um café para ficar mais um pouco.",
    "Faltava sabonete e o chão precisava de atenção. Há margem para subir no ranking.",
)


def identity(label):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "bath-royale:fictional-development:a31:" + label))


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def outside_checkout(path):
    path = path.resolve()
    if path == poc.ROOT or poc.ROOT in path.parents:
        raise RuntimeError("Development credentials/output must remain outside Git")
    return path


def secure_file(path, value):
    if path.is_symlink():
        raise RuntimeError("Refusing symlink output")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write(value)


def seed(password_file, output_dir, device_config=None):
    if poc.INSTANCE != "fixtures":
        raise RuntimeError(
            "Only POC_INSTANCE=fixtures is allowed; owner/managed installations are forbidden"
        )
    if password_file.is_symlink():
        raise RuntimeError("Refusing symlink password input")
    password_file = outside_checkout(password_file)
    info = password_file.stat()
    if password_file.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError("Password file must be private and owned by this user")
    password = password_file.read_text().strip()
    if len(password) < 8:
        raise RuntimeError("Development password needs at least eight characters")
    output_dir = outside_checkout(output_dir)
    output_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if stat.S_IMODE(output_dir.stat().st_mode) != 0o700 or output_dir.is_symlink():
        raise RuntimeError("Private development output directory required")
    poc.start()
    poc.bindings()  # verifies rootless, non-privileged, exclusively loopback listeners
    poc.sql("""create schema if not exists bath_royale_development;
      revoke all on schema bath_royale_development from public,anon,authenticated,service_role;
      create table if not exists bath_royale_development.owned(label text primary key,id uuid not null);
      revoke all on all tables in schema bath_royale_development from public,anon,authenticated,service_role;""")
    # Preflight every collision before changing any account or domain record.
    for name in NAMES:
        email = name + "@example.com"
        existing = poc.sql("select id from auth.users where lower(email)=" + literal(email))
        owned = poc.sql(
            "select id from bath_royale_development.owned where label=" + literal("account:" + name)
        )
        if existing and existing != owned:
            raise RuntimeError("Existing unowned test account preserved; refusing to seed")
    sessions = {}
    for name in NAMES:
        email = name + "@example.com"
        owned = poc.sql(
            "select id from bath_royale_development.owned where label=" + literal("account:" + name)
        )
        status, session = poc.request(
            poc.AUTH_PORT,
            "/token?grant_type=password" if owned else "/signup",
            "POST",
            dict(email=email, password=password),
        )
        if status != 200 or not session.get("access_token"):
            raise RuntimeError("Fixture authentication failed; existing passwords were not changed")
        actor = str(uuid.UUID(session["user"]["id"]))
        if owned and actor != owned:
            raise RuntimeError("Fixture account identity mismatch")
        poc.sql(
            "insert into bath_royale_development.owned values("
            + literal("account:" + name)
            + ","
            + literal(actor)
            + ") on conflict do nothing"
        )
        sessions[name] = session
    admin = sessions["rei"]["user"]["id"]
    poc.sql(
        "insert into app_private.moderators values(" + literal(admin) + ") on conflict do nothing"
    )
    for name in ("rei", "duque"):
        poc.sql(
            "insert into app_private.bathroom_creators values("
            + literal(sessions[name]["user"]["id"])
            + ") on conflict do nothing"
        )
    for index, (name, emoji, origin) in enumerate(BATHROOMS):
        target = identity("bathroom:" + str(index))
        existing = poc.sql("select id from public.bathrooms where id=" + literal(target))
        owned = poc.sql(
            "select id from bath_royale_development.owned where label="
            + literal("bathroom:" + str(index))
        )
        if existing and existing != owned:
            raise RuntimeError("Unowned catalogue collision preserved")
        poc.sql(
            "begin; insert into public.bathrooms(id,name,emoji,accent,contributor_id,community,publication_status,origin) values("
            + ",".join(
                map(
                    literal,
                    (
                        target,
                        "Exemplo fictício · " + name,
                        emoji,
                        index % 6,
                        admin,
                        True,
                        "approved",
                        origin,
                    ),
                )
            )
            + ") on conflict(id) do nothing; insert into bath_royale_development.owned values("
            + literal("bathroom:" + str(index))
            + ","
            + literal(target)
            + ") on conflict do nothing; commit;"
        )

    def submit(name, kind, target, action, payload, label):
        command = dict(
            operationId=identity("operation:" + label),
            entityType=kind,
            entityId=target,
            type=action,
            payload=payload,
            baseRevision=None,
            dependencies={},
        )
        status, result = poc.request(
            poc.REST_PORT,
            "/rpc/sync_submit",
            "POST",
            dict(command=command),
            sessions[name]["access_token"],
        )
        if status != 200 or result.get("status") != "acknowledged":
            raise RuntimeError("Fixture command failed; no existing content was overwritten")

    for user_index, (name, count) in enumerate(
        (("rei", 3), ("duque", 4), ("cavaleiro", 12), ("escudeiro", 2))
    ):
        actor = sessions[name]["user"]["id"]
        for index in range(count):
            label = name + ":" + str(index)
            bathroom = identity("bathroom:" + str(index % 6))
            visit = dict(
                id=identity("visit:" + label),
                bathroom=bathroom,
                user=actor,
                at=1790812800000000 + (user_index * 20 + index) * 86400000000,
                provenance="user_created",
            )
            if index % 4 == 3:
                submit(name, "visit", visit["id"], "createVisit", visit, "visit:" + label)
            else:
                review = dict(
                    id=identity("review:" + label),
                    visit=visit["id"],
                    bathroom=bathroom,
                    author=actor,
                    created=visit["at"],
                    updated=visit["at"],
                    rating=[4.6, 2.1, 3.8, 1.4, 5.0, 0.8][index % 6],
                    paper=index % 3,
                    hygiene=index % 5,
                    comfort=(index + 2) % 5,
                    aesthetics=(index + 3) % 5,
                    tags=json.dumps(
                        [{"emoji": "✨", "label": "Limpo"}]
                        if index % 2 == 0
                        else [{"emoji": "🤫", "label": "Silenciosa"}],
                        ensure_ascii=False,
                    ),
                    comment=COMMENTS[index % len(COMMENTS)],
                    provenance="user_created",
                )
                submit(
                    name,
                    "review",
                    review["id"],
                    "createCommunityVisitReview",
                    dict(visit=visit, review=review),
                    "review:" + label,
                )
        for index in range(min(3, count)):
            bathroom = identity("bathroom:" + str((index + user_index) % 6))
            submit(
                name,
                "favourite",
                bathroom,
                "setFavourite",
                dict(user=actor, bathroom=bathroom, value=True),
                "favourite:" + name + ":" + str(index),
            )
    # A4 extension uses independent deterministic IDs. Original A3.1 payloads and
    # receipts must stay byte-equivalent so reseeding never overwrites test activity.
    tag_pool = (
        {"emoji": "🫧", "label": "Sabonete disponível"},
        {"emoji": "🚪", "label": "Porta sem trinco"},
        {"emoji": "🧻", "label": "Papel macio"},
        {"emoji": "🌬️", "label": "Bem ventilada"},
        {"emoji": "💡", "label": "Boa iluminação"},
        {"emoji": "♿", "label": "Acessível"},
        {"emoji": "💧", "label": "Chão molhado"},
        {"emoji": "👃", "label": "Cheiro duvidoso"},
        {"emoji": "🪝", "label": "Cabide disponível"},
        {"emoji": "🤫", "label": "Silenciosa"},
        {"emoji": "👩🏽‍💻", "label": "Pausa tecnológica"},
    )
    targets = (0, 1, 2, 3, 4, 5, 8, 9, 10)
    for user_index, name in enumerate(NAMES[:-1]):
        actor = sessions[name]["user"]["id"]
        for index in range(6):
            label = "a4:" + name + ":" + str(index)
            bathroom = identity("bathroom:" + str(targets[(index + user_index * 2) % len(targets)]))
            stamp = 1795200000000000 + (user_index * 20 + index) * 3600000000
            visit = dict(
                id=identity("visit:" + label),
                bathroom=bathroom,
                user=actor,
                at=stamp,
                provenance="user_created",
            )
            if index == 5:
                submit(name, "visit", visit["id"], "createVisit", visit, "visit:" + label)
                continue
            count = (index + user_index) % 5
            tags = [
                tag_pool[(index * 2 + offset + user_index) % len(tag_pool)]
                for offset in range(count)
            ]
            review = dict(
                id=identity("review:" + label),
                visit=visit["id"],
                bathroom=bathroom,
                author=actor,
                created=stamp,
                updated=stamp,
                rating=0 if user_index == 0 and index == 0 else (1, 5, 3, 4, 2)[index],
                paper=(index + user_index) % 3,
                hygiene=(index * 2 + user_index) % 5,
                comfort=(index + user_index) % 5,
                aesthetics=(4 - index + user_index) % 5,
                tags=json.dumps(tags, ensure_ascii=False),
                comment=None if count == 0 else COMMENTS[(index + user_index) % len(COMMENTS)],
                provenance="user_created",
            )
            submit(
                name,
                "review",
                review["id"],
                "createCommunityVisitReview"
                if review["rating"] == 0
                else "createCommunityVisitReviewV2",
                dict(visit=visit, review=review),
                "review:" + label,
            )
        bathroom = identity("bathroom:8")
        submit(
            name,
            "favourite",
            bathroom,
            "setFavourite",
            dict(user=actor, bathroom=bathroom, value=True),
            "favourite:a4:" + name,
        )
    accounts = [dict(email=name + "@example.com", password=password) for name in NAMES]
    secure_file(
        output_dir / "test-accounts.txt",
        "FICTIONAL LOCAL DEVELOPMENT ONLY — never distribute\n\n"
        + "\n".join(a["email"] + " : " + a["password"] for a in accounts)
        + "\n",
    )
    if device_config:
        config = json.loads(outside_checkout(device_config).read_text())
        if (
            config.get("SUPABASE_URL") != "https://localhost:55504"
            or config.get("SUPABASE_PUBLISHABLE_KEY") != "local-development-client"
        ):
            raise RuntimeError("Development-only TLS configuration required")
        config.update(
            BATH_ISOLATED_DEVELOPMENT=True,
            BATH_LOCAL_TEST_ACCOUNTS=base64.b64encode(json.dumps(accounts).encode()).decode(),
        )
        secure_file(output_dir / "development-defines.json", json.dumps(config))
    print(
        "PASS: fictional accounts/catalogue/activity seeded idempotently; private reference file written; owner accounts untouched"
    )


def preservation_snapshot():
    result = {}
    for table in (
        "public.bathrooms",
        "public.visits",
        "public.reviews",
        "public.favourites",
        "app_private.bathroom_creators",
        "app_private.moderators",
    ):
        result[table] = poc.sql(
            "select count(*)::text||':'||md5(coalesce(string_agg(row_to_json(t)::text,',' order by row_to_json(t)::text),'')) from "
            + table
            + " t"
        )
    result["auth"] = poc.sql(
        "select md5(coalesce(string_agg(id::text||email||encrypted_password,',' order by id),'')) from auth.users"
    )
    return result


if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--password-file", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--device-config", type=Path)
    parser.add_argument("--verify-idempotency", action="store_true")
    args = parser.parse_args()
    seed(args.password_file, args.output_dir, args.device_config)

    if args.verify_idempotency:
        before = preservation_snapshot()
        seed(args.password_file, args.output_dir, args.device_config)
        if preservation_snapshot() != before:
            raise RuntimeError("Idempotency/preservation check failed")
        print(
            "PASS: repeated seed preserves account IDs/password hashes and all domain rows; no duplicates"
        )
