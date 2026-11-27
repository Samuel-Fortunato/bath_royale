"""Build only an owner-approved, public-configuration alpha; never publishes."""

import argparse
import base64
import json
import os
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path
from urllib.parse import urlsplit


def configuration(url, key):
    parsed = urlsplit(url)
    if (
        parsed.scheme != "https"
        or not re.fullmatch(r"[a-z]{20}\.supabase\.co", parsed.hostname or "")
        or parsed.path not in ("", "/")
        or parsed.username
        or parsed.port
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("Ordinary managed Supabase HTTPS origin required")
    if not re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]+", key):
        try:
            payload = key.split(".")[1]
            claims = json.loads(
                base64.urlsafe_b64decode(payload + "=" * ((-len(payload)) % 4))
            )
            if claims.get("role") != "anon":
                raise ValueError("Privileged key")
        except (ValueError, IndexError, KeyError):
            raise ValueError("Public anon or publishable key required") from None
    return {
        "SUPABASE_URL": url.rstrip("/"),
        "SUPABASE_PUBLISHABLE_KEY": key,
        "BATH_PUBLIC_ALPHA": True,
        "BATH_ALPHA_FEEDBACK": True,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--number", type=int, required=True)
    args = parser.parse_args()
    if os.environ.get("ALPHA_RELEASE_APPROVED") != "true" or args.number < 1001:
        parser.error("Explicit release approval and increasing release code required")
    config = configuration(
        os.environ["SUPABASE_URL"], os.environ["SUPABASE_PUBLISHABLE_KEY"]
    )
    config["BATH_APP_VERSION"] = f"0.1.0-alpha.{args.number}"
    with tempfile.TemporaryDirectory(prefix="bath-alpha-public-") as directory:
        path = Path(directory) / "defines.json"
        path.write_text(json.dumps(config))
        subprocess.run(
            [
                "flutter",
                "build",
                "apk",
                "--release",
                "--no-pub",
                "--target",
                "lib/main.dart",
                f"--dart-define-from-file={path}",
                "--build-number",
                str(args.number),
                "--build-name",
                config["BATH_APP_VERSION"],
            ],
            check=True,
        )
    with zipfile.ZipFile("build/app/outputs/flutter-apk/app-release.apk") as archive:
        for name in archive.namelist():
            if name.endswith(("/libapp.so", ".json", ".dart")):
                data = archive.read(name)
                for value in [
                    "local-development-client",
                    "local-device-client",
                    "Contas de teste",
                    "rei@example.com",
                    "duque@example.com",
                    "BEGIN CERTIFICATE",
                    "Exemplo fictício",
                ]:
                    if value.encode() in data or value.encode("utf-16-le") in data:
                        raise RuntimeError(
                            "Local-development material found in distributable APK"
                        )


if __name__ == "__main__":
    main()
