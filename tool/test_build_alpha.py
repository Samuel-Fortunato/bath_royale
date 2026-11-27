import base64
import json
import unittest

from build_alpha import configuration


class AlphaBuildTest(unittest.TestCase):
    def test_only_public_trusted_configuration(self):
        config = configuration(
            "https://" + "a" * 20 + ".supabase.co", "sb_publishable_test"
        )
        self.assertTrue(config["BATH_ALPHA_FEEDBACK"])
        self.assertTrue(config["BATH_PUBLIC_ALPHA"])
        self.assertEqual(
            set(config),
            {
                "SUPABASE_URL",
                "SUPABASE_PUBLISHABLE_KEY",
                "BATH_ALPHA_FEEDBACK",
                "BATH_PUBLIC_ALPHA",
            },
        )
        for url in [
            "http://localhost:55504",
            "https://localhost:55504",
            "https://user@" + "a" * 20 + ".supabase.co",
            "https://" + "a" * 20 + ".supabase.co?x=1",
        ]:
            with self.assertRaises(ValueError):
                configuration(url, "sb_publishable_test")

        def legacy(role):
            payload = (
                base64.urlsafe_b64encode(json.dumps({"role": role}).encode())
                .decode()
                .rstrip("=")
            )
            return "header." + payload + ".signature"

        self.assertEqual(
            configuration("https://" + "a" * 20 + ".supabase.co", legacy("anon"))[
                "SUPABASE_PUBLISHABLE_KEY"
            ],
            legacy("anon"),
        )
        with self.assertRaises(ValueError):
            configuration(
                "https://" + "a" * 20 + ".supabase.co", legacy("service_role")
            )
        for key in ["sb_secret_x", "service_role", "eyJ.fake.jwt"]:
            with self.assertRaises(ValueError):
                configuration("https://" + "a" * 20 + ".supabase.co", key)
