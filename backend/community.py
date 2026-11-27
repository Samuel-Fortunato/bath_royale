"""A3 HTTP authorization and publication tests, isolated loopback infrastructure only."""

import concurrent.futures
import json
import os
import secrets
import subprocess
import sys
import tempfile
import uuid

import poc

if poc.INSTANCE != "community":
    raise RuntimeError("Use only POC_INSTANCE=community")
COUNT = 0


def check(value, label):
    global COUNT
    if not value:
        raise RuntimeError("Community assertion failed: " + label)
    COUNT += 1


def api(path, body=None, session=None, method="POST", expected=200):
    status, result = poc.request(
        poc.REST_PORT, "/" + path, method, body, session and session["access_token"]
    )
    check(
        status == expected,
        path.split("?")[0]
        + " HTTP "
        + str(status)
        + " expected "
        + str(expected)
        + (" " + result.get("message", "") if isinstance(result, dict) else ""),
    )
    return result


def denied(path, body=None, session=None, method="POST"):
    status, _ = poc.request(
        poc.REST_PORT, "/" + path, method, body, session and session["access_token"]
    )
    check(status in (400, 401, 403, 404, 409), "denied " + path.split("?")[0])


def account():
    status, result = poc.request(
        poc.AUTH_PORT,
        "/signup",
        "POST",
        {
            "email": "community-" + uuid.uuid4().hex + "@example.invalid",
            "password": secrets.token_urlsafe(32),
        },
    )
    check(status == 200 and result.get("access_token"), "fictional signup")
    return result


def command(kind, target, action, payload, base=None, dependencies=None):
    return dict(
        operationId=str(uuid.uuid4()),
        entityType=kind,
        entityId=target,
        type=action,
        payload=payload,
        baseRevision=base,
        dependencies=dependencies or {},
    )


def submit(c, user):
    return api("rpc/sync_submit", {"command": c}, user)


def pull(user=None, feed="catalogue", cursor=None):
    result = []
    for _ in range(100):
        page = api("rpc/sync_pull", dict(feed=feed, checkpoint=cursor, page_size=100), user)
        result.extend(page["changes"])
        cursor = page["checkpoint"]
        if len(page["changes"]) < 100:
            return result, cursor
    raise RuntimeError("Unbounded test feed")


def private_bathroom(a):
    target = str(uuid.uuid4())
    c = command(
        "bathroom",
        target,
        "createBathroom",
        dict(
            id=target,
            name="Private " + target,
            normalized_name="ignored",
            creator=a["user"]["id"],
            emoji="🚽",
            accent=0,
            provenance="user_created",
        ),
    )
    return target, submit(c, a)


def private_review(a, bathroom):
    visit, review = str(uuid.uuid4()), str(uuid.uuid4())
    actor = a["user"]["id"]
    c = command(
        "review",
        review,
        "createVisitReview",
        dict(
            visit=dict(
                id=visit,
                bathroom=bathroom,
                user=actor,
                at=1800000000000000,
                provenance="user_created",
            ),
            review=dict(
                id=review,
                visit=visit,
                bathroom=bathroom,
                author=actor,
                created=1800000000000000,
                updated=1800000000000000,
                rating=4.2,
                paper=2,
                hygiene=4,
                comfort=3,
                aesthetics=1,
                tags='[{"emoji":"✨","label":"Limpo"}]',
                comment="Explicit community test",
                provenance="user_created",
            ),
        ),
    )
    return visit, review, submit(c, a)


def verify():
    a, b, admin = account(), account(), account()
    aid = a["user"]["id"]
    private, _ = private_bathroom(a)
    visit, review, _ = private_review(a, private)
    # A2 private rows exist before the additive A3 migration on the first run.
    before = poc.sql("select row_to_json(r) from public.reviews r where id='" + review + "'")
    poc.migrate()
    after = poc.sql("select row_to_json(r) from public.reviews r where id='" + review + "'")
    check(
        all(json.loads(after)[k] == v for k, v in json.loads(before).items()),
        "non-destructive A2 review migration",
    )
    check(
        not any(r["id"] == json.loads(after)["public_id"] for r in api("rpc/public_reviews", {})),
        "no implicit historical publication",
    )
    denied("visits", method="GET")
    check(api("visits", session=b, method="GET") == [], "private visits isolated")
    check(api("reviews?id=eq." + review, session=b, method="GET") == [], "private review isolated")
    for who in (None, b):
        denied(
            "rpc/sync_submit",
            {
                "command": command(
                    "publication", review, "publishReview", {"review_id": review, "published": True}
                )
            },
            who,
        )
    shared = str(uuid.uuid4())
    name = "  Trono  " + shared + "  "
    contribution = command(
        "contribution",
        shared,
        "contributeBathroom",
        {"name": name.strip(), "emoji": "👑", "accent": 2},
    )
    denied("rpc/sync_submit", {"command": contribution})
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        results = list(pool.map(lambda _: submit(contribution, a), range(2)))
    check(results[0] == results[1], "contribution receipt replay")
    duplicate = command(
        "contribution",
        str(uuid.uuid4()),
        "contributeBathroom",
        {"name": name.strip().upper().replace("  ", " "), "emoji": "🚽", "accent": 0},
    )
    denied("rpc/sync_submit", {"command": duplicate}, b)
    catalogue, _ = pull()
    check(
        any(c["entityId"] == shared and not c["deleted"] for c in catalogue), "anonymous catalogue"
    )
    check(not any(c["entityId"] == private for c in catalogue), "private bathroom absent publicly")
    for who in (None, b):
        check(
            api("bathrooms?id=eq." + shared, session=who, method="GET") == [],
            "base bathroom Auth identity isolated",
        )
    check(
        all(
            set(row) == {"id", "name", "emoji", "accent", "institution", "locality"}
            for row in api("rpc/public_catalogue", {})
        ),
        "narrow public catalogue projection",
    )

    link = command("link", private, "linkBathroom", {"shared_id": shared})
    denied("rpc/sync_submit", {"command": link}, b)
    submit(link, a)
    check(
        not any(r["bathroom_id"] == shared for r in api("rpc/public_reviews", {})),
        "association does not publish history",
    )
    username = command(
        "profile", aid, "setUsername", {"username": "alpha_" + uuid.uuid4().hex[:16]}
    )
    submit(username, a)
    denied("profiles", method="GET")
    check(api("profiles?id=eq." + aid, session=b, method="GET") == [], "auth identity not public")
    pub = command("publication", review, "publishReview", {"review_id": review, "published": True})
    outcome = submit(pub, a)
    public = [r for r in api("rpc/public_reviews", {}) if r["bathroom_id"] == shared]
    check(len(public) == 1 and public[0]["bathroom_id"] == shared, "explicit linked publication")
    public_id = public[0]["id"]
    check(public_id != review and public[0]["author_id"] != aid, "independent public identities")
    check(
        set(public[0])
        == {
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
        },
        "strict public allowlist",
    )
    raw = json.dumps(public)
    check(
        all(
            secret not in raw
            for secret in [visit, review, aid, a["user"]["email"], "1800000000000000"]
        ),
        "public projection privacy",
    )
    check(
        [r for r in api("rpc/public_reviews", {}, b) if r["bathroom_id"] == shared] == public,
        "two account community visibility",
    )
    denied("reviews?id=eq." + review, {"published": False}, b, method="PATCH")
    denied("reviews?id=eq." + review, {"published": True}, a, method="PATCH")
    check(submit(pub, a) == outcome, "lost acknowledgement publication replay")
    # Direct private editing updates only explicitly published reviews.
    api(
        "reviews?id=eq." + review,
        {"rating": 3.1, "comment": "Edited public review"},
        a,
        method="PATCH",
    )
    check(
        next(r for r in api("rpc/public_reviews", {}) if r["id"] == public_id)["rating"] == 3.1,
        "owner edits published review",
    )
    report = command(
        "report",
        str(uuid.uuid4()),
        "reportContent",
        {"kind": "review", "target": public_id, "reason": "Teste de moderação"},
    )
    submit(report, b)
    duplicate_report = dict(report, operationId=str(uuid.uuid4()), entityId=str(uuid.uuid4()))
    submit(duplicate_report, b)
    denied("rpc/moderation_reports", {}, b)
    denied(
        "rpc/moderate_content",
        dict(content_kind="review", content_id=public_id, hide=True, report_id=None),
        b,
    )
    poc.sql("insert into app_private.moderators values('" + admin["user"]["id"] + "')")
    reports = [
        r for r in api("rpc/moderation_reports", {}, admin)["reports"] if r["target"] == public_id
    ]
    check(len(reports) == 1 and "reporter" not in reports[0], "minimal moderator queue")
    api(
        "rpc/moderate_content",
        dict(content_kind="review", content_id=public_id, hide=True, report_id=reports[0]["id"]),
        admin,
    )
    check(
        not any(r["id"] == public_id for r in api("rpc/public_reviews", {})),
        "moderation removes aggregates input",
    )
    replay, _ = pull()
    check(
        all(c["deleted"] for c in replay if c["entityId"] == public_id),
        "historical feed cannot reveal hidden text",
    )
    denied(
        "rpc/sync_submit",
        {
            "command": command(
                "publication",
                review,
                "publishReview",
                {"review_id": review, "published": True},
                outcome["revision"],
            )
        },
        a,
    )
    api(
        "rpc/moderate_content",
        dict(content_kind="review", content_id=public_id, hide=False, report_id=reports[0]["id"]),
        admin,
    )
    # Refresh base after external private edit; publication state has its own CAS.
    withdrawal = command(
        "publication",
        review,
        "withdrawReview",
        {"review_id": review, "published": False},
        outcome["revision"],
    )
    result = submit(withdrawal, a)
    check(result["status"] == "acknowledged", "owner withdrawal")
    stale = command(
        "publication",
        review,
        "publishReview",
        {"review_id": review, "published": True},
        outcome["revision"],
    )
    check(
        submit(stale, a)["status"] == "conflict", "concurrent publication CAS preserves withdrawal"
    )
    check(
        not any(r["id"] == public_id for r in api("rpc/public_reviews", {})),
        "withdrawal invisible to anonymous and other users",
    )
    replay, _ = pull()
    check(
        all(c["deleted"] for c in replay if c["entityId"] == public_id),
        "historical feed cannot reveal withdrawn review",
    )
    _, other_cursor = pull(b, "private")
    denied("rpc/sync_pull", dict(feed="private", checkpoint=other_cursor, page_size=20), a)
    denied("rpc/sync_pull", dict(feed="private", checkpoint=None, page_size=20))
    own, _ = pull(a, "private")
    foreign, _ = pull(b, "private")
    check(
        not any(c["entityId"] in [private, visit, review] for c in foreign),
        "cross account private feed isolation",
    )
    check(any(c["entityId"] == review for c in own), "own review remains after withdrawal")
    # User metadata cannot self-promote, nor can clients reach internal tables/helpers.
    denied("rpc/private_sync_submit", {"command": pub}, a)
    denied("rpc/is_moderator", {}, a)
    denied(
        "bathrooms", {"name": "Escalation", "community": True, "publication_status": "approved"}, a
    )
    check(
        api("visits?id=eq." + visit, session=a, method="GET")[0]["id"] == visit,
        "private visit preserved",
    )
    if "--flutter" in sys.argv:
        fd, path = tempfile.mkstemp(prefix="community-flutter-", suffix=".json", dir=poc.STATE)
        try:
            with os.fdopen(fd, "w") as stream:
                json.dump(dict(a=a, b=b, endpoint=f"http://127.0.0.1:{poc.REST_PORT}/"), stream)
            result = subprocess.run(
                ["flutter", "test", "--no-pub", "test/real_community_test.dart"],
                cwd=poc.ROOT,
                env=dict(os.environ, BATH_COMMUNITY_TEST_CONFIG=path),
                capture_output=True,
                text=True,
            )
            # Never emit tokens/HTTP response bodies, even on assertion failure.
            report = result.stdout + result.stderr
            for session in (a, b):
                for key in ("access_token", "refresh_token"):
                    report = report.replace(session[key], "[redacted]")
            print(report)
            check(result.returncode == 0, "real Flutter two-account community integration")
        finally:
            os.unlink(path)
    print(f"PASS: {COUNT} A3 direct HTTP/migration/privacy/community assertions")


def main():
    poc.start(migrations=False)
    try:
        poc.migrate(through="202611270007_grapheme_grant.sql")
        verify()
        from sync_portability import verify as verify_portability

        verify_portability()
    finally:
        poc.compose("stop")
        print("Stopped isolated community stack; no managed deployment")


if __name__ == "__main__":
    os.umask(0o077)
    sys.stdout.reconfigure(line_buffering=True)
    main()
