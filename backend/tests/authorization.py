"""Real Auth + PostgREST attacks; SQL privilege/constraint checks complement HTTP."""

import json
import secrets
import time
import uuid

from poc import AUTH_PORT, REST_PORT, ROOT, STATE, request, secure_write, sql

COUNT = 0
ONE = "10000000-0000-4000-8000-000000000001"
TWO = "10000000-0000-4000-8000-000000000002"


def check(condition, label):
    global COUNT
    if not condition:
        raise RuntimeError("Assertion failed: " + label)
    COUNT += 1


def api(path, method="GET", body=None, user=None, expected=200):
    status, result = request(REST_PORT, "/" + path, method, body, user and user["access_token"])
    check(
        status == expected,
        method + " " + path.split("?")[0] + " expected " + str(expected) + ", got " + str(status),
    )
    return result


def reject(path, method, body=None, user=None):
    status, _ = request(REST_PORT, "/" + path, method, body, user and user["access_token"])
    check(
        status in (400, 401, 403, 404, 409),
        "reject " + method + " " + path.split("?")[0] + ", got " + str(status),
    )


def login(account):
    status, result = request(
        AUTH_PORT,
        "/token?grant_type=password",
        "POST",
        {"email": account["email"], "password": account["password"]},
    )
    check(status == 200 and "access_token" in result, "email/password login")
    return result


def review(visit, bathroom=ONE, **overrides):
    value = {
        "visit_id": visit,
        "bathroom_id": bathroom,
        "rating": 4.2,
        "paper": 2,
        "hygiene": 4,
        "comfort": 3,
        "aesthetics": 0,
        "tags": [{"emoji": "✨", "label": "Nice", "key": "nice", "version": 1}],
        "comment": "Comentário fictício do PoC.",
    }
    if overrides.get("published") is False:
        overrides.pop("published")
    value.update(overrides)
    return value


def publish(session, review_id, value):
    # Explicit A3 command with its separate per-owner publication CAS state.
    rows = sql(
        "select revision from app_private.sync_records where subject='"
        + session["user"]["id"]
        + "' and entity_type='publication' and entity_id='"
        + review_id
        + "'"
    )
    return api(
        "rpc/sync_submit",
        "POST",
        {
            "command": {
                "operationId": str(uuid.uuid4()),
                "entityType": "publication",
                "entityId": review_id,
                "type": "publishReview" if value else "withdrawReview",
                "payload": {"review_id": review_id, "published": value},
                "baseRevision": int(rows) if rows else None,
                "dependencies": {},
            }
        },
        session,
    )


def verify(existing_only=False, check_expiry=True):
    global COUNT
    COUNT = 0
    # Accounts persist privately; tokens exist only in process memory.
    path = STATE / "accounts.json"
    if existing_only and not path.exists():
        raise RuntimeError("Migrated accounts required; signup disabled")
    if not path.exists():
        accounts = [
            {
                "email": "bath-royale-fictional-" + name + "@example.invalid",
                "password": secrets.token_urlsafe(32),
            }
            for name in ["a", "b"]
        ]
        secure_write(path, json.dumps(accounts))
    accounts = json.loads(path.read_text())
    for account in [] if existing_only else accounts:
        status, result = request(AUTH_PORT, "/signup", "POST", account)
        check(status in (200, 422), "fictional signup or existing account")
        if status == 200:
            check("access_token" in result, "local auto-confirm signup session")
    a, b = [login(account) for account in accounts]
    aid, bid = a["user"]["id"], b["user"]["id"]
    uuid.UUID(aid)
    uuid.UUID(bid)
    for session, name in [(a, "a"), (b, "b")]:
        rows = api("profiles?id=eq." + session["user"]["id"], user=session)
        if not rows:
            api("profiles", "POST", {"username": "poc_fictional_" + name}, session, 201)
    # Only dedicated fictional account records are reset by this opt-in test.
    sql(
        "delete from public.visits where owner_id in ('" + aid + "','" + bid + "');"
        "delete from public.favourites where owner_id in ('" + aid + "','" + bid + "');"
        "delete from public.bathrooms where contributor_id in ('" + aid + "','" + bid + "') "
        "and id not in ('" + ONE + "','" + TWO + "');"
        "delete from app_private.moderators;"
    )
    sql((ROOT / "backend/fixtures.sql").read_text())
    check(len(api("rpc/public_catalogue")) == 2, "anonymous approved catalogue only")
    reject("profiles", "GET")
    check(len(api("profiles", user=a)) == 1, "private profile ID author-only")
    for table in ["visits", "reviews", "favourites"]:
        reject(table, "GET")
        reject(table, "POST", {})
    reject("bathrooms", "POST", {"name": "Proposta anónima"})
    reject("profiles", "POST", {"username": "anonymous"})
    reject("moderators", "GET")
    reject("users", "GET")
    status, _ = request(REST_PORT, "/users", token=a["access_token"])
    check(status == 404, "auth schema absent from API")
    print("PASS: fictional Auth signup/login; anonymous grants and public catalogue")

    # Own optional/repeat visits and favourites; ownership derived from auth.uid().
    visits = []
    for session, date in [
        (a, "2026-01-01T12:00:00Z"),
        (a, "2026-01-02T12:00:00Z"),
        (b, "2026-01-03T12:00:00Z"),
    ]:
        row = api("visits", "POST", {"bathroom_id": ONE, "visited_at": date}, session, 201)[0]
        check(row["owner_id"] == session["user"]["id"], "server-derived visit owner")
        visits.append(row["id"])
    av, av2, bv = visits
    api("favourites", "POST", {"bathroom_id": ONE}, a, 201)
    api("favourites", "POST", {"bathroom_id": TWO}, b, 201)
    check(len(api("visits", user=a)) == 2, "own repeat visits")
    check(len(api("visits", user=b)) == 1, "B cannot read A history")
    check(len(api("favourites", user=b)) == 1, "B only own favourite")
    check(api("visits?id=eq." + av, user=b) == [], "B exact private visit read hidden")
    check(
        api("favourites?owner_id=eq." + aid, user=b) == [],
        "B exact favourite read hidden",
    )
    for method, body in [
        ("PATCH", {"visited_at": "2026-01-04T12:00:00Z"}),
        ("DELETE", None),
    ]:
        check(
            api("visits?id=eq." + av, method, body, b) == [],
            "cross-user visit mutation no-op",
        )
    check(
        api("favourites?owner_id=eq." + aid, "DELETE", user=b) == [],
        "cross-user favourite delete no-op",
    )
    reject(
        "visits",
        "POST",
        {"owner_id": bid, "bathroom_id": ONE, "visited_at": "2026-01-05T12:00:00Z"},
        a,
    )
    reject("favourites", "POST", {"owner_id": bid, "bathroom_id": TWO}, a)
    for field, value in [
        ("owner_id", bid),
        ("bathroom_id", TWO),
        ("id", str(uuid.uuid4())),
        ("created_at", "2020-01-01"),
    ]:
        reject("visits?id=eq." + av, "PATCH", {field: value}, a)
    reject("visits", "POST", {"bathroom_id": ONE, "visited_at": "2026-01-01T12:00:00Z"}, a)
    reject(
        "visits",
        "POST",
        {"bathroom_id": str(uuid.uuid4()), "visited_at": "2026-01-01T12:00:00Z"},
        a,
    )
    reject("favourites", "POST", {"bathroom_id": ONE}, a)
    api("visits?id=eq." + av2, "PATCH", {"visited_at": "2026-01-06T12:00:00Z"}, a)
    check(
        api("visits?id=eq." + av2, user=a)[0]["visited_at"].startswith("2026-01-06"),
        "own visit update",
    )

    reject("reviews", "POST", review(bv), a)
    reject("reviews", "POST", review(av, TWO), a)
    reject("reviews", "POST", review(av, author_id=bid), a)
    for field, value in [
        ("rating", -0.1),
        ("rating", 5.1),
        ("rating", "NaN"),
        ("rating", "Infinity"),
        ("paper", 3),
        ("hygiene", -1),
        ("comfort", 5),
        ("aesthetics", 5),
        ("paper", 1.5),
        ("comment", "x" * 501),
        ("comment", ""),
        ("comment", " "),
        ("tags", {}),
        ("tags", [None]),
        ("tags", [{"emoji": "✨", "label": "x"}]),
    ]:
        reject("reviews", "POST", review(av, **{field: value}), a)
    tag = {"emoji": "✨", "label": "Nice", "key": "nice", "version": 1}
    for tags in [
        [tag] * 11,
        [tag, dict(tag, emoji="🌿")],
        [dict(tag, key="forged")],
        [dict(tag, label="a" * 31, key="a" * 31)],
        [dict(tag, emoji="abc")],
        [dict(tag, emoji="🌿🌿")],
        [dict(tag, emoji="🇵")],
        [dict(tag, emoji="🏻")],
        [
            dict(tag, label="grafiti", key="graffiti"),
            dict(tag, label="graffiti", key="graffiti"),
        ],
        [dict(tag, version=2)],
        [dict(tag, label="Nice,", key="nice,")],
        [dict(tag, extra="bad")],
        [dict(tag, label=None)],
    ]:
        reject("reviews", "POST", review(av, tags=tags), a)
    ar = api("reviews", "POST", review(av), a, 201)[0]
    br = api("reviews", "POST", review(bv, rating=0, comment=None), b, 201)[0]
    check(br["rating"] == 0, "explicit zero rating retained")
    for emoji in ["👨‍👩‍👧‍👦", "👍🏽", "🇵🇹", "1️⃣", "❤️"]:
        api("reviews?id=eq." + ar["id"], "PATCH", {"tags": [dict(tag, emoji=emoji)]}, a)
    api("reviews?id=eq." + ar["id"], "PATCH", {"tags": [tag], "comment": "🚽" * 500}, a)
    api(
        "reviews?id=eq." + ar["id"],
        "PATCH",
        {
            "comment": "e\u0301" * 500,
            "tags": [dict(tag, label="e\u0301" * 30, key="e\u0301" * 30, emoji="👨‍" * 10 + "👨")],
        },
        a,
    )
    reject("reviews", "POST", review(av), a)
    for field, value in [
        ("author_id", bid),
        ("visit_id", av2),
        ("bathroom_id", TWO),
        ("id", str(uuid.uuid4())),
        ("created_at", "2020-01-01"),
    ]:
        reject("reviews?id=eq." + ar["id"], "PATCH", {field: value}, a)
    check(api("reviews?id=eq." + ar["id"], user=b) == [], "raw review author-only")
    check(
        api("reviews?id=eq." + ar["id"], "PATCH", {"rating": 1}, b) == [],
        "cross-author update no-op",
    )
    check(
        api("reviews?id=eq." + ar["id"], "DELETE", user=b) == [],
        "cross-author delete no-op",
    )
    check(
        api("reviews?id=eq." + ar["id"], user=a)[0]["rating"] == 4.2,
        "attack left rating unchanged",
    )
    updated = api("reviews?id=eq." + ar["id"], "PATCH", {"rating": 5, "comment": "x" * 500}, a)[0]
    check(updated["updated_at"] >= updated["created_at"], "server update timestamp")
    api("reviews", "POST", review(av2, published=False, comment="Privado"), a, 201)
    print(
        "PASS: private ownership, repeat/optional visits, immutable associations, ratings/tags/content"
    )

    # Pending proposals visible only to contributor and protected moderator membership.
    pending = api(
        "bathrooms",
        "POST",
        {
            "name": "Proposta fictícia por aprovar",
            "institution": "Universidade Fictícia",
        },
        a,
        201,
    )[0]
    pid = pending["id"]
    check(api("bathrooms?id=eq." + pid) == [], "anonymous pending hidden")
    check(api("bathrooms?id=eq." + pid, user=b) == [], "other user pending hidden")
    check(len(api("bathrooms?id=eq." + pid, user=a)) == 1, "contributor pending read")
    api("bathrooms?id=eq." + pid, "PATCH", {"name": "Proposta fictícia editada"}, a)
    for field, value in [
        ("publication_status", "approved"),
        ("verification_status", "verified"),
        ("contributor_id", bid),
        ("origin", "curated"),
        ("approved_by", aid),
    ]:
        reject("bathrooms?id=eq." + pid, "PATCH", {field: value}, a)
        reject("bathrooms", "POST", {"name": "Ataque fictício", field: value}, a)
    reject("rpc/approve_bathroom", "POST", {"proposal_id": pid}, a)
    reject("rpc/approve_bathroom", "POST", {"proposal_id": pid})
    reject("moderators", "POST", {"user_id": aid}, a)
    reject("profiles?id=eq." + aid, "PATCH", {"is_admin": True}, a)
    reject("visits", "POST", {"bathroom_id": pid, "visited_at": "2026-02-01T12:00:00Z"}, a)
    reject("favourites", "POST", {"bathroom_id": pid}, a)
    # User-editable JWT metadata must not be an authority source.
    status, _ = request(
        AUTH_PORT,
        "/user",
        "PUT",
        {"data": {"role": "service_role", "is_admin": True}},
        a["access_token"],
    )
    check(status == 200, "user metadata spoof stored without authority")
    a = login(accounts[0])
    reject("rpc/approve_bathroom", "POST", {"proposal_id": pid}, a)
    sql("insert into app_private.moderators values ('" + aid + "');")
    reject("rpc/approve_bathroom", "POST", {"proposal_id": pid}, a)
    sql(
        "delete from app_private.moderators; insert into app_private.moderators values ('"
        + bid
        + "');"
    )
    check(
        len(api("bathrooms?id=eq." + pid, user=b)) == 1,
        "authorized moderator sees proposal",
    )
    api("rpc/approve_bathroom", "POST", {"proposal_id": pid}, b, 204)
    approved = api("bathrooms?id=eq." + pid, user=b)[0]
    check(
        approved["contributor_id"] == aid and approved["approved_by"] == bid,
        "approval preserves contributor",
    )
    check(
        api("bathrooms?id=eq." + pid, "PATCH", {"name": "Mutated"}, a) == [],
        "approved immutable to contributor",
    )
    private_proposal = api(
        "bathrooms", "POST", {"name": "Proposta fictícia ainda privada"}, a, 201
    )[0]
    removed = api("bathrooms", "POST", {"name": "Proposta fictícia a remover"}, a, 201)[0]
    api("bathrooms?id=eq." + removed["id"], "DELETE", user=a)
    check(api("bathrooms?id=eq." + removed["id"], user=a) == [], "own pending deletion")
    print(
        "PASS: proposal privacy, no self-approval/admin escalation, moderator approval and attribution"
    )

    publish(a, ar["id"], True)
    publish(b, br["id"], True)
    projection = api("rpc/public_reviews")
    check(len(projection) == 2, "only explicitly published reviews")
    expected = {
        "id",
        "bathroom_id",
        "author_id",
        "username",
        "rating",
        "paper",
        "hygiene",
        "comfort",
        "aesthetics",
        "tags",
        "comment",
    }
    check(
        all(set(row) == expected for row in projection),
        "public projection exact column allowlist",
    )
    public_text = json.dumps(projection)
    check(
        all(
            value not in public_text
            for value in [
                av,
                av2,
                bv,
                accounts[0]["email"],
                accounts[1]["email"],
                "2026-01-",
                "Privado",
            ]
        ),
        "public payload contains no private identifiers/times/email/comment",
    )
    for column in [
        "visit_id",
        "visited_at",
        "created_at",
        "updated_at",
        "email",
        "owner_id",
    ]:
        reject("rpc/public_reviews?select=" + column, "GET")
    reject("rpc/public_reviews?select=*,visits(*)", "GET")
    for table in ["visits", "reviews", "favourites"]:
        reject("bathrooms?select=id," + table + "(*)", "GET")
        api("bathrooms?select=id," + table + "(*)", user=b)
    # Authenticated embedding must still apply child RLS.
    embedded = api(
        "bathrooms?id=eq." + ONE + "&select=id,visits(*),reviews(*),favourites(*)",
        user=b,
    )
    check(
        all(v["owner_id"] == bid for row in embedded for v in row["visits"]),
        "embedded visit RLS",
    )
    check(
        all(v["author_id"] == bid for row in embedded for v in row["reviews"]),
        "embedded review RLS",
    )
    check(
        all(v["owner_id"] == bid for row in embedded for v in row["favourites"]),
        "embedded favourite RLS",
    )
    # Private ownership references Auth directly, never a public identity join.
    reject("visits?select=*,profiles(*)", "GET", user=b)
    reject("visits?select=*,users(*)", "GET", user=b)
    reject("profiles?select=*,users(*)", "GET", user=a)
    publish(a, ar["id"], False)
    check(len(api("rpc/public_reviews")) == 1, "unpublish removes projection immediately")
    api(
        "reviews?id=eq." + ar["id"],
        "PATCH",
        {"comment": "Exemplo fictício."},
        a,
    )
    publish(a, ar["id"], True)
    # Token forgery fails signature verification.
    parts = a["access_token"].split(".")
    import base64

    payload = json.loads(base64.urlsafe_b64decode(parts[1] + "==="))
    payload["role"] = "service_role"
    parts[1] = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    check(
        request(REST_PORT, "/visits", token=".".join(parts))[0] == 401,
        "forged JWT rejected",
    )
    print("PASS: public projection/joins exclude private data; spoofed JWT rejected")

    # Direct SQL as actual API roles, never claim privileged SELECT proves RLS.
    def as_role(role, statement, subject=None):
        claims = json.dumps({"sub": subject, "role": role})
        return sql(
            "begin; set local role " + role + "; "
            "select set_config('request.jwt.claims','" + claims + "',true); "
            "select set_config('request.jwt.claim.sub','"
            + (subject or "")
            + "',true); "
            + statement
            + "; rollback;"
        ).splitlines()[-1]

    check(
        as_role("anon", "select count(*) from public.public_catalogue()") == "3",
        "SQL anonymous approved projection only",
    )
    check(
        as_role("anon", "select count(*) from public.bathrooms") == "0",
        "SQL raw catalogue hides Auth IDs",
    )
    check(
        as_role("authenticated", "select count(*) from public.visits", bid) == "1",
        "SQL B private scope",
    )
    check(
        as_role(
            "authenticated",
            "select count(*) from public.visits where id='" + av + "'",
            bid,
        )
        == "0",
        "SQL cross-user denial",
    )
    for role, statement, subject in [
        ("anon", "select * from public.visits", None),
        (
            "authenticated",
            "update public.visits set owner_id='" + bid + "' where id='" + av + "'",
            aid,
        ),
        (
            "authenticated",
            "insert into app_private.moderators values ('" + aid + "')",
            aid,
        ),
        (
            "authenticated",
            "update public.reviews set rating=8 where id='" + ar["id"] + "'",
            aid,
        ),
    ]:
        denied = False
        try:
            as_role(role, statement, subject)
        except RuntimeError:
            denied = True
        check(denied, "SQL role rejects invalid operation")
    check(
        sql(
            "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('profiles','bathrooms','visits','reviews','favourites') and c.relrowsecurity"
        )
        == "5",
        "all exposed tables RLS",
    )
    check(
        sql(
            "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('public_reviews','approve_bathroom') and p.prosecdef and p.proconfig @> array['search_path=\"\"']"
        )
        == "2",
        "definer functions fixed empty search_path",
    )
    # Immutable trigger protects even an accidentally broadened column grant.
    denied = False
    try:
        sql(
            "begin; update public.reviews set visit_id='"
            + av2
            + "' where id='"
            + ar["id"]
            + "'; rollback;"
        )
    except RuntimeError:
        denied = True
    check(denied, "SQL immutable association trigger")
    failed = False
    try:
        sql("begin; create table app_private.rollback_probe(id int); select 1/0; commit;")
    except RuntimeError:
        failed = True
    check(
        failed and sql("select to_regclass('app_private.rollback_probe') is null") == "t",
        "failed transaction leaves no partial DDL",
    )
    print("PASS: SQL role checks, RLS inventory, fixed function paths and immutable trigger")

    # Eligible own deletion; visit deletion cascades the optional review, not favourites.
    api("reviews?id=eq." + ar["id"], "DELETE", user=a)
    check(api("reviews?id=eq." + ar["id"], user=a) == [], "own review delete")
    api("visits?id=eq." + av2, "DELETE", user=a)
    check(api("reviews?visit_id=eq." + av2, user=a) == [], "visit delete cascades review")
    check(len(api("favourites", user=a)) == 1, "visit delete preserves favourite")
    api("favourites?bathroom_id=eq." + ONE, "DELETE", user=a)
    check(api("favourites", user=a) == [], "own favourite delete")
    api("profiles?id=eq." + aid, "PATCH", {"username": "poc_fictional_a"}, a)
    api("reviews", "POST", review(av), a, 201)
    api("favourites", "POST", {"bathroom_id": ONE}, a, 201)
    api(
        "visits",
        "POST",
        {"bathroom_id": TWO, "visited_at": "2026-02-02T12:00:00Z"},
        a,
        201,
    )
    check(
        api("bathrooms?id=eq." + private_proposal["id"]) == [],
        "pending stays private after all joins",
    )

    # Refresh, global logout, revoked refresh and bounded residual JWT lifetime.
    for session in [a, b]:
        status, refreshed = request(
            AUTH_PORT,
            "/token?grant_type=refresh_token",
            "POST",
            {"refresh_token": session["refresh_token"]},
        )
        check(status == 200 and "access_token" in refreshed, "session refresh")
        api("visits", user=refreshed)
        status, _ = request(
            AUTH_PORT, "/logout?scope=global", "POST", token=refreshed["access_token"]
        )
        check(status == 204, "global logout")
        status, _ = request(
            AUTH_PORT,
            "/token?grant_type=refresh_token",
            "POST",
            {"refresh_token": refreshed["refresh_token"]},
        )
        check(status in (400, 401), "logged-out refresh revoked")
        check(
            request(AUTH_PORT, "/user", token=refreshed["access_token"])[0] in (401, 403),
            "Auth rejects revoked session",
        )
        # PostgREST validates JWT signature/expiry; logout alone does not revoke an issued JWT.
        api("visits", user=refreshed)
        session.clear()
        session.update(refreshed)
    print("PASS: refresh/logout; Auth revocation; issued API JWT remains valid until expiry")
    if not check_expiry:
        login(accounts[0])
        login(accounts[1])
        print("SKIP: managed long-lived JWT expiry; destination tests retain expiry check")
        print("PASS: " + str(COUNT) + " authorization/authentication assertions")
        return
    # PostgREST v14.18 permits 30 seconds of clock skew after exp.
    deadline = time.monotonic() + 100
    progress_at = time.monotonic() + 45
    while time.monotonic() < deadline:
        if all(request(REST_PORT, "/visits", token=s["access_token"])[0] == 401 for s in [a, b]):
            break
        if time.monotonic() >= progress_at:
            print("Waiting for 60-second JWT expiry plus PostgREST clock-skew tolerance...")
            progress_at += 45
        time.sleep(1)
    else:
        raise RuntimeError("Expired access token still accepted")
    check(True, "expired access tokens rejected")
    login(accounts[0])
    login(accounts[1])
    print("PASS: JWT expiry and fresh password login after logout")
    print("PASS: " + str(COUNT) + " authorization/authentication assertions")
