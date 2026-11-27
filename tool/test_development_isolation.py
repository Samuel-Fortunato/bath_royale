"""Distribution entrypoints must never import the fixture selector or embed its data."""
import base64
import json
from pathlib import Path
import re
import tempfile
import unittest
import zipfile
from verify_development_isolation import verify

ROOT=Path(__file__).resolve().parent.parent


def dependencies(path,seen=None):
    seen=set() if seen is None else seen
    if path in seen:return seen
    seen.add(path)
    for uri in re.findall(r"(?:import|export)\s+['\"]([^'\"]+)",path.read_text()):
        if uri.startswith('dart:'):continue
        if uri.startswith('package:bath_royale/'):target=ROOT/'lib'/uri.removeprefix('package:bath_royale/')
        elif ':' not in uri:target=(path.parent/uri).resolve()
        else:continue
        dependencies(target,seen)
    return seen


class DistributionGuards(unittest.TestCase):
    def test_distributable_dependency_graphs_exclude_development_shortcuts(self):
        for entry in (ROOT/'lib/main.dart',ROOT/'tool/auth_device_preview.dart'):
            files=dependencies(entry)
            self.assertNotIn(ROOT/'tool/local_development.dart',files)
            self.assertFalse(any('BATH_LOCAL_TEST_ACCOUNTS' in p.read_text() for p in files))
    def test_artifact_scan_detects_encoded_fixture_credentials(self):
        config={'BATH_LOCAL_TEST_ACCOUNTS':base64.b64encode(json.dumps([{'email':'fixture-unit@example.invalid','password':'dummy-unit-input'}]).encode()).decode()}
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'app.apk'
            with zipfile.ZipFile(path,'w') as archive:archive.writestr('lib/arm64-v8a/libapp.so',config['BATH_LOCAL_TEST_ACCOUNTS'].encode())
            with self.assertRaises(RuntimeError):verify(path,config)
            verify(path,config,True)
            with zipfile.ZipFile(path,'w') as archive:archive.writestr('lib/arm64-v8a/libapp.so',b'ordinary app payload')
            verify(path,config)
