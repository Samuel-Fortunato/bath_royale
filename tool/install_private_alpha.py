"""Build, verify, update and launch the USB-only private alpha. Never clears data."""

from app_version import metadata

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = "com.example.bath_royale"


def run(*args, capture=False):
    return subprocess.run(
        args,
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    ).stdout


def validate_configuration(config, development):
    endpoint = "https://localhost:55504" if development else "https://localhost:55474"
    key = "local-development-client" if development else "local-device-client"
    if (
        config.get("SUPABASE_URL") != endpoint
        or config.get("SUPABASE_PUBLISHABLE_KEY") != key
    ):
        raise ValueError("Wrong isolated endpoint for selected target")
    if development:
        if config.get("BATH_ISOLATED_DEVELOPMENT") is not True or not config.get(
            "BATH_LOCAL_TEST_ACCOUNTS"
        ):
            raise ValueError("Development fixtures configuration required")
    elif any(
        k.startswith("BATH_LOCAL_") or k == "BATH_ISOLATED_DEVELOPMENT" for k in config
    ):
        raise ValueError("Development configuration forbidden in alpha target")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config-dir",
        required=True,
        type=Path,
        help="Existing private TLS directory containing defines.json",
    )
    parser.add_argument(
        "--development",
        action="store_true",
        help="Install only the isolated fictional development target",
    )
    parser.add_argument("--keystore", default=os.environ.get("PREVIEW_KEYSTORE"))
    args = parser.parse_args()
    if not args.keystore or not Path(args.keystore).is_file():
        parser.error(
            "Supply the original signing key with --keystore or PREVIEW_KEYSTORE"
        )
    defines = args.config_dir.resolve() / (
        "development-defines.json" if args.development else "defines.json"
    )
    if not defines.is_file():
        parser.error("Existing local TLS defines.json required; see device runbook")
    try:
        validate_configuration(json.loads(defines.read_text()), args.development)
    except (ValueError, TypeError):
        parser.error("Configuration does not match the selected isolated target")
    for command in ("adb", "flutter"):
        if not shutil.which(command):
            parser.error(
                f"{command} missing; run inside the project direnv/Nix environment"
            )
    global PACKAGE
    PACKAGE = metadata("development", 1)["package"]
    os.environ["BATH_BUILD_CHANNEL"] = "development"
    # get-serialno fails for missing, unauthorized or ambiguous devices.
    run("adb", "get-serialno", capture=True)
    info = run("adb", "shell", "dumpsys", "package", PACKAGE, capture=True)
    match = re.search(r"versionCode=(\d+)", info)
    if not match:
        parser.error("Existing installation required; refusing a fresh installation")
    code = "1"
    if not args.development:
        parser.error(
            "Use managed_release.py install for managed updates; isolated configuration cannot overwrite it"
        )
    name = metadata("development", 1)["version_name"]
    run(sys.executable, "tool/verify_preview.py", "key", args.keystore)
    paths = run("adb", "shell", "pm", "path", PACKAGE, capture=True)
    base = next(
        (
            p.removeprefix("package:").strip()
            for p in paths.splitlines()
            if p.strip().endswith("/base.apk")
        ),
        None,
    )
    if not base:
        parser.error("Cannot inspect installed APK")
    sdk = Path(os.environ["ANDROID_HOME"])
    apksigner = str(sorted((sdk / "build-tools").glob("*/apksigner"))[-1])
    with tempfile.TemporaryDirectory(prefix="bath-alpha-install-") as directory:
        installed = str(Path(directory) / "installed.apk")
        run("adb", "pull", base, installed, capture=True)
        certificates = run(
            apksigner, "verify", "--print-certs", installed, capture=True
        )
        from verify_preview import CERTIFICATE

        if CERTIFICATE not in certificates.lower().replace(":", ""):
            parser.error("Installed signing identity mismatch; no update performed")
    os.environ["PREVIEW_KEYSTORE"] = str(Path(args.keystore).resolve())
    run("flutter", "pub", "get", "--enforce-lockfile")
    run(
        "flutter",
        "build",
        "apk",
        "--release",
        "--no-pub",
        "--target",
        (
            "tool/local_development.dart"
            if args.development
            else "tool/auth_device_preview.dart"
        ),
        f"--dart-define-from-file={defines}",
        "--dart-define=BATH_ALPHA_FEEDBACK=true",
        f"--dart-define=BATH_APP_VERSION={name}",
        "--build-number",
        code,
        "--build-name",
        name,
    )
    apk = "build/app/outputs/flutter-apk/app-release.apk"
    run(sys.executable, "tool/verify_preview.py", "apk", apk, code, name, PACKAGE)
    run("adb", "install", "-r", apk)
    port = "55504" if args.development else "55474"
    run("adb", "reverse", "tcp:" + port, "tcp:" + port)
    run(
        "adb",
        "shell",
        "am",
        "start",
        "-n",
        f"{PACKAGE}/com.example.bath_royale.MainActivity",
    )


if __name__ == "__main__":
    main()
