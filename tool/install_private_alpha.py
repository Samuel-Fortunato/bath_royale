"""Build, verify, update and launch the USB-only private alpha. Never clears data."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = 'com.example.bath_royale'


def run(*args, capture=False):
    return subprocess.run(args, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config-dir', required=True, type=Path,
                        help='Existing private TLS directory containing defines.json')
    parser.add_argument('--keystore', default=os.environ.get('PREVIEW_KEYSTORE'))
    args = parser.parse_args()
    if not args.keystore or not Path(args.keystore).is_file():
        parser.error('Supply the original signing key with --keystore or PREVIEW_KEYSTORE')
    defines = args.config_dir.resolve() / 'defines.json'
    if not defines.is_file():
        parser.error('Existing local TLS defines.json required; see device runbook')
    for command in ('adb', 'flutter'):
        if not shutil.which(command):
            parser.error(f'{command} missing; run inside the project direnv/Nix environment')
    # get-serialno fails for missing, unauthorized or ambiguous devices.
    run('adb', 'get-serialno', capture=True)
    info = run('adb', 'shell', 'dumpsys', 'package', PACKAGE, capture=True)
    match = re.search(r'versionCode=(\d+)', info)
    if not match:
        parser.error('Existing installation required; refusing a fresh installation')
    code = match[1]
    name = f'0.1.0-alpha-a11.{code}'
    run(sys.executable, 'tool/verify_preview.py', 'key', args.keystore)
    paths = run('adb', 'shell', 'pm', 'path', PACKAGE, capture=True)
    base = next((p.removeprefix('package:').strip() for p in paths.splitlines()
                 if p.strip().endswith('/base.apk')), None)
    if not base:
        parser.error('Cannot inspect installed APK')
    sdk = Path(os.environ['ANDROID_HOME'])
    apksigner = str(sorted((sdk / 'build-tools').glob('*/apksigner'))[-1])
    with tempfile.TemporaryDirectory(prefix='bath-alpha-install-') as directory:
        installed = str(Path(directory) / 'installed.apk')
        run('adb', 'pull', base, installed, capture=True)
        certificates = run(apksigner, 'verify', '--print-certs', installed, capture=True)
        from verify_preview import CERTIFICATE
        if CERTIFICATE not in certificates.lower().replace(':', ''):
            parser.error('Installed signing identity mismatch; no update performed')
    os.environ['PREVIEW_KEYSTORE'] = str(Path(args.keystore).resolve())
    run('flutter', 'pub', 'get', '--enforce-lockfile')
    run('flutter', 'build', 'apk', '--release', '--no-pub', '--target',
        'tool/auth_device_preview.dart', f'--dart-define-from-file={defines}',
        '--build-number', code, '--build-name', name)
    apk = 'build/app/outputs/flutter-apk/app-release.apk'
    run(sys.executable, 'tool/verify_preview.py', 'apk', apk, code, name)
    run('adb', 'install', '-r', apk)
    run('adb', 'reverse', 'tcp:55474', 'tcp:55474')
    run('adb', 'shell', 'am', 'start', '-n', f'{PACKAGE}/.MainActivity')


if __name__ == '__main__':
    main()
