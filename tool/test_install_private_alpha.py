"""Verify update-only installation and fail-closed certificate checks."""
import os
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
            (root / 'defines.json').write_text('{}')
            (root / 'key').touch()
            sdk = root / 'build-tools/36.0.0'
            sdk.mkdir(parents=True)
            (sdk / 'apksigner').touch()

            def run(*args, **kwargs):
                calls.append(args)
                if args[1:3] == ('shell', 'dumpsys'):
                    return 'versionCode=1023'
                if args[1:4] == ('shell', 'pm', 'path'):
                    return 'package:/data/app/base.apk'
                if 'verify' in args:
                    return 'Signer #1 certificate SHA-256 digest: ' + certificate
                return ''

            with patch.dict(os.environ, {'ANDROID_HOME': directory}), patch.object(installer, 'run', run), patch.object(installer.shutil, 'which', return_value='/bin/tool'), patch('sys.argv', ['install', '--config-dir', directory, '--keystore', str(root / 'key')]):
                if certificate == CERTIFICATE:
                    installer.main()
                else:
                    with self.assertRaises(SystemExit):
                        installer.main()
        return calls

    def test_update_restores_forwarding_and_launches_without_data_removal(self):
        calls = self.exercise(CERTIFICATE)
        self.assertTrue(any(c[1:3] == ('install', '-r') for c in calls))
        self.assertIn(('adb', 'reverse', 'tcp:55474', 'tcp:55474'), calls)
        self.assertTrue(any('start' in c for c in calls))
        self.assertFalse(any('uninstall' in c or 'clear' in c for c in calls))

    def test_mismatched_certificate_stops_before_build_or_install(self):
        calls = self.exercise('wrong')
        self.assertFalse(any('build' in c or 'install' in c for c in calls))
