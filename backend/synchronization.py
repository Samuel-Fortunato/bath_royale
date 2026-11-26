"""Opt-in real synchronization verification; exclusively the disposable sync stack."""

import base64
import concurrent.futures
import hashlib
import hmac
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid

import poc

if poc.INSTANCE != "sync":
    raise RuntimeError("Set POC_INSTANCE=sync; preserved installations are forbidden")

sys.path.insert(0, str(poc.ROOT / "backend/tests"))
import authorization as auth  # noqa: E402

COUNT = 0


def check(value, label):
    global COUNT
    if not value:
        raise RuntimeError("Synchronization assertion failed: " + label)
    COUNT += 1


def rpc(name, body, token=None, expected=200):
    status, result = poc.request(poc.REST_PORT, "/rpc/" + name, "POST", body, token)
    check(status == expected, name + " HTTP " + str(status))
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


def bathroom(actor):
    target = str(uuid.uuid4())
    return command(
        "bathroom",
        target,
        "createBathroom",
        dict(
            id=target,
            name="Proposta fictícia de sincronização",
            normalized_name="ignored",
            creator=actor,
            emoji="🚽",
            accent=0,
            provenance="user_created",
        ),
    )


def submit(value, token, expected=200):
    return rpc("sync_submit", {"command": value}, token, expected)


def pull(token=None, cursor=None, feed="private", size=100):
    return rpc("sync_pull", dict(feed=feed, checkpoint=cursor, page_size=size), token)


def pages(token=None, feed="private", cursor=None, size=2):
    changes = []
    for _ in range(2000):
        page = pull(token, cursor, feed, size)
        changes += page["changes"]
        cursor = page["checkpoint"]
        if len(page["changes"]) < size:
            return changes, cursor
    raise RuntimeError("Unbounded feed")


def server_tests(a, b):
    token, other = a["access_token"], b["access_token"]
    actor = a["user"]["id"]
    c = bathroom(actor)
    # Two concurrent HTTP requests contend on the durable receipt transaction.
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        outcomes = list(pool.map(lambda _: submit(c, token), range(2)))
    check(outcomes[0] == outcomes[1], "concurrent duplicate original result")
    check(
        poc.sql("select count(*) from public.bathrooms where id='" + c["entityId"] + "'") == "1",
        "single domain effect",
    )
    check(submit(c, token) == outcomes[0], "identical committed replay")
    altered = json.loads(json.dumps(c))
    altered["payload"]["name"] = "Different"
    submit(altered, token, 400)
    for field, value in [
        ("creator", b["user"]["id"]),
        ("publication_status", "approved"),
        ("approved_by", actor),
    ]:
        attack = bathroom(actor)
        attack["payload"][field] = value
        status, _ = poc.request(
            poc.REST_PORT, "/rpc/sync_submit", "POST", {"command": attack}, token
        )
        check(status in (400, 403), "ownership/publication attack")
        check(
            poc.sql(
                "select count(*) from app_private.sync_receipts where operation_id='"
                + attack["operationId"]
                + "'"
            )
            == "0",
            "failed transaction leaves no receipt",
        )
    rpc("sync_submit", {"command": c}, expected=401)
    rpc("sync_pull", dict(feed="private"), expected=401)
    for endpoint in ("sync_receipts", "sync_records", "sync_changes", "sync_cursors"):
        check(
            poc.request(poc.REST_PORT, "/" + endpoint, token=token)[0] == 404,
            "private protocol table hidden",
        )
    edit = command(
        "bathroom",
        c["entityId"],
        "updateBathroom",
        c["payload"],
        dependencies={c["operationId"]: outcomes[0]["revision"]},
    )
    edited = submit(edit, token)
    check(edited["revision"] > outcomes[0]["revision"], "queued edit resolves causal base")
    invalid = command(
        "bathroom",
        c["entityId"],
        "updateBathroom",
        c["payload"],
        dependencies={c["operationId"]: -1},
    )
    submit(invalid, token, 400)
    invalid["dependencies"] = {str(uuid.uuid4()): edited["revision"]}
    submit(invalid, token, 400)
    foreign = bathroom(b["user"]["id"])
    foreign_result = submit(foreign, other)
    invalid["dependencies"] = {foreign["operationId"]: foreign_result["revision"]}
    submit(invalid, token, 400)
    # Same operation UUID is independently scoped to another authenticated account.
    foreign["operationId"] = c["operationId"]
    foreign["entityId"] = str(uuid.uuid4())
    foreign["payload"]["id"] = foreign["entityId"]
    check(submit(foreign, other)["status"] == "acknowledged", "receipt account isolation")
    # A provenance assertion is not evidence of truth; server authorization is
    # independent of it. Only the opted-in client's accidental-upload gate uses it.
    provenance = bathroom(actor)
    provenance["payload"]["provenance"] = "demo"
    check(
        submit(provenance, token)["status"] == "acknowledged",
        "provenance does not establish authenticity",
    )
    pending_visit = str(uuid.uuid4())
    unavailable = command(
        "visit",
        pending_visit,
        "createVisit",
        dict(
            id=pending_visit,
            bathroom=c["entityId"],
            user=actor,
            at=1800000000000000,
            provenance="user_created",
        ),
    )
    submit(unavailable, token, 403)
    # A failed second half must roll back the visit AND its change/revision/receipt.
    compound_visit, compound_review = str(uuid.uuid4()), str(uuid.uuid4())
    bad = command(
        "review",
        compound_review,
        "createVisitReview",
        dict(
            visit=dict(id=compound_visit, bathroom=auth.ONE, user=actor, at=1800000000000001),
            review=dict(
                id=compound_review,
                visit=compound_visit,
                bathroom=auth.ONE,
                author=actor,
                created=1800000000000001,
                updated=1800000000000001,
                rating=9,
                paper=2,
                hygiene=4,
                comfort=0,
                aesthetics=1,
                tags="[]",
                comment=None,
            ),
        ),
    )
    submit(bad, token, 400)
    check(
        poc.sql("select count(*) from public.visits where id='" + compound_visit + "'") == "0",
        "compound visit rollback",
    )
    check(
        poc.sql(
            "select count(*) from app_private.sync_records where entity_id in ('"
            + compound_visit
            + "','"
            + compound_review
            + "')"
        )
        == "0",
        "compound revision rollback",
    )
    check(
        poc.sql(
            "select count(*) from app_private.sync_changes where entity_id in ('"
            + compound_visit
            + "','"
            + compound_review
            + "')"
        )
        == "0",
        "compound feed rollback",
    )
    check(
        poc.sql(
            "select count(*) from app_private.sync_receipts where operation_id='"
            + bad["operationId"]
            + "'"
        )
        == "0",
        "compound receipt rollback",
    )
    # Preserve the exact existing Unicode constraints, with an explicit future
    # integration gate rather than silently changing local grapheme validation.
    for content in ("e\u0301" * 251,):
        bad["operationId"] = str(uuid.uuid4())
        bad["payload"]["review"]["rating"] = 4
        bad["payload"]["review"]["comment"] = content
        submit(bad, token, 400)
    private_a, cursor = pages(token)
    private_b, _ = pages(other)
    public, public_cursor = pages(feed="catalogue")
    check(any(x["entityId"] == c["entityId"] for x in private_a), "own proposal feed")
    check(
        not any(x["entityId"] == c["entityId"] for x in private_b + public),
        "cross-account/public proposal exclusion",
    )
    # Removing a never-public proposal must not publish even its identifier.
    removed = bathroom(actor)
    submit(removed, token)
    status, _ = poc.request(
        poc.REST_PORT, "/bathrooms?id=eq." + removed["entityId"], "DELETE", token=token
    )
    check(status == 200, "own pending proposal deletion")
    withdrawals, _ = pages(feed="catalogue", cursor=public_cursor)
    check(
        not any(x["entityId"] == removed["entityId"] for x in withdrawals),
        "never-public proposal deletion remains private",
    )
    rpc("sync_pull", dict(feed="private", checkpoint=cursor), other, 400)
    rpc("sync_pull", dict(feed="catalogue", checkpoint=cursor), expected=400)
    rpc("sync_pull", dict(feed="private", page_size=101), token, 400)
    poc.sql(
        "update app_private.sync_cursors set expires_at=now()-interval '1 second' where id='"
        + cursor
        + "'"
    )
    reset = pull(token, cursor, size=1)
    check(reset["reset"] and len(reset["changes"]) == 1, "expired cursor bounded full replay")
    # Visibility removal/republication and public projections are independently logged.
    poc.sql(
        "update public.bathrooms set publication_status='rejected',approved_by=null,approved_at=null where id='"
        + auth.TWO
        + "'"
    )
    hidden, public_cursor = pages(feed="catalogue", cursor=public_cursor)
    check(
        any(
            x["entityId"] == auth.TWO and x["deleted"] and x["payload"].get("_visibility") is False
            for x in hidden
        ),
        "visibility withdrawal",
    )
    poc.sql(
        "update public.bathrooms set publication_status='approved',approved_by='"
        + actor
        + "',approved_at=now() where id='"
        + auth.TWO
        + "'"
    )
    restored, _ = pages(feed="catalogue", cursor=public_cursor)
    check(
        any(x["entityId"] == auth.TWO and not x["deleted"] for x in restored), "visibility return"
    )
    for change in public:
        payload = change["payload"]
        check(
            not any(
                k in payload
                for k in ("visit_id", "visited_at", "owner_id", "email", "created_at", "updated_at")
            ),
            "public allowlist has no private fields",
        )
        check(change["entityType"] in ("bathroom", "review"), "public entity types")
    overlap_test(actor, token)
    print("PASS: " + str(COUNT) + " real server protocol assertions")


def overlap_test(actor, token):
    # A allocates a candidate sequence/transaction ID before B, but delays writing.
    # B's later candidate commits first. Neither candidate is a feed watermark.
    poc.sql("create sequence if not exists app_private.sync_test_candidates")
    _, cursor = pages(token)
    first, second = str(uuid.uuid4()), str(uuid.uuid4())
    args = [
        "podman",
        "exec",
        "-i",
        poc.PROJECT + "-db",
        "psql",
        "-X",
        "-qAt",
        "-U",
        "supabase_admin",
        "-d",
        "postgres",
        "-v",
        "ON_ERROR_STOP=1",
    ]
    with tempfile.TemporaryFile(mode="w+") as output:
        delayed = subprocess.Popen(
            args, stdin=subprocess.PIPE, stdout=output, stderr=subprocess.DEVNULL, text=True
        )
        delayed.stdin.write(
            "begin; select nextval('app_private.sync_test_candidates'); select pg_current_xact_id();\n"
        )
        delayed.stdin.flush()
        for _ in range(100):
            output.seek(0)
            candidate_lines = output.read().splitlines()
            if len(candidate_lines) >= 2:
                break
            time.sleep(0.02)
        else:
            raise RuntimeError("Delayed transaction readiness failed")
        later_candidate = poc.sql(
            "begin; select nextval('app_private.sync_test_candidates'); insert into public.bathrooms(id,name,contributor_id) values('"
            + second
            + "','Later candidate commits first','"
            + actor
            + "'); commit;"
        )
        check(
            int(candidate_lines[0]) < int(later_candidate),
            "candidate allocations actually overlap in reverse commit order",
        )
        one = pull(token, cursor, size=1)
        check(
            [x["entityId"] for x in one["changes"]] == [second],
            "later candidate commit paginated first",
        )
        delayed.stdin.write(
            "insert into public.bathrooms(id,name,contributor_id) values('"
            + first
            + "','Earlier candidate commits last','"
            + actor
            + "'); commit;\n"
        )
        delayed.stdin.close()
        check(delayed.wait(timeout=15) == 0, "delayed transaction commits")
    two = pull(token, one["checkpoint"], size=1)
    check([x["entityId"] for x in two["changes"]] == [first], "earlier candidate never skipped")
    check(
        two["changes"][0]["revision"] > one["changes"][0]["revision"],
        "watermark allocated in committed order",
    )
    # Once a change watermark is allocated, later writers must wait for commit.
    with tempfile.TemporaryFile(mode="w+") as output:
        holder = subprocess.Popen(
            args, stdin=subprocess.PIPE, stdout=output, stderr=subprocess.DEVNULL, text=True
        )
        holder.stdin.write("begin; select app_private.sync_revision();\n")
        holder.stdin.flush()
        for _ in range(100):
            output.seek(0)
            if output.read().strip():
                break
            time.sleep(0.02)
        else:
            raise RuntimeError("Writer lock readiness failed")
        with concurrent.futures.ThreadPoolExecutor(1) as pool:
            future = pool.submit(submit, bathroom(actor), token)
            for _ in range(100):
                if (
                    poc.sql(
                        "select count(*) from pg_stat_activity where wait_event_type='Lock' and query like '%sync_submit%'"
                    )
                    != "0"
                ):
                    break
                time.sleep(0.02)
            else:
                raise RuntimeError("Concurrent API writer did not reach the lock")
            check(not future.done(), "later watermark allocation blocked until commit")
            holder.stdin.write("rollback;\n")
            holder.stdin.close()
            check(holder.wait(timeout=15) == 0, "rollback releases watermark")
            check(future.result(timeout=15)["status"] == "acknowledged", "waiting writer completes")


def expired_token(actor):
    # Deliberately expired JWT with the dedicated installation's signing key.
    key = json.loads((poc.STATE / "secrets.json").read_text())["JWT_SECRET"]

    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=")

    message = (
        encode({"alg": "HS256", "typ": "JWT"})
        + b"."
        + encode(
            dict(sub=actor, role="authenticated", aud="authenticated", exp=int(time.time()) - 3600)
        )
    )
    return (
        message
        + b"."
        + base64.urlsafe_b64encode(hmac.new(key.encode(), message, hashlib.sha256).digest()).rstrip(
            b"="
        )
    ).decode()


def verification():
    if "--skip-authorization" not in sys.argv:
        auth.verify()
    accounts = json.loads((poc.STATE / "accounts.json").read_text())
    a, b = [auth.login(account) for account in accounts]
    server_tests(a, b)
    # Fresh Auth tokens before the real Flutter transport suite. Never print them.
    a, b = [auth.login(account) for account in accounts]
    catalogue = str(uuid.uuid4())
    poc.sql(
        "insert into public.bathrooms(id,name,contributor_id,publication_status,approved_by,approved_at) values('"
        + catalogue
        + "','Catálogo fictício exclusivo do transporte','"
        + a["user"]["id"]
        + "','approved','"
        + b["user"]["id"]
        + "',now())"
    )
    config = dict(
        catalogue=catalogue,
        endpoint=f"http://127.0.0.1:{poc.REST_PORT}/",
        environment="isolated-local-sync-v1",
        a=a,
        b=b,
        expired=expired_token(a["user"]["id"]),
    )
    fd, path = tempfile.mkstemp(prefix="sync-client-", suffix=".json", dir=poc.STATE)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(config, stream)
        environment = dict(os.environ, BATH_SYNC_TEST_CONFIG=path)
        with tempfile.TemporaryFile(mode="w+") as output:
            result = subprocess.run(
                ["flutter", "test", "test/real_sync_test.dart", "--reporter", "expanded"],
                cwd=poc.ROOT,
                env=environment,
                stdout=output,
                stderr=subprocess.STDOUT,
                check=False,
            )
            output.seek(0)
            # Test output must contain no HTTP response/token dumps.
            report = output.read()
            for session in (a, b):
                for key in ("access_token", "refresh_token"):
                    report = report.replace(session[key], "[redacted]")
            report = report.replace(config["expired"], "[redacted]")
            print(report)
        check(result.returncode == 0, "real Flutter client integration suite")
    finally:
        os.unlink(path)


def main():
    poc.start()
    try:
        verification()
    finally:
        poc.compose("stop")
        print("Stopped dedicated sync installation; credentials, volumes and network retained")


if __name__ == "__main__":
    os.umask(0o077)
    sys.stdout.reconfigure(line_buffering=True)
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        print(
            str(error) if isinstance(error, RuntimeError) else "Local synchronization test failed",
            file=sys.stderr,
        )
        sys.exit(1)
