"""Fail closed on preview signing, identity and release payload mismatches."""

import contextlib
import os
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

CERTIFICATE = "4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc"
ARCHITECTURES = {"armeabi-v7a", "arm64-v8a", "x86_64"}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def private_file(path):
    path = Path(path).absolute()
    require(
        not any(p.is_symlink() for p in (path, *path.parents)),
        "Não são permitidas ligações simbólicas.",
    )
    require(path.is_file(), "É necessário um ficheiro privado existente.")
    info = path.stat()
    require(
        info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o600,
        "O ficheiro privado exige o proprietário atual e modo 0600.",
    )
    return path


def verify_key(path, password_file=None):
    path = private_file(path)
    # Existing public debug-password compatibility remains the default. Never put
    # even that password in argv; explicit migrated password files are short lived.
    with contextlib.ExitStack() as stack:
        if password_file is None:
            directory = stack.enter_context(
                tempfile.TemporaryDirectory(prefix="preview-key-")
            )
            password_file = Path(directory) / "password"
            descriptor = os.open(
                password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600
            )
            with os.fdopen(descriptor, "w") as stream:
                stream.write("android")
        password_file = private_file(password_file)
        certificate = subprocess.check_output(
            [
                "keytool",
                "-exportcert",
                "-keystore",
                str(path),
                "-alias",
                "androiddebugkey",
                "-storepass:file",
                str(password_file),
            ],
            stderr=subprocess.PIPE,
        )
    import hashlib

    require(
        hashlib.sha256(certificate).hexdigest() == CERTIFICATE,
        "Incompatible preview certificate",
    )


def verify_badging(badging, number, name):
    require(
        badging.startswith(
            f"package: name='com.example.bath_royale' versionCode='{number}' "
            f"versionName='{name}' "
        ),
        "Package/version mismatch",
    )
    require("application-debuggable" not in badging, "Debuggable APK")
    lines = [line for line in badging.splitlines() if line.startswith("native-code:")]
    require(
        len(lines) == 1
        and set(lines[0].split()[1:]) == {f"'{a}'" for a in ARCHITECTURES},
        "Unexpected native architectures",
    )


def verify_apk(path, number, name):
    tools = Path(os.environ["ANDROID_HOME"]) / "build-tools/36.0.0"
    signing = subprocess.check_output(
        [str(tools / "apksigner"), "verify", "--print-certs", path], text=True
    )
    digests = [
        line for line in signing.splitlines() if "certificate SHA-256 digest:" in line
    ]
    require(
        digests == [f"Signer #1 certificate SHA-256 digest: {CERTIFICATE}"],
        "Incompatible APK certificate",
    )
    badging = subprocess.check_output(
        [str(tools / "aapt"), "dump", "badging", path], text=True
    )
    verify_badging(badging, number, name)
    with zipfile.ZipFile(path) as apk:
        names = set(apk.namelist())
        for architecture in ARCHITECTURES:
            require(f"lib/{architecture}/libapp.so" in names, "Missing AOT code")
            require(f"lib/{architecture}/libflutter.so" in names, "Missing engine")
        require(
            "assets/flutter_assets/kernel_blob.bin" not in names,
            "Debug kernel in release APK",
        )
    print(
        f"Verified universal AOT release: {number} / {name}; {Path(path).stat().st_size} bytes"
    )


if __name__ == "__main__":
    if sys.argv[1] == "key":
        import argparse

        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("keystore")
        parser.add_argument(
            "--password-file",
            type=Path,
            help="Ficheiro temporário 0600 com a palavra-passe; nunca passar o valor como argumento.",
        )
        args = parser.parse_args(sys.argv[2:])
        verify_key(args.keystore, args.password_file)
    elif sys.argv[1] == "apk":
        verify_apk(*sys.argv[2:])
    else:
        raise RuntimeError("Unknown verification mode")
