"""Exercise publication recovery without network or real releases."""

import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import publish_preview as publisher


class PublicationTest(unittest.TestCase):
    def test_public_version_is_separate_from_build(self):
        for alpha in (True, False):
            title, notes = publisher.release_presentation("1039", alpha)
            from app_version import current

            self.assertIn(f"Bath Royale v{current()} — ", title)
            self.assertNotIn("1039", title)
            self.assertIn("Compilação interna Android: **1039**", notes)
            if alpha:
                for section in (
                    "Funcionalidades principais",
                    "Instalar ou atualizar",
                    "Limitações e privacidade da alfa",
                ):
                    self.assertIn(section, notes)
            else:
                self.assertIn("sem configuração", notes)

    def test_development_publication_is_blocked_before_io(self):
        for configured in ("false", ""):
            with (
                patch.dict(os.environ, CONFIGURED_ALPHA=configured),
                patch.object(publisher, "api") as api,
                patch.object(publisher, "gh") as gh,
            ):
                with self.assertRaisesRegex(RuntimeError, "Development builds"):
                    publisher.publish(Path("/nonexistent/artifact"))
                api.assert_not_called()
                gh.assert_not_called()

    def test_validation_workflow_has_no_publication_path(self):
        workflow = (
            Path(__file__).resolve().parents[1]
            / ".github/workflows/android-preview.yml"
        ).read_text()
        self.assertNotIn("prerelease:", workflow)
        self.assertNotIn("contents: write", workflow)
        self.assertNotIn("ALPHA_RELEASE_APPROVED", workflow)
        self.assertNotIn("upload-artifact", workflow)
        self.assertIn("BATH_BUILD_CHANNEL=development", workflow)
        self.assertIn("com.example.bath_royale.development", workflow)

    def test_publication_scenarios(self):
        for scenario in (
            "new",
            "partial",
            "complete",
            "wrong-tag",
            "wrong-asset",
            "bad-checksum",
            "incomplete-public",
            "interrupted",
            "expired-approval",
        ):
            alpha = True
            tag = "alpha-1001" if alpha else "preview-1001"
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                (directory / "bath-royale.apk").write_bytes(b"verified APK")
                checksum = hashlib.sha256(b"verified APK").hexdigest()
                (directory / "SHA256SUMS").write_text(
                    checksum + "  ./bath-royale.apk\n"
                )
                if scenario == "bad-checksum":
                    (directory / "SHA256SUMS").write_text("invalid")
                assets = (
                    []
                    if scenario in ("new", "interrupted")
                    else [{"name": "bath-royale.apk", "id": 1}]
                )
                if scenario == "complete":
                    assets.append({"name": "SHA256SUMS", "id": 2})
                release = {
                    "id": 42,
                    "tag_name": tag,
                    "target_commitish": "abc",
                    "prerelease": False,
                    "draft": scenario not in ("complete", "incomplete-public"),
                    "assets": assets,
                }
                mutations = []

                def api(path, *args):
                    if "matching-refs" in path:
                        return (
                            []
                            if scenario == "new"
                            else [
                                {
                                    "ref": f"refs/tags/{tag}",
                                    "object": {
                                        "type": "commit",
                                        "sha": "other"
                                        if scenario == "wrong-tag"
                                        else "abc",
                                    },
                                }
                            ]
                        )
                    if path.endswith("/git/refs"):
                        mutations.append("tag")
                        return {}
                    if "--paginate" in args:
                        return [[]] if scenario == "new" else [[release]]
                    self.assertNotIn("/releases/tags/", path)
                    return release

                def gh(*args):
                    mutations.append(args[1])
                    if args[1] == "upload":
                        if scenario == "interrupted":
                            raise RuntimeError("Interrupted upload")
                        name = Path(args[3]).name
                        assets.append(
                            {"name": name, "id": 1 if name.endswith(".apk") else 2}
                        )
                    return ""

                def download(args, **kwargs):
                    if scenario == "wrong-asset":
                        return b"foreign APK"
                    return (
                        directory
                        / (
                            "bath-royale.apk"
                            if args[2].endswith("/1")
                            else "SHA256SUMS"
                        )
                    ).read_bytes()

                guards = []

                def guard():
                    guards.append(True)
                    if scenario == "expired-approval" and len(guards) > 1:
                        raise RuntimeError("Approval expired before exposure")

                with (
                    patch.dict(
                        os.environ,
                        GH_REPO="owner/repo",
                        GITHUB_SHA="abc",
                        BUILD_NUMBER="1001",
                        CONFIGURED_ALPHA="true" if alpha else "false",
                    ),
                    patch.object(publisher, "api", api),
                    patch.object(publisher, "gh", gh),
                    patch.object(publisher.subprocess, "check_output", download),
                ):
                    if scenario in (
                        "wrong-tag",
                        "wrong-asset",
                        "bad-checksum",
                        "incomplete-public",
                        "interrupted",
                        "expired-approval",
                    ):
                        with self.assertRaises(RuntimeError):
                            publisher.publish(directory, guard=guard)
                        self.assertNotIn("edit", mutations)
                    else:
                        publisher.publish(directory, guard=guard)
                        self.assertEqual("edit" in mutations, scenario != "complete")
                        if scenario == "complete":
                            self.assertEqual(mutations, [])


if __name__ == "__main__":
    unittest.main()
