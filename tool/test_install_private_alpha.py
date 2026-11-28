"""Verify update-only installation and fail-closed certificate checks."""

import os
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import install_private_alpha as installer
from verify_preview import CERTIFICATE


class InstallerTest(unittest.TestCase):
    def exercise(self, certificate):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "development-defines.json").write_text(
                json.dumps(
                    {
                        "SUPABASE_URL": "https://localhost:55504",
                        "SUPABASE_PUBLISHABLE_KEY": "local-development-client",
                        "BATH_ISOLATED_DEVELOPMENT": True,
                        "BATH_LOCAL_TEST_ACCOUNTS": "fictional",
                    }
                )
            )
            (root / "key").touch()
            sdk = root / "build-tools/36.0.0"
            sdk.mkdir(parents=True)
            (sdk / "apksigner").touch()

            def run(*args, **kwargs):
                calls.append(args)
                if args[1:3] == ("shell", "dumpsys"):
                    return "versionCode=1023"
                if args[1:4] == ("shell", "pm", "path"):
                    return "package:/data/app/base.apk"
                if "verify" in args:
                    return "Signer #1 certificate SHA-256 digest: " + certificate
                return ""

            with (
                patch.dict(os.environ, {"ANDROID_HOME": directory}),
                patch.object(installer, "run", run),
                patch.object(installer.shutil, "which", return_value="/bin/tool"),
                patch(
                    "sys.argv",
                    [
                        "install",
                        "--config-dir",
                        directory,
                        "--development",
                        "--keystore",
                        str(root / "key"),
                    ],
                ),
            ):
                if certificate == CERTIFICATE:
                    installer.main()
                else:
                    with self.assertRaises(SystemExit):
                        installer.main()
        return calls

    def test_update_restores_forwarding_and_launches_without_data_removal(self):
        calls = self.exercise(CERTIFICATE)
        self.assertTrue(any(c[1:3] == ("install", "-r") for c in calls))
        self.assertIn(("adb", "reverse", "tcp:55504", "tcp:55504"), calls)
        self.assertTrue(any("start" in c for c in calls))
        self.assertFalse(any("uninstall" in c or "clear" in c for c in calls))

    def test_mismatched_certificate_stops_before_build_or_install(self):
        calls = self.exercise("wrong")
        self.assertFalse(any("build" in c or "install" in c for c in calls))


class ConfigurationIsolationTest(unittest.TestCase):
    def test_alpha_rejects_development_or_managed_configuration(self):
        for config in [
            dict(
                SUPABASE_URL="https://managed.invalid",
                SUPABASE_PUBLISHABLE_KEY="public",
            ),
            dict(
                SUPABASE_URL="https://localhost:55504",
                SUPABASE_PUBLISHABLE_KEY="local-development-client",
            ),
            dict(
                SUPABASE_URL="https://localhost:55474",
                SUPABASE_PUBLISHABLE_KEY="local-device-client",
                BATH_ISOLATED_DEVELOPMENT=True,
            ),
        ]:
            with self.assertRaises(ValueError):
                installer.validate_configuration(config, False)

    def test_development_requires_explicit_fixture_data(self):
        config = dict(
            SUPABASE_URL="https://localhost:55504",
            SUPABASE_PUBLISHABLE_KEY="local-development-client",
        )
        with self.assertRaises(ValueError):
            installer.validate_configuration(config, True)
        config.update(
            BATH_ISOLATED_DEVELOPMENT=True, BATH_LOCAL_TEST_ACCOUNTS="fixture-marker"
        )
        installer.validate_configuration(config, True)
