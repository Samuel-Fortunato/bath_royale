"""Release-security rehearsal. Refuses all retained owner/managed instances."""

import base64
import hmac
import json
import secrets
import time
import uuid

import community as c
import poc


def verify():
    if poc.INSTANCE not in ("community", "protocol"):
        raise RuntimeError("Disposable infrastructure only")
    password = secrets.token_urlsafe(24)
    # The signup helper uses a random password, so create a known independent account.
    email = "release-" + uuid.uuid4().hex + "@example.invalid"
    status, a = poc.request(poc.AUTH_PORT, "/signup", "POST", dict(email=email, password=password))
    c.check(status == 200 and bool(a.get("access_token")), "open registration")
    new = secrets.token_urlsafe(24)
    for payload in [dict(password=new), dict(password=new, current_password="wrong")]:
        status, result = poc.request(poc.AUTH_PORT, "/user", "PUT", payload, a["access_token"])
        c.check(status in (400, 422), "direct missing/wrong password denied")
    status, _ = poc.request(
        poc.AUTH_PORT,
        "/user",
        "PUT",
        dict(password=new, current_password=password),
        a["access_token"],
    )
    c.check(status == 200, "current password accepted by server")
    status, a = poc.request(
        poc.AUTH_PORT, "/token?grant_type=password", "POST", dict(email=email, password=new)
    )
    c.check(status == 200, "new password login")
    code = c.api("rpc/create_alpha_recovery_code", {}, a)
    actor, secret = code.split(":")
    c.check(actor == a["user"]["id"] and len(secret) == 64, "one-time recovery credential")
    c.denied("rpc/create_alpha_recovery_code", {})
    c.check(
        poc.sql(
            "select count(*) from app_private.alpha_recovery where user_id='"
            + actor
            + "' and digest=extensions.digest('"
            + secret
            + "','sha256')"
        )
        == "1",
        "only digest retained",
    )
    replacement = c.api("rpc/create_alpha_recovery_code", {}, a)
    c.check(replacement != code, "replacement rotates credential")
    poc.sql(
        "update auth.sessions set created_at=now()-interval '10 minutes' where user_id='"
        + actor
        + "'"
    )
    c.denied("rpc/create_alpha_recovery_code", {}, a)
    c.check(
        poc.sql("select app_private.consume_alpha_recovery('" + replacement + "')") == actor,
        "operator consumes proof once",
    )
    c.check(
        poc.sql("select count(*) from app_private.alpha_recovery where user_id='" + actor + "'")
        == "0",
        "consumed proof cannot be replayed",
    )

    # Native Auth admin reset after proof consumption, never email ownership.
    def encoded(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")

    header = encoded(dict(alg="HS256", typ="JWT"))
    claims = encoded(dict(role="service_role", exp=int(time.time()) + 120))
    unsigned = header + "." + claims
    key = poc.initialize()["JWT_SECRET"]
    signature = (
        base64.urlsafe_b64encode(hmac.digest(key.encode(), unsigned.encode(), "sha256"))
        .decode()
        .rstrip("=")
    )
    operator = unsigned + "." + signature
    reset = secrets.token_urlsafe(32)
    status, _ = poc.request(
        poc.AUTH_PORT, "/admin/users/" + actor, "PUT", dict(password=reset), a["access_token"]
    )
    c.check(status == 403, "ordinary API cannot reset another password")
    status, _ = poc.request(
        poc.AUTH_PORT, "/admin/users/" + actor, "PUT", dict(password=reset), operator
    )
    c.check(status == 200, "operator reset after proof")
    poc.sql("delete from auth.sessions where user_id='" + actor + "'")
    status, recovered = poc.request(
        poc.AUTH_PORT, "/token?grant_type=password", "POST", dict(email=email, password=reset)
    )
    c.check(status == 200 and recovered["user"]["id"] == actor, "recovery retains exact account")
    a = recovered
    b = c.account()
    shared = str(uuid.uuid4())
    poc.sql("insert into app_private.bathroom_creators values('" + actor + "')")
    c.submit(
        c.command(
            "contribution",
            shared,
            "contributeBathroom",
            dict(name="Erasure " + shared, emoji="👑", accent=1),
        ),
        a,
    )
    c.private_review(b, shared)
    c.private_bathroom(a)
    poc.sql("select app_private.erase_alpha_domain('" + actor + "')")
    c.check(
        poc.sql("select count(*) from public.bathrooms where contributor_id='" + actor + "'")
        == "0",
        "private domain erasure",
    )
    c.check(
        poc.sql("select count(*) from public.visits where owner_id='" + b["user"]["id"] + "'")
        == "1",
        "other account and shared bathroom preserved",
    )
    for route in ["/recover", "/otp"]:
        status, _ = poc.request(poc.AUTH_PORT, route, "POST", dict(email=email))
        c.check(status >= 400, "unverified email cannot recover account")
    c.denied("rpc/erase_alpha_domain", dict(actor=actor), a)
    status, _ = poc.request(poc.AUTH_PORT, "/admin/users/" + actor, "DELETE", token=operator)
    c.check(status == 200, "native Auth account deletion after domain erasure")
    c.check(
        poc.sql("select count(*) from auth.users where id='" + actor + "'") == "0",
        "identity removed",
    )
    poc.sql(
        "insert into app_private.alpha_signup_buckets values(current_date,100) on conflict(day) do update set attempts=100"
    )
    try:
        status, _ = poc.request(
            poc.AUTH_PORT,
            "/signup",
            "POST",
            dict(email=uuid.uuid4().hex + "@example.invalid", password=new),
        )
        c.check(status == 429, "global registration quota enforced")
    finally:
        poc.sql("delete from app_private.alpha_signup_buckets where day=current_date")
    print(
        "PASS: open registration, direct password bypass denial, recovery proof, mail denial and quota"
    )


if __name__ == "__main__":
    if poc.INSTANCE not in ("community", "protocol"):
        raise RuntimeError("Disposable infrastructure only")
    poc.start()
    try:
        verify()
    finally:
        poc.compose("stop")
