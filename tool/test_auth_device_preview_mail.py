"""Token-safe mapping and recipient-isolation regressions for local test mail."""
import unittest
from unittest.mock import patch

import auth_device_mail as helper


class DeviceMailTest(unittest.TestCase):
    def test_maps_confirmation_and_recovery_without_consuming_tokens(self):
        original = 'http://127.0.0.1:55471/verify?token=fictional-123&amp;type=signup&amp;redirect_to=http%3A%2F%2Flocalhost'
        mapped = helper.mapped_links(f'<a href="{original}">Confirmar</a> {original}')
        self.assertEqual(len(mapped), 1)
        self.assertEqual(mapped[0], {
            'link': 'https://localhost:55474/auth/v1/verify?token=fictional-123&type=signup&redirect_to=http%3A%2F%2Flocalhost',
            'recovery': False,
        })
        self.assertTrue(helper.mapped_links(original.replace('signup', 'recovery'))[0]['recovery'])
        for invalid in (original.replace('55471', '55431'),
                        original.replace('127.0.0.1', 'example.com'),
                        original.replace('/verify?', '/other?'),
                        original.replace('token=fictional-123', 'other=value'),
                        original.replace('signup', 'invite')):
            self.assertEqual(helper.mapped_links(invalid), [])

    def test_recipient_filter_deduplication_and_newest_message_order(self):
        listing = {'messages': [
            {'ID': 'new-1', 'To': [{'Address': 'first@example.com'}], 'Created': '2026-11-26T12:00:00Z'},
            {'ID': 'foreign-1', 'To': [{'Address': 'other@example.com'}], 'Created': '2026-11-26T13:00:00Z'},
            {'ID': 'old-1', 'To': [{'Address': 'first@example.com'}], 'Created': '2026-11-26T11:00:00Z'},
            {'ID': '../other', 'To': [{'Address': 'first@example.com'}]},
        ]}
        def read(path):
            if path.startswith('messages?'):
                return listing
            text = 'http://127.0.0.1:55471/verify?token=fictional&type=recovery'
            return {'Text': text, 'HTML': '<a href="' + text + '">Recover</a>'}
        with patch.object(helper, 'mail', side_effect=read) as api:
            result = helper.messages_for('FIRST@example.com')
            self.assertEqual(len(result), 2)
            self.assertGreater(result[0]['created'], result[1]['created'])
            self.assertEqual([call.args[0] for call in api.call_args_list],
                             ['messages?limit=100', 'message/new-1', 'message/old-1'])
        with patch.object(helper, 'mail') as api:
            self.assertEqual(helper.messages_for(''), [])
            api.assert_not_called()


if __name__ == '__main__':
    unittest.main()
