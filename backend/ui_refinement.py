"""A4 input/feedback verification against disposable local infrastructure only."""

import uuid

import community as c
import poc


def verify_inputs():
    for emoji in ["👩🏽‍💻", "👨‍👩‍👧‍👦", "🇵🇹", "1️⃣", "❤️", "↔️", "◀️", "⬛"]:
        c.check(
            poc.sql("select app_private.valid_tag_emoji('" + emoji + "')") == "t",
            "shared single emoji validator",
        )
    a, b = c.account(), c.account()
    actor = a["user"]["id"]
    target = str(uuid.uuid4())
    proposal = c.command(
        "contribution",
        target,
        "contributeBathroom",
        dict(name="A4 compound emoji " + target, emoji="👩🏽‍💻", accent=4, accent_rgb=0x12ABEF),
    )
    c.denied("rpc/sync_submit", dict(command=proposal), a)
    poc.sql("insert into app_private.bathroom_creators values('" + actor + "')")
    result = c.submit(proposal, a)
    c.check(c.submit(proposal, a) == result, "RGB creation idempotency")
    catalogue = c.api("rpc/public_catalogue", {})
    bathroom = next(r for r in catalogue if r["id"] == target)
    c.check(
        bathroom["emoji"] == "👩🏽‍💻"
        and bathroom["accent_rgb"] == 0x12ABEF
        and bathroom["accent"] == 4,
        "legacy palette and arbitrary RGB remain separate",
    )
    rows, _ = c.pull(b, "catalogue")
    c.check(
        any(r["entityId"] == target and r["payload"].get("accent_rgb") == 0x12ABEF for r in rows),
        "RGB public sync",
    )
    for emoji, rgb in [
        ("text", 0),
        ("😀😀", 1),
        ("🇵", 2),
        ("🏽", 3),
        ("👑", -1),
        ("👑", 0x1000000),
    ]:
        bad = c.command(
            "contribution",
            str(uuid.uuid4()),
            "contributeBathroom",
            dict(name="A4 invalid " + str(uuid.uuid4()), emoji=emoji, accent=0, accent_rgb=rgb),
        )
        c.denied("rpc/sync_submit", dict(command=bad), a)

    def review_command(score, action="createCommunityVisitReviewV2"):
        visit, review = str(uuid.uuid4()), str(uuid.uuid4())
        stamp = 1800000000000000 + uuid.uuid4().int % 100000000
        return c.command(
            "review",
            review,
            action,
            dict(
                visit=dict(
                    id=visit, bathroom=target, user=actor, at=stamp, provenance="user_created"
                ),
                review=dict(
                    id=review,
                    visit=visit,
                    bathroom=target,
                    author=actor,
                    created=stamp,
                    updated=stamp,
                    rating=score,
                    paper=2,
                    hygiene=4,
                    comfort=3,
                    aesthetics=2,
                    tags="[]",
                    comment="A4 test",
                    provenance="user_created",
                ),
            ),
        )

    for score in [0, 0.5, 2.37, 5.1]:
        command = review_command(score)
        c.denied("rpc/sync_submit", dict(command=command), a)
        c.check(
            poc.sql(
                "select count(*) from public.visits where id='"
                + command["payload"]["visit"]["id"]
                + "'"
            )
            == "0",
            "invalid atomic input creates no visit",
        )
    for score in [1, 2, 3, 4, 5]:
        command = review_command(score)
        result = c.submit(command, a)
        c.check(c.submit(command, a) == result, "integer review replay")
    for score in [0, 2.37, 4.7]:
        command = review_command(score, "createVisitReview")  # durable pre-A4 queue
        result = c.submit(command, a)
        r = command["payload"]["review"]
        c.check(c.submit(command, a) == result, "legacy queued rating replay")
        changed = dict(r, comment="Unrelated field edited")
        update = c.command(
            "review", r["id"], "updateReviewV2", dict(review=changed), result["revision"]
        )
        result = c.submit(update, a)
        c.check(
            float(poc.sql("select rating from public.reviews where id='" + r["id"] + "'")) == score,
            "unrelated historical edit exact",
        )
        invalid = c.command(
            "review",
            r["id"],
            "updateReviewV2",
            dict(review=dict(changed, rating=2.5)),
            result["revision"],
        )
        c.denied("rpc/sync_submit", dict(command=invalid), a)
        c.denied("rpc/sync_submit", dict(command=update), b)
    c.check(
        poc.sql(
            "select count(*) from public.bathrooms where accent_rgb is null and accent between 0 and 5"
        )
        != "0",
        "existing identities preserved",
    )
    command = review_command("4.123456789123456789", "createVisitReview")
    result = c.submit(command, a)
    r = command["payload"]["review"]
    changed = dict(r, rating=4.123456789123457, comment="Unrelated client-double edit")
    update = c.command(
        "review",
        r["id"],
        "updateReviewV2",
        dict(review=changed, preserveRating=True),
        result["revision"],
    )
    c.submit(update, a)
    c.check(
        poc.sql("select rating::text from public.reviews where id='" + r["id"] + "'")
        == "4.123456789123456789",
        "unrelated edit preserves original server numeric precision",
    )
    print("PASS: A4 additive identity, entitlement, integer-input and historical queue/edit checks")


def verify_feedback():
    # Retained disposable runs may have intentionally filled the hourly quota.
    poc.sql(
        "update app_private.alpha_feedback set submitted_at=clock_timestamp()-interval '2 days'"
    )
    a, admin = c.account(), c.account()
    poc.sql("insert into app_private.moderators values('" + admin["user"]["id"] + "')")
    body = dict(
        report_id=str(uuid.uuid4()),
        retry_key=str(uuid.uuid4()),
        category="problem",
        description="O botão ficou escondido.",
        app_version="0.1.0-dev-a4.1023",
        platform_version="Android 16 (SDK 36)",
        screen_id="review_tags",
    )
    result = c.api("rpc/submit_alpha_feedback", body)
    c.check(result == {"submitted": True}, "anonymous feedback receives no read capability")
    c.check(
        c.api("rpc/submit_alpha_feedback", body) == result, "anonymous lost-ack retry idempotency"
    )
    for session in (None, a):
        c.denied("rpc/alpha_feedback_reports", {"page": 0}, session)
        c.denied(
            "rpc/set_alpha_feedback_status",
            {"report_id": body["report_id"], "new_status": "resolved"},
            session,
        )
        c.denied("alpha_feedback", None, session, method="GET")
    for fields in [
        dict(category="invalid"),
        dict(description="x"),
        dict(description="x" * 2001),
        dict(app_version="secret@example.com"),
        dict(platform_version="x" * 97),
        dict(screen_id="/bathroom/private-identifier"),
        dict(attachment="unexpected"),
        dict(retry_key=str(uuid.uuid4())),
        dict(description="Changed after lost acknowledgement"),
    ]:
        invalid = dict(body, **fields)
        if (
            "retry_key" not in fields
            and fields.get("description") != "Changed after lost acknowledgement"
        ):
            invalid["report_id"] = str(uuid.uuid4())
        c.denied("rpc/submit_alpha_feedback", invalid)
    reports = c.api("rpc/alpha_feedback_reports", {"page": 0}, admin)["reports"]
    row = next(r for r in reports if r["id"] == body["report_id"])
    c.check(
        set(row)
        == {
            "id",
            "category",
            "description",
            "app_version",
            "platform_version",
            "screen_id",
            "status",
            "submitted_at",
        },
        "admin projection excludes retry secret and all account data",
    )
    c.check(row["status"] == "new", "feedback initial state")
    for status in ("reviewed", "resolved"):
        c.api(
            "rpc/set_alpha_feedback_status",
            {"report_id": body["report_id"], "new_status": status},
            admin,
        )
        c.check(
            next(
                r
                for r in c.api("rpc/alpha_feedback_reports", {"page": 0}, admin)["reports"]
                if r["id"] == body["report_id"]
            )["status"]
            == status,
            "admin state persisted",
        )
    c.denied(
        "rpc/set_alpha_feedback_status",
        {"report_id": body["report_id"], "new_status": "hidden"},
        admin,
    )
    c.denied("rpc/alpha_feedback_reports", {"page": -1}, admin)
    # Exercise quota enforcement for rotating client IDs and accounts. Retained
    # fixtures are not deleted; only new disposable test rows are backdated.
    poc.sql(
        "update app_private.alpha_feedback set submitted_at=clock_timestamp()-interval '2 days'"
    )
    for index in range(30):
        c.api(
            "rpc/submit_alpha_feedback",
            dict(body, report_id=str(uuid.uuid4()), retry_key=str(uuid.uuid4())),
        )
    status, failure = poc.request(
        poc.REST_PORT,
        "/rpc/submit_alpha_feedback",
        "POST",
        dict(body, report_id=str(uuid.uuid4()), retry_key=str(uuid.uuid4())),
        a["access_token"],
    )
    c.check(
        status != 200 and failure.get("message") == "Feedback limit reached; retry later",
        "global quota resists account/client ID rotation",
    )
    c.check(
        c.api("rpc/submit_alpha_feedback", body) == result, "quota never blocks exact receipt retry"
    )
    poc.sql(
        "update app_private.alpha_feedback set submitted_at=clock_timestamp()-interval '2 days'"
    )
    # Enforce daily and total retained storage limits independently of the hourly cap.
    quota_insert = "insert into app_private.alpha_feedback(id,retry_hash,category,description,app_version,platform_version,screen_id,submitted_at) select gen_random_uuid(),decode('00','hex'),'other','Disposable quota fixture','0.1.0-quota-test','Test','other',"
    try:
        poc.sql(quota_insert + "clock_timestamp()-interval '2 hours' from generate_series(1,100)")
        status, failure = poc.request(
            poc.REST_PORT,
            "/rpc/submit_alpha_feedback",
            "POST",
            dict(body, report_id=str(uuid.uuid4()), retry_key=str(uuid.uuid4())),
        )
        c.check(
            status != 200 and failure.get("message") == "Feedback limit reached; retry later",
            "daily quota enforced",
        )
        poc.sql(
            "update app_private.alpha_feedback set submitted_at=clock_timestamp()-interval '2 days'"
        )
        poc.sql(
            quota_insert
            + "clock_timestamp()-interval '2 days' from generate_series(1,greatest(0,5000-(select count(*) from app_private.alpha_feedback)))"
        )
        status, failure = poc.request(
            poc.REST_PORT,
            "/rpc/submit_alpha_feedback",
            "POST",
            dict(body, report_id=str(uuid.uuid4()), retry_key=str(uuid.uuid4())),
        )
        c.check(
            status != 200 and failure.get("message") == "Feedback limit reached; retry later",
            "retained storage cap enforced",
        )
    finally:
        poc.sql("delete from app_private.alpha_feedback where app_version='0.1.0-quota-test'")
    print(
        "PASS: A4 anonymous feedback validation, idempotency, quotas, privacy and administrator access"
    )


def main():
    if poc.INSTANCE not in ("community", "protocol"):
        raise RuntimeError("Disposable community/protocol only")
    poc.start()
    try:
        verify_inputs()
        verify_feedback()
    finally:
        poc.compose("stop")


if __name__ == "__main__":
    main()
