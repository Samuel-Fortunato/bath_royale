"""A3 HTTP authorization and publication tests, isolated loopback infrastructure only."""

import os
import secrets
import sys
import uuid

import poc

if poc.INSTANCE not in ("community", "protocol", "sync"):
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
    # Current owner-approved contract supersedes A3 username/publication tests.
    from simplification import verify as current_verification

    return current_verification()


def main():
    poc.start(migrations=False)
    try:
        poc.migrate(through="202611270008_community.sql")
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
