"""A3.1 direct API/privacy/entitlement checks; disposable community stack only."""

import json
import os
import subprocess
import sys
import tempfile
import uuid

import community as c
import poc


def verify():
    a, b, admin = c.account(), c.account(), c.account()
    aid = a["user"]["id"]
    private, _ = c.private_bathroom(a)
    visit, old_review, _ = c.private_review(a, private)
    before = poc.sql(
        "select row_to_json(r) from public.reviews r where id=" + "'" + old_review + "'"
    )
    poc.migrate()
    after = poc.sql(
        "select row_to_json(r) from public.reviews r where id=" + "'" + old_review + "'"
    )
    c.check(json.loads(before) == json.loads(after), "historical private review unchanged")
    shared = str(uuid.uuid4())
    contribution = c.command(
        "contribution",
        shared,
        "contributeBathroom",
        dict(name="Trono A31 " + shared, emoji="👑", accent=2),
    )
    c.denied("rpc/sync_submit", dict(command=contribution), a)
    c.denied("rpc/grant_bathroom_creation", dict(account_email=a["user"]["email"], allowed=True), a)
    # Editable metadata never conveys the protected entitlement.
    status, _ = poc.request(
        poc.AUTH_PORT,
        "/user",
        "PUT",
        {"data": {"create_bathroom": True, "is_admin": True}},
        a["access_token"],
    )
    c.check(status == 200, "metadata attack stored without authority")
    c.denied("rpc/sync_submit", dict(command=contribution), a)
    poc.sql("insert into app_private.moderators values('" + admin["user"]["id"] + "')")
    c.api(
        "rpc/grant_bathroom_creation", dict(account_email=a["user"]["email"], allowed=True), admin
    )
    result = c.submit(contribution, a)
    c.check(c.submit(contribution, a) == result, "contribution receipt idempotency")
    duplicate = c.command(
        "contribution",
        str(uuid.uuid4()),
        "contributeBathroom",
        dict(name=contribution["payload"]["name"].upper(), emoji="🚽", accent=0),
    )
    c.denied("rpc/sync_submit", dict(command=duplicate), a)
    c.denied("bathrooms", dict(name="Bypass"), a)
    c.api(
        "rpc/grant_bathroom_creation", dict(account_email=a["user"]["email"], allowed=False), admin
    )
    c.denied(
        "rpc/sync_submit",
        dict(
            command=c.command(
                "contribution",
                str(uuid.uuid4()),
                "contributeBathroom",
                dict(name="Denied", emoji="🚽", accent=0),
            )
        ),
        a,
    )
    _, cursor = c.pull(a, "private")
    c.denied("rpc/sync_pull", dict(feed="private", checkpoint=cursor, page_size=20), b)
    # Legacy queued operations remain private even when they reference a shared row.
    legacy_visit, legacy_review, _ = c.private_review(a, shared)
    c.check(
        not any(r["id"] in (old_review, legacy_review) for r in c.api("rpc/public_reviews", {})),
        "historical/private command never auto-published",
    )
    for kind, action, payload, target in [
        ("publication", "publishReview", {"review_id": old_review, "published": True}, old_review),
        ("link", "linkBathroom", {"shared_id": shared}, private),
        ("profile", "setUsername", {"username": "obsolete"}, aid),
    ]:
        c.denied("rpc/sync_submit", dict(command=c.command(kind, target, action, payload)), a)
    # New explicit-version submission is public, anonymous, atomic and profile-free.
    v, r = str(uuid.uuid4()), str(uuid.uuid4())
    stamp = 1800000000123456
    review = dict(
        id=r,
        visit=v,
        bathroom=shared,
        author=aid,
        created=stamp,
        updated=stamp,
        rating=4.3,
        paper=2,
        hygiene=4,
        comfort=3,
        aesthetics=2,
        tags='[{"emoji":"✨","label":"Limpo"}]',
        comment="Um trono fictício de respeito.",
        provenance="user_created",
    )
    command = c.command(
        "review",
        r,
        "createCommunityVisitReview",
        dict(
            visit=dict(id=v, bathroom=shared, user=aid, at=stamp, provenance="user_created"),
            review=review,
        ),
    )
    c.denied("rpc/sync_submit", dict(command=command))
    outcome = c.submit(command, a)
    c.check(c.submit(command, a) == outcome, "anonymous submission exact replay")
    row = next(x for x in c.api("reviews?id=eq." + r, session=a, method="GET"))
    public_id = row["public_id"]
    projection = next(x for x in c.api("rpc/public_reviews", {}, b) if x["id"] == public_id)
    c.check(
        set(projection)
        == {
            "id",
            "bathroom_id",
            "rating",
            "paper",
            "hygiene",
            "comfort",
            "aesthetics",
            "tags",
            "comment",
        },
        "anonymous exact projection allowlist",
    )
    text = json.dumps(c.pull()[0])
    c.check(
        all(
            x not in text
            for x in [
                aid,
                v,
                r,
                visit,
                legacy_visit,
                a["user"]["email"],
                "username",
                "author_id",
                str(stamp),
            ]
        ),
        "public feed has no personal or correlatable author information",
    )
    c.check(
        c.api("reviews?id=eq." + r, session=b, method="GET") == [],
        "other account cannot read private source",
    )
    c.check(
        c.api("visits?id=eq." + v, session=b, method="GET") == [], "other account cannot read visit"
    )
    c.api("reviews?id=eq." + r, {"rating": 1.1}, a, method="PATCH")
    c.check(
        next(x for x in c.api("rpc/public_reviews", {}) if x["id"] == public_id)["rating"] == 1.1,
        "owner edits anonymous review",
    )
    c.check(
        c.api("reviews?id=eq." + r, {"rating": 0}, b, method="PATCH") == [],
        "cross-owner edit denied",
    )
    c.submit(
        c.command(
            "report",
            str(uuid.uuid4()),
            "reportContent",
            {"kind": "review", "target": public_id, "reason": "Verificação de moderação"},
        ),
        b,
    )
    c.denied("rpc/moderation_reports", {}, b)
    reports = c.api("rpc/moderation_reports", {}, admin)["reports"]
    report = next(x for x in reports if x["target"] == public_id)
    c.api(
        "rpc/moderate_content",
        dict(content_kind="review", content_id=public_id, hide=True, report_id=report["id"]),
        admin,
    )
    c.check(
        not any(x["id"] == public_id for x in c.api("rpc/public_reviews", {})),
        "moderation hides anonymous review",
    )
    c.check(
        all(x["deleted"] for x in c.pull()[0] if x["entityId"] == public_id),
        "historical replay cannot reveal moderated content",
    )
    c.api(
        "rpc/moderate_content",
        dict(content_kind="review", content_id=public_id, hide=False, report_id=report["id"]),
        admin,
    )
    c.api("reviews?id=eq." + r, session=a, method="DELETE")
    c.check(
        not any(x["id"] == public_id for x in c.api("rpc/public_reviews", {})),
        "owner deletion removes public projection",
    )
    c.check(
        len(c.api("visits?id=eq." + v, session=a, method="GET")) == 1,
        "review-only deletion retains visit",
    )
    c.check(
        c.api("rpc/public_catalogue", {})[-1].get("classification") in ("official", "community"),
        "catalogue classification",
    )
    if "--flutter" in sys.argv:
        # Give A creation permission for the integration's distinct test row.
        c.api(
            "rpc/grant_bathroom_creation",
            dict(account_email=a["user"]["email"], allowed=True),
            admin,
        )
        fd, path = tempfile.mkstemp(prefix="a31-client-", suffix=".json", dir=poc.STATE)
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(dict(a=a, b=b, endpoint=f"http://127.0.0.1:{poc.REST_PORT}/"), f)
            result = subprocess.run(
                ["flutter", "test", "--no-pub", "test/real_community_test.dart"],
                env=dict(os.environ, BATH_COMMUNITY_TEST_CONFIG=path),
                cwd=poc.ROOT,
                capture_output=True,
                text=True,
            )
            output = result.stdout + result.stderr
            for user in (a, b):
                for key in ("access_token", "refresh_token"):
                    output = output.replace(user[key], "[redacted]")
            print(output)
            c.check(result.returncode == 0, "real anonymous two-account client integration")
        finally:
            os.unlink(path)
    print(f"PASS: {c.COUNT} A3.1 API/privacy/entitlement assertions")


if __name__ == "__main__":
    os.umask(0o077)
    poc.start(migrations=False)
    try:
        poc.migrate(through="202611270008_community.sql")
        verify()
        from sync_portability import verify as portability

        portability()
    finally:
        poc.compose("stop")
