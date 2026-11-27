"""Retired managed fixture writer; retained private-account validation for exports."""

import json
import os
import stat
import sys

import cloud


def managed():
    raise RuntimeError("Retired managed fixture workflow; use the non-destructive A5.1 runbook")


def validate_accounts(path):
    cloud.require(not path.is_symlink() and path.is_file(), "Missing regular accounts file")
    info = path.stat()
    cloud.require(
        info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o600,
        "Accounts file must be owner-only mode 0600",
    )
    accounts = json.loads(path.read_text())
    cloud.require(
        isinstance(accounts, list)
        and len(accounts) == 2
        and all(isinstance(a, dict) for a in accounts),
        "Expected two fictional accounts",
    )
    cloud.require(
        {a.get("email") for a in accounts}
        == {"bath-royale-fictional-a@example.invalid", "bath-royale-fictional-b@example.invalid"}
        and all(isinstance(a.get("password"), str) and a["password"] for a in accounts),
        "Unexpected fictional account credentials",
    )
    return accounts


def prepare(remote):
    raise RuntimeError("Managed fixture reset and authorization mutation workflows are retired")


if __name__ == "__main__":
    print(
        "Retired: no managed connection or mutation attempted. See the A5.1 runbook.",
        file=sys.stderr,
    )
    sys.exit(1)
