"""Regression checks for fail-closed preview validation."""
import tempfile
import unittest
import zipfile
from unittest.mock import patch

import verify_preview as verifier


class PreviewTest(unittest.TestCase):
    def test_identity_and_release_flags(self):
        good = ("package: name='com.example.bath_royale' versionCode='1024' "
                "versionName='0.1.0-preview.24' platformBuildVersionName='x'\n"
                "native-code: 'armeabi-v7a' 'arm64-v8a' 'x86_64'\n")
        verifier.verify_badging(good, '1024', '0.1.0-preview.24')
        for bad in (good + 'application-debuggable\n',
                    good.replace('1024', '1'),
                    good.replace('com.example', 'org.example'),
                    good.replace("'x86_64'", ''),
                    good.replace('preview.24', 'preview.23')):
            with self.assertRaises(RuntimeError):
                verifier.verify_badging(bad, '1024', '0.1.0-preview.24')

    def test_aot_and_certificate(self):
        badging = ("package: name='com.example.bath_royale' versionCode='1024' "
                   "versionName='0.1.0-preview.24' platformBuildVersionName='x'\n"
                   "native-code: 'armeabi-v7a' 'arm64-v8a' 'x86_64'\n")
        signing = f'Signer #1 certificate SHA-256 digest: {verifier.CERTIFICATE}\n'
        for variant in ('release', 'wrong-signer', 'missing-aot', 'debug-kernel'):
            with self.subTest(variant=variant), tempfile.NamedTemporaryFile() as apk:
                with zipfile.ZipFile(apk.name, 'w') as archive:
                    for abi in verifier.ARCHITECTURES:
                        archive.writestr(f'lib/{abi}/libflutter.so', b'engine')
                        if variant != 'missing-aot':
                            archive.writestr(f'lib/{abi}/libapp.so', b'aot')
                    if variant == 'debug-kernel':
                        archive.writestr('assets/flutter_assets/kernel_blob.bin', b'kernel')
                with patch.dict(verifier.os.environ, ANDROID_HOME='/sdk'), patch.object(
                        verifier.subprocess, 'check_output',
                        side_effect=[signing if variant != 'wrong-signer' else 'wrong',
                                     badging]):
                    if variant == 'release':
                        verifier.verify_apk(apk.name, '1024', '0.1.0-preview.24')
                    else:
                        with self.assertRaises(RuntimeError):
                            verifier.verify_apk(apk.name, '1024', '0.1.0-preview.24')

    def test_missing_or_incompatible_key(self):
        with tempfile.NamedTemporaryFile() as key:
            with patch.object(verifier.subprocess, 'check_output', return_value=b'wrong'):
                with self.assertRaises(RuntimeError):
                    verifier.verify_key(key.name)
        with self.assertRaises(RuntimeError):
            verifier.verify_key(key.name)


if __name__ == '__main__':
    unittest.main()
