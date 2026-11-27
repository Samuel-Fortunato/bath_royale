"""Emit a reviewed, non-destructive psql migration plan. Never connects anywhere."""

import argparse
import hashlib
from pathlib import Path


def plan(root):
    output = [
        "\\set ON_ERROR_STOP on\nBEGIN;\nSELECT pg_advisory_xact_lock(740451);\nCREATE SCHEMA IF NOT EXISTS bath_royale_migrations;\nCREATE TABLE IF NOT EXISTS bath_royale_migrations.applied(name text primary key,sha256 text not null);\nREVOKE ALL ON SCHEMA bath_royale_migrations FROM public,anon,authenticated;\n"
    ]
    for path in sorted(root.glob("*.sql")):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        output.append(
            f"DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM bath_royale_migrations.applied WHERE name='{path.name}' AND sha256<>'{digest}') THEN RAISE EXCEPTION 'Applied migration checksum differs'; END IF; END $guard$;\n"
        )
        body = (
            path.read_text()
            + f"\nINSERT INTO bath_royale_migrations.applied VALUES('{path.name}','{digest}');"
        )
        output.append(
            f"SELECT $migration_{digest}${body}$migration_{digest}$ WHERE NOT EXISTS(SELECT 1 FROM bath_royale_migrations.applied WHERE name='{path.name}')\\gexec\n"
        )
    return "".join(output) + "NOTIFY pgrst, 'reload schema';\nCOMMIT;\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with args.output.open("x") as stream:
        stream.write(plan(Path(__file__).resolve().parent.parent / "supabase/migrations"))
    print(
        "Ordered plan written; no database accessed. Review and approval required before execution."
    )
