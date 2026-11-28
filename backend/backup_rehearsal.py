"""Complete Auth backup fixture; only freshly created no-network resources.

Use the same database fixture and native pinned dump executable as the approved
transfer tooling. Auth initializes over the source container's isolated loopback;
no host port is published. All credentials are independently disposable.
"""

import contextlib
import json
import secrets
import tempfile
import time
from pathlib import Path

import administration_rehearsal as fixture
import poc


@contextlib.contextmanager
def disposable():
    with fixture.disposable(backup_tooling=True) as (db, container):
        auth = container.removesuffix("-db") + "-auth"
        created = None
        with tempfile.TemporaryDirectory(prefix="broyale-backup-auth-") as name:
            root = Path(name)
            password = secrets.token_hex(32)
            db.sql("ALTER USER supabase_auth_admin PASSWORD '" + password + "';")
            env = {
                "GOTRUE_API_HOST": "127.0.0.1",
                "GOTRUE_API_PORT": "9999",
                "API_EXTERNAL_URL": "http://127.0.0.1:9999",
                "GOTRUE_SITE_URL": "http://127.0.0.1:9999",
                "GOTRUE_DB_DRIVER": "postgres",
                "GOTRUE_DB_DATABASE_URL": "postgres://supabase_auth_admin:"
                + password
                + "@127.0.0.1:5432/postgres",
                "GOTRUE_JWT_SECRET": secrets.token_hex(32),
                "GOTRUE_JWT_AUD": "authenticated",
                "GOTRUE_JWT_EXP": "60",
                "GOTRUE_EXTERNAL_EMAIL_ENABLED": "true",
                "GOTRUE_EXTERNAL_PHONE_ENABLED": "false",
                "GOTRUE_LOG_LEVEL": "error",
            }
            path = root / "auth.env"
            poc.secure_write(path, "\n".join(k + "=" + v for k, v in env.items()) + "\n")
            try:
                created = fixture.run(
                    [
                        "podman",
                        "run",
                        "-d",
                        "--name",
                        auth,
                        "--network",
                        "container:" + container,
                        "--env-file",
                        str(path),
                        "docker.io/supabase/gotrue@sha256:5e9ee59d7406d21412b35e6b524a1f2004ff518a0b49fa3cc08dee75811af09d",
                    ]
                )
                deadline = time.monotonic() + 120
                while True:
                    # The final schema migration creates OAuth tables. Readiness
                    # also requires no active Auth migration transaction.
                    exists = db.sql("SELECT to_regclass('auth.oauth_client_states') IS NOT NULL;")
                    running = fixture.run(
                        ["podman", "inspect", "--format", "{{.State.Running}}", auth]
                    )
                    fixture.check(running == "true", "Auth initializer running")
                    if exists == "t":
                        # Full migration count stabilizes before Auth serves.
                        active = db.sql(
                            "SELECT count(*) FROM pg_stat_activity WHERE usename='supabase_auth_admin' AND state='active';"
                        )
                        if active == "0":
                            break
                    fixture.check(time.monotonic() < deadline, "Auth initialization readiness")
                    time.sleep(1)
                fixture.run(["podman", "stop", auth])
                tables = [
                    "auth.users",
                    "auth.identities",
                    "auth.sessions",
                    "auth.refresh_tokens",
                    "auth.mfa_amr_claims",
                ]
                fixture.check(
                    len(
                        json.loads(
                            db.sql(
                                "SELECT json_agg(x) FROM (SELECT to_regclass(t) name FROM unnest(ARRAY["
                                + ",".join("'" + t + "'" for t in tables)
                                + "]) t) x;"
                            )
                        )
                    )
                    == len(tables),
                    "complete Auth scope",
                )
                yield db, container
            finally:
                if created:
                    fixture.run(["podman", "rm", "-f", "-v", created])
