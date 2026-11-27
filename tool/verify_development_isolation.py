"""Verify real release payloads exclude private development fixture configuration."""
import argparse
import base64
import json
from pathlib import Path
import zipfile


def verify(apk, config, development=False):
    encoded=config['BATH_LOCAL_TEST_ACCOUNTS']
    accounts=json.loads(base64.b64decode(encoded))
    needles=[encoded,'Contas de teste',*[a['email'] for a in accounts]]
    with zipfile.ZipFile(apk) as archive:
        payloads=[archive.read(name) for name in archive.namelist() if name.endswith(('.so','.json','.dart'))]
    found=any(value.encode() in payload or value.encode('utf-16-le') in payload for value in needles for payload in payloads)
    if development and not found:raise RuntimeError('Development payload missing fixtures')
    if not development and found:raise RuntimeError('Distributable payload contains development fixtures')
    print('PASS: development fixture presence' if development else 'PASS: no fixture accounts, credential payload or selector in distributable APK')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk',type=Path)
    parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--development',action='store_true')
    args=parser.parse_args()
    verify(args.apk,json.loads(args.config.read_text()),args.development)
