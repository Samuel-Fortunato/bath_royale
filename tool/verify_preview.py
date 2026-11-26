"""Fail closed on preview signing, identity and release payload mismatches."""
import os
from pathlib import Path
import subprocess
import sys
import zipfile

CERTIFICATE = '4f5c38685c8304dca2708d9627e0287a82f3058c4c2293c42bb980d05bea37fc'
ARCHITECTURES = {'armeabi-v7a', 'arm64-v8a', 'x86_64'}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify_key(path):
    require(Path(path).is_file(), 'Existing preview key required')
    certificate = subprocess.check_output([
        'keytool', '-exportcert', '-keystore', path, '-alias',
        'androiddebugkey', '-storepass', 'android', '-keypass', 'android',
    ])
    import hashlib
    require(hashlib.sha256(certificate).hexdigest() == CERTIFICATE,
            'Incompatible preview certificate')


def verify_badging(badging, number, name):
    require(badging.startswith(
        f"package: name='com.example.bath_royale' versionCode='{number}' "
        f"versionName='{name}' "), 'Package/version mismatch')
    require('application-debuggable' not in badging, 'Debuggable APK')
    lines = [line for line in badging.splitlines() if line.startswith('native-code:')]
    require(len(lines) == 1 and
            set(lines[0].split()[1:]) == {f"'{a}'" for a in ARCHITECTURES},
            'Unexpected native architectures')


def verify_apk(path, number, name):
    tools = Path(os.environ['ANDROID_HOME']) / 'build-tools/36.0.0'
    signing = subprocess.check_output([
        str(tools / 'apksigner'), 'verify', '--print-certs', path], text=True)
    digests = [line for line in signing.splitlines()
               if 'certificate SHA-256 digest:' in line]
    require(digests == [f'Signer #1 certificate SHA-256 digest: {CERTIFICATE}'],
            'Incompatible APK certificate')
    badging = subprocess.check_output([
        str(tools / 'aapt'), 'dump', 'badging', path], text=True)
    verify_badging(badging, number, name)
    with zipfile.ZipFile(path) as apk:
        names = set(apk.namelist())
        for architecture in ARCHITECTURES:
            require(f'lib/{architecture}/libapp.so' in names, 'Missing AOT code')
            require(f'lib/{architecture}/libflutter.so' in names, 'Missing engine')
        require('assets/flutter_assets/kernel_blob.bin' not in names,
                'Debug kernel in release APK')
    print(f'Verified universal AOT release: {number} / {name}; {Path(path).stat().st_size} bytes')


if __name__ == '__main__':
    if sys.argv[1] == 'key':
        verify_key(sys.argv[2])
    elif sys.argv[1] == 'apk':
        verify_apk(*sys.argv[2:])
    else:
        raise RuntimeError('Unknown verification mode')
