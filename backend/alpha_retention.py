"""Plan operator-only feedback retention from privately recorded review dates.

Never connects to a database. The journal contains UUIDs/dates, not feedback text.
"""

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

import cloud_transfer


def plan(records, apply=False):
    if not isinstance(records, list):
        raise ValueError("Expected a review-date list")
    rows, seen = [], set()
    for record in records:
        if not isinstance(record, dict) or set(record) != {"id", "reviewed_at"}:
            raise ValueError("Expected only id and reviewed_at")
        identifier = str(UUID(record["id"]))
        reviewed = datetime.fromisoformat(record["reviewed_at"])
        if reviewed.tzinfo is None or reviewed > datetime.now(timezone.utc):
            raise ValueError("Past, timezone-aware review date required")
        if identifier in seen:
            raise ValueError("Duplicate feedback ID")
        seen.add(identifier)
        rows.append(f"('{identifier}'::uuid,'{reviewed.isoformat()}'::timestamptz)")
    values = ",\n".join(rows) if rows else "(NULL::uuid,NULL::timestamptz)"
    eligible = (
        "f.id=r.id AND f.status IN ('reviewed','resolved') "
        "AND r.reviewed_at <= statement_timestamp()-interval '90 days' "
        "AND f.submitted_at <= r.reviewed_at"
    )
    query = (
        f"DELETE FROM app_private.alpha_feedback f USING reviewed r WHERE {eligible} RETURNING f.id"
        if apply
        else f"SELECT count(*) AS eligible_feedback FROM app_private.alpha_feedback f "
        f"JOIN reviewed r ON {eligible}"
    )
    return (
        "\\set ON_ERROR_STOP on\nBEGIN;\n"
        "SELECT pg_advisory_xact_lock(74042012);\n"
        f"WITH reviewed(id,reviewed_at) AS (VALUES\n{values}\n)\n{query};\n"
        + ("COMMIT;\n" if apply else "ROLLBACK;\n")
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    cloud_transfer.outside_checkout(args.journal)
    cloud_transfer.private_path(args.journal)
    cloud_transfer.outside_checkout(args.output)
    cloud_transfer.private_path(args.output.parent, directory=True)
    sql = plan(json.loads(args.journal.read_text()), args.apply)
    cloud_transfer.poc.secure_write(args.output, sql)
    print("Retention SQL written; no database contacted. Review before execution.")


if __name__ == "__main__":
    main()
