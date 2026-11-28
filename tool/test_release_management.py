"""Release invariants exercised with disposable files and an in-memory remote."""

# Nested resource and failure contexts make their lifetime explicit in these tests.
# ruff: noqa: SIM117
import copy
import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import app_version as version
import managed_release as service
import release_ledger as allocator


class MemoryLedger(allocator.Ledger):
    def __init__(self):
        self.state = {"format": 1, "allocations": [], "publication": None}
        self.revision = 0
        self.collide = False
        self.unknown = False

    def read(self):
        return self.revision, copy.deepcopy(self.state)

    def tag_floor(self):
        return allocator.FLOOR

    def write(self, parent, value):
        if self.collide:
            self.collide = False
            self.state["allocations"].append(
                {
                    "request": "b" * 32,
                    "source": "b" * 40,
                    "version": "0.2.0",
                    "code": allocator.FLOOR + 1,
                }
            )
            self.revision += 1
        if parent != self.revision:
            raise allocator.RemoteError(422)
        self.state = copy.deepcopy(value)
        self.revision += 1
        if self.unknown:
            self.unknown = False
            raise allocator.RemoteError()


class VersionTests(unittest.TestCase):
    def test_authority_bumps_and_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            p = root / "pubspec.yaml"
            p.write_text("name: sample\nversion: 2.3.4\n")
            for part, expected in (
                ("patch", "2.3.5"),
                ("minor", "2.4.0"),
                ("major", "3.0.0"),
            ):
                self.assertEqual(version.bump(part, root=root)["after"], expected)
                self.assertEqual(version.current(root), "2.3.4")
            self.assertEqual(
                version.metadata("candidate", 1234, root)["version_name"],
                "2.3.4-alpha.1234",
            )
            self.assertEqual(
                version.metadata("development", 1, root)["package"],
                "com.example.bath_royale.development",
            )
            version.bump("minor", root=root, apply=True)
            self.assertEqual(version.current(root), "2.4.0")
            for text in (
                "version: 01.2.3",
                "version: 1.2.3+4",
                "version: 1.2.3\nversion: 1.2.4",
            ):
                p.write_text(text)
                with self.assertRaises(ValueError):
                    version.current(root)
        for channel, code in (
            ("other", 2),
            ("development", 2),
            ("candidate", 0),
            ("alpha", 2100000001),
        ):
            with self.assertRaises(ValueError):
                version.metadata(channel, code)

    def test_consumers_have_no_independent_version(self):
        root = Path(__file__).resolve().parents[1]
        for path in (
            "tool/build_alpha.py",
            "tool/install_private_alpha.py",
            ".github/workflows/android-preview.yml",
            "lib/widgets/alpha_feedback.dart",
            "android/app/src/main/kotlin/com/example/bath_royale/MainActivity.kt",
        ):
            self.assertNotRegex((root / path).read_text(), r"0\.1\.[01]")
        self.assertRegex(version.current(), r"^\d+\.\d+\.\d+$")


class AllocationTests(unittest.TestCase):
    def test_collision_retry_and_concurrent_writer(self):
        ledger = MemoryLedger()
        ledger.collide = True
        row = ledger.allocate("a" * 32, "a" * 40, "0.2.0")
        self.assertEqual(row["code"], allocator.FLOOR + 2)
        self.assertEqual(ledger.allocate("a" * 32, "a" * 40, "0.2.0"), row)
        self.assertEqual(len(ledger.state["allocations"]), 2)
        with self.assertRaises(ValueError):
            ledger.allocate("a" * 32, "c" * 40, "0.2.0")
        newer = ledger.allocate("c" * 32, "c" * 40, "0.2.0", minimum=row["code"] + 50)
        self.assertGreater(newer["code"], row["code"] + 50)

    def test_unknown_network_outcome_uses_same_request(self):
        ledger = MemoryLedger()
        ledger.unknown = True
        with self.assertRaises(allocator.RemoteError):
            ledger.allocate("a" * 32, "a" * 40, "0.2.0")
        row = ledger.allocate("a" * 32, "a" * 40, "0.2.0")
        self.assertEqual(row["code"], allocator.FLOOR + 1)
        self.assertEqual(len(ledger.state["allocations"]), 1)

    def test_exhaustion_and_request_validation(self):
        ledger = MemoryLedger()
        with self.assertRaises(ValueError):
            ledger.allocate("bad", "a" * 40, "0.2.0")
        with self.assertRaises(ValueError):
            ledger.allocate("a" * 32, "a" * 40, "0.2.0", minimum=allocator.MAX_CODE)

    def test_stale_concurrent_expired_approvals_and_allocation_exclusion(self):
        ledger = MemoryLedger()
        old = ledger.allocate("a" * 32, "a" * 40, "0.2.0")
        row = ledger.allocate("b" * 32, "b" * 40, "0.2.0")
        with self.assertRaises(ValueError):
            ledger.acquire({"allocation": old})
        binding = {"allocation": row, "notes": "reviewed"}
        ledger.acquire(binding)
        for operation in (
            lambda: ledger.acquire(binding),
            lambda: ledger.allocate("c" * 32, "c" * 40, "0.2.0"),
            lambda: ledger.assert_lease(dict(binding, notes="changed")),
            lambda: ledger.release(dict(binding, notes="changed")),
        ):
            with self.assertRaises(ValueError):
                operation()
        ledger.assert_lease(binding)
        ledger.state["publication"]["expires"] = (
            dt.datetime.now(dt.UTC) - dt.timedelta(seconds=1)
        ).isoformat()
        with self.assertRaises(ValueError):
            ledger.assert_lease(binding)
        with self.assertRaises(ValueError):
            ledger.acquire(binding)
        ledger.release(binding)
        self.assertIsNone(ledger.state["publication"])


class AdditionalReleaseTests(unittest.TestCase):
    def test_non_force_ref_update_and_bootstrap(self):
        ledger = allocator.Ledger("owner/app")
        for parent in (None, "a" * 40):
            calls = []

            def api(path, payload=None, method=None, calls=calls):
                calls.append((path, payload, method))
                return {"sha": "b" * 40}

            with patch.object(ledger, "api", side_effect=api):
                ledger.write(
                    parent, {"format": 1, "allocations": [], "publication": None}
                )
            last = calls[-1]
            if parent:
                self.assertIs(last[1]["force"], False)
                self.assertEqual(calls[1][1]["parents"], [parent])
            else:
                self.assertEqual(last[1]["ref"], "refs/heads/" + allocator.BRANCH)
                self.assertEqual(calls[1][1]["parents"], [])

    def test_network_errors_are_never_absence(self):
        ledger = allocator.Ledger("owner/app")
        for status in (None, 401, 403, 500):
            with patch.object(ledger, "api", side_effect=allocator.RemoteError(status)):
                with self.assertRaises(allocator.RemoteError):
                    ledger.read()
        with patch.object(ledger, "api", side_effect=allocator.RemoteError(404)):
            self.assertIsNone(ledger.read()[0])

    def test_missing_initialized_branch_never_resets_counter(self):
        ledger = allocator.Ledger("owner/app")
        with patch.object(
            ledger,
            "api",
            side_effect=[allocator.RemoteError(404), {"object": {"sha": "a" * 40}}],
        ):
            with self.assertRaisesRegex(ValueError, "sem reiniciar"):
                ledger.read()

    def test_actual_file_lock_excludes_concurrent_build(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "candidate"
            with service.build_lock(directory):
                with self.assertRaises(ValueError):
                    with service.build_lock(directory):
                        pass
            with service.build_lock(directory):
                pass

    def test_payload_scanner_rejects_fixtures(self):
        import zipfile

        from build_alpha import verify_distribution_payload

        with tempfile.TemporaryDirectory() as temp:
            apk = Path(temp) / "fixture.apk"
            for payload, bad in (
                (b"normal aot payload", False),
                ("Exemplo fictício".encode(), True),
                ("Contas de teste".encode("utf-16-le"), True),
            ):
                with zipfile.ZipFile(apk, "w") as archive:
                    archive.writestr("lib/arm64-v8a/libapp.so", payload)
                if bad:
                    with self.assertRaises(RuntimeError):
                        verify_distribution_payload(apk)
                else:
                    verify_distribution_payload(apk)


class ReleaseServiceTests(unittest.TestCase):
    def test_source_dirty_ahead_behind_fail_closed(self):
        for dirty, counts in ((" M pubspec.yaml", "0 0"), ("", "1 0"), ("", "0 1")):
            with (
                patch.object(service, "run", side_effect=["", "a" * 40, dirty, counts]),
                self.assertRaises(ValueError),
            ):
                service.source(strict=True)
        with patch.object(service, "run", side_effect=["", "a" * 40, "", "0 0"]):
            self.assertFalse(service.source(strict=True)["dirty"])

    def test_required_ci_exact_commit_and_latest_attempt(self):
        good = {
            "id": 1,
            "head_sha": "a" * 40,
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "run_number": 20,
            "run_attempt": 1,
        }
        for bad in (
            dict(good, status="in_progress"),
            dict(good, conclusion="failure"),
            dict(good, head_sha="b" * 40),
        ):
            with patch.object(service, "api", return_value={"workflow_runs": [bad]}):
                with self.assertRaises(ValueError):
                    service.ci_required("owner/app", "a" * 40)
        with (
            patch.object(
                service,
                "api",
                return_value={
                    "workflow_runs": [good, dict(good, run_attempt=2, status="queued")]
                },
            ),
            self.assertRaises(ValueError),
        ):
            service.ci_required("owner/app", "a" * 40)

    def test_install_rejects_fixtures_missing_or_downgrade(self):
        base = {
            "channel": "candidate",
            "package": "com.example.bath_royale",
            "version_code": 2000001,
            "version_name": "0.2.0-alpha.2000001",
        }
        for record, installed in (
            (dict(base, channel="development"), ""),
            (base, ""),
            (base, "versionCode=2000001"),
            (base, "versionCode=2000002"),
        ):
            with (
                patch.object(service, "verify_record", return_value=record),
                patch.object(service, "run", side_effect=["", installed]) as run,
            ):
                with self.assertRaises(ValueError):
                    service.install("/disposable")
                self.assertFalse(
                    any(
                        "install" in c.args
                        or "uninstall" in c.args
                        or "clear" in c.args
                        for c in run.call_args_list
                    )
                )

    def test_publication_cleanup_success_failure_cancellation_and_network(self):
        binding = {
            "allocation": {
                "code": 2000001,
                "source": "a" * 40,
                "version": "0.2.0",
                "request": "a" * 32,
            },
            "artifact": "hash",
        }
        request = {
            "repo": "owner/app",
            "directory": "/disposable",
            "verification_directory": "/verify",
            "confirm": allocator.digest(binding),
        }
        for outcome in (None, RuntimeError("failure"), KeyboardInterrupt()):
            ledger = MemoryLedger()
            ledger.state["allocations"] = [binding["allocation"]]
            calls = []
            with (
                patch.object(service, "binding_for", return_value=binding),
                patch.object(service, "Ledger", return_value=ledger),
                patch.object(service, "gh", return_value="false"),
                patch.object(
                    service,
                    "gate",
                    side_effect=lambda repo, on, calls=calls: calls.append(on),
                ),
                patch("publish_preview.publish", side_effect=outcome),
                patch.object(service, "download", return_value={"sha256": "hash"}),
            ):
                if outcome is None:
                    self.assertTrue(service.publish(request)["published"])
                else:
                    with self.assertRaises(type(outcome)):
                        service.publish(request)
            self.assertEqual(calls, [True, False])
            if outcome is None:
                self.assertIsNone(ledger.state["publication"])
            else:
                self.assertIsNotNone(ledger.state["publication"])
        ledger = MemoryLedger()
        ledger.state["allocations"] = [binding["allocation"]]
        with (
            patch.object(service, "binding_for", return_value=binding),
            patch.object(service, "Ledger", return_value=ledger),
            patch.object(service, "gh", return_value="false"),
            patch.object(service, "gate", side_effect=[None, allocator.RemoteError()]),
            patch("publish_preview.publish", side_effect=RuntimeError("failure")),
        ):
            with self.assertRaises(allocator.RemoteError):
                service.publish(request)
        self.assertIsNotNone(ledger.state["publication"])

    def test_confirmation_mismatch_and_preview_do_not_enable_gate(self):
        with (
            patch.object(service, "binding_for", return_value={"source": "reviewed"}),
            patch.object(service, "gate") as gate,
        ):
            self.assertFalse(service.publish({})["approved"])
            with self.assertRaises(ValueError):
                service.publish({"confirm": "stale"})
            gate.assert_not_called()

    def test_reconciliation_disables_gate_before_freeing_expired_exclusion(self):
        ledger = MemoryLedger()
        row = ledger.allocate("a" * 32, "a" * 40, "0.2.0")
        ledger.acquire(
            {"allocation": row}, now=dt.datetime.now(dt.UTC) - dt.timedelta(hours=2)
        )
        request = {"repo": "owner/app", "confirm": allocator.digest(ledger.state)}
        with (
            patch.object(service, "Ledger", return_value=ledger),
            patch.object(service, "gate") as gate,
        ):
            with self.assertRaises(ValueError):
                service.reconcile(request)
            self.assertIsNotNone(ledger.state["publication"])
            self.assertTrue(
                service.reconcile(dict(request, publisher_stopped=True))["reconciled"]
            )
            self.assertIsNone(ledger.state["publication"])
            self.assertEqual(gate.call_count, 2)

    def test_nonmonotonic_publication_rejected_before_owner_gate(self):
        request = {"repo": "owner/app", "directory": "/disposable", "public_config": {}}
        for semantic, code in (("0.1.1", 1000001), ("0.1.0", 1000001), ("0.2.0", 1046)):
            record = {
                "channel": "candidate",
                "source": "a" * 40,
                "notes_hash": "notes",
                "config_hash": allocator.digest({}),
                "version": semantic,
                "version_code": code,
            }
            with (
                patch.object(service, "source", return_value={"source": "a" * 40}),
                patch.object(service, "verify_record", return_value=record),
                patch.object(service, "checksum", return_value="notes"),
                patch.object(service, "public_config", return_value={}),
                patch.object(service, "configuration", return_value={}),
                patch.object(service, "gh", return_value="public"),
                patch.object(
                    service,
                    "api",
                    side_effect=[
                        {"object": {"sha": "a" * 40}},
                        {"tag_name": "alpha-1046", "name": "Bath Royale v0.1.1 — Alfa"},
                    ],
                ),
                patch.object(service, "gate") as gate,
            ):
                with self.assertRaisesRegex(ValueError, "superiores"):
                    service.binding_for(request)
                gate.assert_not_called()

    def test_signing_password_file_is_protected_and_removed_on_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            target = base / "candidate"
            key = base / "key"
            config = base / "signing.json"
            key.write_bytes(b"disposable keystore")
            key.chmod(0o600)
            config.write_text(
                json.dumps(
                    {
                        "alias": "disposable-alias",
                        "store_password": "disposable-marker",
                        "key_password": "different-marker",
                    }
                )
            )
            config.chmod(0o600)
            observed = []

            def verify(key_path, password_path):
                observed.append(password_path)
                self.assertEqual(password_path.stat().st_mode & 0o777, 0o600)
                self.assertEqual(password_path.read_text(), "disposable-marker")
                raise RuntimeError("certificate rejected")

            with (
                patch.object(
                    service, "source", return_value={"source": "a" * 40, "dirty": False}
                ),
                patch.object(service, "verify_key", side_effect=verify),
            ):
                with self.assertRaises(RuntimeError):
                    service.build_locked(
                        {
                            "channel": "development",
                            "directory": str(target),
                            "keystore": str(key),
                            "signing_config": str(config),
                        }
                    )
            self.assertTrue(observed)
            self.assertFalse(observed[0].exists())

    def test_incomplete_artifacts_and_symlinks_are_never_overwritten(self):
        for symlink in (False, True):
            with tempfile.TemporaryDirectory() as temp:
                base = Path(temp)
                target = base / "candidate"
                target.mkdir(mode=0o700)
                victim = base / "preserved"
                victim.write_bytes(b"disposable-original")
                apk = target / "bath-royale.apk"
                if symlink:
                    apk.symlink_to(victim)
                else:
                    apk.write_bytes(b"failed-artifact")
                with (
                    patch.object(service, "source", return_value={"source": "a" * 40}),
                    patch.object(service, "Ledger") as ledger,
                ):
                    with self.assertRaisesRegex(ValueError, "nada foi substituído"):
                        service.build_locked(
                            {"channel": "candidate", "directory": str(target)}
                        )
                    ledger.assert_not_called()
                self.assertEqual(victim.read_bytes(), b"disposable-original")
                self.assertEqual(
                    apk.read_bytes(),
                    b"disposable-original" if symlink else b"failed-artifact",
                )
                with self.assertRaises(FileExistsError):
                    service.write_private(apk, b"replacement")

    def test_public_update_verifies_after_install_without_destructive_flags(self):
        record = {
            "channel": "alpha",
            "package": "com.example.bath_royale",
            "version_code": 1000002,
            "version_name": "0.1.2-alpha.1000002",
        }
        outputs = [
            "",
            "versionCode=1046",
            "package:/data/app/safe/base.apk",
            "",
            "Signer #1 certificate SHA-256 digest: " + service.CERTIFICATE,
            "",
            "versionCode=1000002 versionName=0.1.2-alpha.1000002",
        ]
        with (
            patch.object(service, "verify_public", return_value=record),
            patch.object(service, "run", side_effect=outputs) as run,
            patch.dict(service.os.environ, ANDROID_HOME="/sdk"),
        ):
            result = service.install("/disposable", "owner/app")
        self.assertTrue(result["installed"])
        self.assertTrue(
            any(c.args[:3] == ("adb", "install", "-r") for c in run.call_args_list)
        )
        self.assertFalse(
            any(
                "uninstall" in c.args or "clear" in c.args or "-d" in c.args
                for c in run.call_args_list
            )
        )

    def test_wrong_signature_rejects_before_install(self):
        record = {
            "channel": "candidate",
            "package": "com.example.bath_royale",
            "version_code": 2000001,
            "version_name": "0.2.0-alpha.2000001",
        }
        outputs = [
            "",
            "versionCode=1046",
            "package:/data/app/safe/base.apk",
            "",
            "wrong certificate",
        ]
        with (
            patch.object(service, "verify_record", return_value=record),
            patch.object(service, "run", side_effect=outputs) as run,
            patch.dict(service.os.environ, ANDROID_HOME="/sdk"),
        ):
            with self.assertRaises(ValueError):
                service.install("/disposable")
            self.assertFalse(any("install" in c.args for c in run.call_args_list))
