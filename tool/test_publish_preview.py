"""Exercise publication recovery without network or real releases."""
import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import publish_preview as publisher


class PublicationTest(unittest.TestCase):
    def test_checkout_precedes_artifact_download(self):
        workflow = (Path(__file__).resolve().parents[1] /
                    '.github/workflows/android-preview.yml').read_text()
        publication = workflow.split('  prerelease:', 1)[1]
        self.assertLess(publication.index('actions/checkout@'),
                        publication.index('actions/download-artifact@'))
        self.assertEqual(workflow.count('flutter build apk'), 1)
        self.assertEqual(workflow.count('contents: write'), 1)
        self.assertIn('flutter build apk --release --no-pub', workflow)
        self.assertNotIn('--split-per-abi', workflow)
        self.assertIn('app-release.apk', workflow)
        self.assertLess(workflow.index('python3 tool/verify_preview.py key'),
                        workflow.index('flutter build apk'))
        self.assertLess(workflow.index('python3 tool/verify_preview.py apk'),
                        workflow.index('Upload APK and checksum'))

    def test_publication_scenarios(self):
        for scenario in ('new', 'partial', 'complete', 'wrong-tag', 'wrong-asset',
                         'bad-checksum', 'incomplete-public', 'interrupted'):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                (directory / 'bath-royale.apk').write_bytes(b'verified APK')
                checksum = hashlib.sha256(b'verified APK').hexdigest()
                (directory / 'SHA256SUMS').write_text(
                    checksum + '  ./bath-royale.apk\n')
                if scenario == 'bad-checksum':
                    (directory / 'SHA256SUMS').write_text('invalid')
                assets = [] if scenario in ('new', 'interrupted') else [
                    {'name': 'bath-royale.apk', 'id': 1}]
                if scenario == 'complete':
                    assets.append({'name': 'SHA256SUMS', 'id': 2})
                release = {'id': 42, 'tag_name': 'preview-1001', 'target_commitish': 'abc',
                           'prerelease': True, 'draft': scenario not in
                           ('complete', 'incomplete-public'), 'assets': assets}
                mutations = []

                def api(path, *args):
                    if 'matching-refs' in path:
                        return [] if scenario == 'new' else [{
                            'ref': 'refs/tags/preview-1001', 'object': {
                                'type': 'commit', 'sha': 'other' if scenario ==
                                'wrong-tag' else 'abc'}}]
                    if path.endswith('/git/refs'):
                        mutations.append('tag')
                        return {}
                    if '--paginate' in args:
                        return [[]] if scenario == 'new' else [[release]]
                    self.assertNotIn('/releases/tags/', path)
                    return release

                def gh(*args):
                    mutations.append(args[1])
                    if args[1] == 'upload':
                        if scenario == 'interrupted':
                            raise RuntimeError('Interrupted upload')
                        name = Path(args[3]).name
                        assets.append({'name': name, 'id': 1 if name.endswith('.apk') else 2})
                    return ''

                def download(args, **kwargs):
                    if scenario == 'wrong-asset':
                        return b'foreign APK'
                    return (directory / ('bath-royale.apk' if args[2].endswith('/1')
                                         else 'SHA256SUMS')).read_bytes()

                with patch.dict(os.environ, GH_REPO='owner/repo', GITHUB_SHA='abc',
                                BUILD_NUMBER='1001'), patch.object(publisher, 'api', api), \
                        patch.object(publisher, 'gh', gh), \
                        patch.object(publisher.subprocess, 'check_output', download):
                    if scenario in ('wrong-tag', 'wrong-asset', 'bad-checksum',
                                    'incomplete-public', 'interrupted'):
                        with self.assertRaises(RuntimeError):
                            publisher.publish(directory)
                        self.assertNotIn('edit', mutations)
                    else:
                        publisher.publish(directory)
                        self.assertEqual('edit' in mutations, scenario != 'complete')
                        if scenario == 'complete':
                            self.assertEqual(mutations, [])


if __name__ == '__main__':
    unittest.main()
