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
    print("PASS: A4 additive identity, entitlement, integer-input and historical queue/edit checks")


def main():
    if poc.INSTANCE not in ("community", "protocol"):
        raise RuntimeError("Disposable community/protocol only")
    poc.start()
    try:
        verify_inputs()
    finally:
        poc.compose("stop")


if __name__ == "__main__":
    main()
