#!/usr/bin/env python3

import copy
import hashlib
import importlib.util
import json
import plistlib
import subprocess
import tempfile
import unittest
from unittest import mock
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).parents[3]
MODULE_PATH = ROOT / "Scripts/verify-pawgoo-development-app.py"
FIXTURE_PATH = (
    ROOT
    / "Automation/release-preflight/fixtures/pawgoo-development-valid.json"
)
SPEC = importlib.util.spec_from_file_location(
    "verify_pawgoo_development_app", MODULE_PATH
)
assert SPEC and SPEC.loader
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


def canonical_policy() -> dict:
    return verifier.load_policy(ROOT / "Config/release-candidate-policy.json")


def valid_fixture() -> dict:
    value = json.loads(FIXTURE_PATH.read_text())
    value["profile"]["ExpirationDate"] = datetime(
        2099, 1, 1, tzinfo=timezone.utc
    )
    value["profile"]["DeveloperCertificates"] = [b"fixture-certificate"]
    return value


class PawGooDevelopmentAppVerifierTests(unittest.TestCase):
    def setUp(self):
        self.policy = canonical_policy()
        self.fixture = valid_fixture()

    def test_exact_pawgoo_development_fixture_passes(self):
        verifier.validate_info(
            self.fixture["info"],
            "0.7.12",
            "2026072012",
            "a" * 40,
            self.policy,
        )
        verifier.validate_signature_details(
            self.fixture["signature_details"], self.policy
        )
        verifier.validate_entitlements(
            self.fixture["entitlements"], self.policy, label="signed app"
        )
        verifier.validate_profile(
            self.fixture["profile"],
            self.policy,
            ["IPHONE-TEST-UDID", "IPAD-TEST-UDID"],
            now=datetime(2026, 7, 20, tzinfo=timezone.utc),
        )

    def test_policy_cannot_weaken_development_entitlement_contract(self):
        policy = canonical_policy()
        policy["development_signed_entitlements"]["required_exact"][
            "get-task-allow"
        ] = False
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "policy.json"
            path.write_text(json.dumps(policy))
            with self.assertRaisesRegex(
                verifier.VerificationError, "not canonical"
            ):
                verifier.load_policy(path)

    def test_personal_team_artifact_fails(self):
        entitlements = copy.deepcopy(self.fixture["entitlements"])
        entitlements["application-identifier"] = (
            "6S245NCUPQ.app.tadawords.app"
        )
        entitlements["com.apple.developer.team-identifier"] = "6S245NCUPQ"
        entitlements["keychain-access-groups"] = [
            "6S245NCUPQ.app.tadawords.app"
        ]
        with self.assertRaisesRegex(verifier.VerificationError, "application-identifier"):
            verifier.validate_entitlements(
                entitlements, self.policy, label="signed app"
            )

    def test_old_normal_and_localqa_bundles_fail(self):
        for bundle in ("com.tadawords.app", "com.tadawords.app.localqa"):
            with self.subTest(bundle=bundle):
                info = copy.deepcopy(self.fixture["info"])
                info["CFBundleIdentifier"] = bundle
                with self.assertRaisesRegex(
                    verifier.VerificationError, "CFBundleIdentifier"
                ):
                    verifier.validate_info(
                        info,
                        "0.7.12",
                        "2026072012",
                        "a" * 40,
                        self.policy,
                    )

    def test_wrong_version_build_or_commit_fails(self):
        cases = {
            "CFBundleShortVersionString": "0.7.11",
            "CFBundleVersion": "2026072011",
            "TadaWordsGitCommit": "b" * 40,
        }
        for key, value in cases.items():
            with self.subTest(key=key):
                info = copy.deepcopy(self.fixture["info"])
                info[key] = value
                with self.assertRaisesRegex(verifier.VerificationError, key):
                    verifier.validate_info(
                        info,
                        "0.7.12",
                        "2026072012",
                        "a" * 40,
                        self.policy,
                    )

    def test_installable_macho_must_be_ios_arm64_only(self):
        verifier.validate_macho_metadata(" platform IOS\n", ["arm64"])
        invalid = [
            (" platform IOSSIMULATOR\n", ["arm64"]),
            (" platform MACCATALYST\n", ["arm64"]),
            (" platform IOS\n", ["x86_64"]),
            (" platform IOS\n", ["arm64", "x86_64"]),
            ("", ["arm64"]),
        ]
        for platform_output, architectures in invalid:
            with self.subTest(
                platform_output=platform_output, architectures=architectures
            ), self.assertRaises(verifier.VerificationError):
                verifier.validate_macho_metadata(
                    platform_output, architectures
                )

    def test_bundle_info_must_declare_installable_iphoneos_app(self):
        base = {
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "UIDeviceFamily": [1, 2],
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Tada Words",
        }
        mutations = {
            "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
            "UIDeviceFamily": [2],
            "CFBundlePackageType": "BNDL",
            "CFBundleExecutable": "../outside",
        }
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Tada Words.app"
            app.mkdir()
            executable = app / "Tada Words"
            executable.write_bytes(b"fixture")
            executable.chmod(0o755)
            for key, value in mutations.items():
                with self.subTest(key=key), mock.patch.object(
                    verifier, "run"
                ):
                    info = copy.deepcopy(base)
                    info[key] = value
                    with self.assertRaisesRegex(
                        verifier.VerificationError, key
                    ):
                        verifier.validate_installable_bundle(app, info)

    def test_verify_app_orchestrates_every_identity_binding(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Tada Words.app"
            app.mkdir()
            (app / "embedded.mobileprovision").touch()
            with (
                mock.patch.object(
                    verifier, "read_plist", return_value=self.fixture["info"]
                ),
                mock.patch.object(verifier, "validate_installable_bundle") as layout,
                mock.patch.object(verifier, "run"),
                mock.patch.object(
                    verifier,
                    "signature_details",
                    return_value=self.fixture["signature_details"],
                ),
                mock.patch.object(
                    verifier,
                    "signed_entitlements",
                    return_value=self.fixture["entitlements"],
                ),
                mock.patch.object(
                    verifier,
                    "decode_profile",
                    return_value=self.fixture["profile"],
                ),
                mock.patch.object(
                    verifier,
                    "signing_leaf_certificate",
                    return_value=b"fixture-certificate",
                ),
                mock.patch.object(
                    verifier,
                    "validate_app_authorized_by_profile",
                    wraps=verifier.validate_app_authorized_by_profile,
                ) as entitlement_binding,
                mock.patch.object(
                    verifier,
                    "validate_signing_certificate",
                    wraps=verifier.validate_signing_certificate,
                ) as certificate_binding,
            ):
                verifier.verify_app(
                    app,
                    "0.7.12",
                    "2026072012",
                    "a" * 40,
                    ["IPHONE-TEST-UDID", "IPAD-TEST-UDID"],
                    self.policy,
                )

            layout.assert_called_once()
            entitlement_binding.assert_called_once()
            certificate_binding.assert_called_once()

    def test_snapshot_rejects_artifact_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "Tada Words.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(b"fixture")
            destination = root / "snapshot" / "Tada Words.app"
            with mock.patch.object(
                verifier,
                "tree_sha256",
                side_effect=["before", "after-mutation", "snapshot"],
            ), self.assertRaisesRegex(verifier.VerificationError, "changed"):
                verifier.snapshot_app(app, destination)

    def test_malformed_artifact_metadata_fails_closed(self):
        with self.assertRaisesRegex(verifier.VerificationError, "dictionary"):
            verifier.validate_entitlements([], self.policy, label="signed app")
        with self.assertRaisesRegex(verifier.VerificationError, "dictionary"):
            verifier.validate_profile(
                [], self.policy, ["IPHONE-TEST-UDID"]
            )
        with self.assertRaisesRegex(verifier.VerificationError, "valid property list"):
            verifier.read_plist_bytes(b"not a plist", "fixture")

    def test_expired_profile_fails(self):
        profile = copy.deepcopy(self.fixture["profile"])
        profile["ExpirationDate"] = datetime(2026, 7, 19, tzinfo=timezone.utc)
        with self.assertRaisesRegex(verifier.VerificationError, "expired"):
            verifier.validate_profile(
                profile,
                self.policy,
                ["IPHONE-TEST-UDID"],
                now=datetime(2026, 7, 20, tzinfo=timezone.utc),
            )

    def test_runtime_device_argument_is_mandatory(self):
        with self.assertRaisesRegex(verifier.VerificationError, "device-udid"):
            verifier.validate_requested_device_udids([])

    def test_profile_must_cover_every_runtime_device_udid(self):
        with self.assertRaisesRegex(verifier.VerificationError, "missing=.*MISSING-DEVICE"):
            verifier.validate_profile(
                self.fixture["profile"],
                self.policy,
                ["IPHONE-TEST-UDID", "MISSING-DEVICE"],
                now=datetime(2026, 7, 20, tzinfo=timezone.utc),
            )

    def test_profile_must_not_cover_unapproved_extra_device(self):
        profile = copy.deepcopy(self.fixture["profile"])
        profile["ProvisionedDevices"].append("UNAPPROVED-DEVICE")
        with self.assertRaisesRegex(
            verifier.VerificationError, "unexpected=.*UNAPPROVED-DEVICE"
        ):
            verifier.validate_profile(
                profile,
                self.policy,
                ["IPHONE-TEST-UDID", "IPAD-TEST-UDID"],
                now=datetime(2026, 7, 20, tzinfo=timezone.utc),
            )

    def test_duplicate_runtime_device_argument_fails(self):
        with self.assertRaisesRegex(verifier.VerificationError, "unique"):
            verifier.validate_requested_device_udids(
                ["IPHONE-TEST-UDID", "IPHONE-TEST-UDID"]
            )

    def test_duplicate_profile_device_udid_fails(self):
        profile = copy.deepcopy(self.fixture["profile"])
        profile["ProvisionedDevices"].append("IPHONE-TEST-UDID")
        with self.assertRaisesRegex(verifier.VerificationError, "unique"):
            verifier.validate_profile(
                profile,
                self.policy,
                ["IPHONE-TEST-UDID", "IPAD-TEST-UDID"],
                now=datetime(2026, 7, 20, tzinfo=timezone.utc),
            )

    def test_realistic_profile_authorization_envelope_passes(self):
        verifier.validate_profile_authorization(
            self.fixture["profile"]["Entitlements"], self.policy
        )

    def test_profile_authorization_rejects_wrong_cloudkit_or_team_wildcard(self):
        mutations = {
            "com.apple.developer.devicecheck.appattest-environment": "production",
            "com.apple.developer.icloud-container-environment": ["Production"],
            "com.apple.developer.icloud-services": ["CloudDocuments"],
            "com.apple.developer.ubiquity-kvstore-identifier": "6S245NCUPQ.*",
            "keychain-access-groups": ["6S245NCUPQ.*", "com.apple.token"],
        }
        for key, value in mutations.items():
            with self.subTest(key=key):
                entitlements = copy.deepcopy(
                    self.fixture["profile"]["Entitlements"]
                )
                entitlements[key] = value
                with self.assertRaisesRegex(verifier.VerificationError, key):
                    verifier.validate_profile_authorization(
                        entitlements, self.policy
                    )

    def test_signed_app_entitlements_must_be_authorized_by_profile(self):
        app_entitlements = copy.deepcopy(self.fixture["entitlements"])
        app_entitlements[
            "com.apple.developer.icloud-container-development-container-identifiers"
        ] = ["iCloud.com.tadawords.app"]
        profile_entitlements = copy.deepcopy(
            self.fixture["profile"]["Entitlements"]
        )
        del profile_entitlements[
            "com.apple.developer.icloud-container-development-container-identifiers"
        ]
        with self.assertRaisesRegex(verifier.VerificationError, "not authorized"):
            verifier.validate_app_authorized_by_profile(
                app_entitlements, profile_entitlements
            )

    def test_signing_leaf_certificate_must_be_in_profile(self):
        verifier.validate_signing_certificate(
            b"fixture-certificate", self.fixture["profile"]
        )
        with self.assertRaisesRegex(verifier.VerificationError, "not authorized"):
            verifier.validate_signing_certificate(
                b"wrong-certificate", self.fixture["profile"]
            )

    def test_decode_profile_rejects_self_signed_cms(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            content = root / "content.plist"
            key = root / "fake.key"
            certificate = root / "fake.pem"
            cms = root / "fake.mobileprovision"
            content.write_bytes(plistlib.dumps(self.fixture["profile"]))
            subprocess.run(
                [
                    "/usr/bin/openssl",
                    "req",
                    "-x509",
                    "-newkey",
                    "rsa:2048",
                    "-nodes",
                    "-batch",
                    "-days",
                    "1",
                    "-subj",
                    "/CN=Fake Provisioning Profile/O=Not Apple/C=US",
                    "-keyout",
                    str(key),
                    "-out",
                    str(certificate),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            subprocess.run(
                [
                    "/usr/bin/openssl",
                    "smime",
                    "-sign",
                    "-binary",
                    "-nodetach",
                    "-in",
                    str(content),
                    "-signer",
                    str(certificate),
                    "-inkey",
                    str(key),
                    "-outform",
                    "DER",
                    "-out",
                    str(cms),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            with self.assertRaisesRegex(
                verifier.VerificationError, "command failed|pinned Apple"
            ):
                verifier.decode_profile(cms)

    def test_profile_signer_fingerprint_is_pinned(self):
        certificate = b"fixture-apple-profile-signer"
        expected = hashlib.sha256(certificate).hexdigest()
        with mock.patch.object(
            verifier, "APPLE_PROVISIONING_SIGNER_SHA256", expected
        ):
            verifier.validate_provisioning_signer_fingerprint(certificate)
            with self.assertRaisesRegex(
                verifier.VerificationError, "pinned Apple"
            ):
                verifier.validate_provisioning_signer_fingerprint(
                    b"other-system-trusted-signer"
                )

    def test_wrong_environment_container_service_and_team_fail(self):
        mutations = {
            "aps-environment": "production",
            "com.apple.developer.devicecheck.appattest-environment": "production",
            "com.apple.developer.icloud-container-environment": "Production",
            "com.apple.developer.icloud-container-identifiers": [
                "iCloud.example.wrong"
            ],
            "com.apple.developer.icloud-services": ["CloudKit", "CloudDocuments"],
            "com.apple.developer.team-identifier": "6S245NCUPQ",
        }
        for key, value in mutations.items():
            with self.subTest(key=key):
                entitlements = copy.deepcopy(self.fixture["entitlements"])
                entitlements[key] = value
                with self.assertRaisesRegex(verifier.VerificationError, key):
                    verifier.validate_entitlements(
                        entitlements, self.policy, label="signed app"
                    )

    def test_unexpected_entitlement_fails(self):
        entitlements = copy.deepcopy(self.fixture["entitlements"])
        entitlements["com.apple.developer.healthkit"] = True
        with self.assertRaisesRegex(verifier.VerificationError, "unexpected"):
            verifier.validate_entitlements(
                entitlements, self.policy, label="signed app"
            )

    def test_injected_kvstore_must_match_exact_pawgoo_normal_identity(self):
        entitlements = copy.deepcopy(self.fixture["entitlements"])
        entitlements[
            "com.apple.developer.ubiquity-kvstore-identifier"
        ] = "7R78Q4HP86.com.tadawords.app"
        with self.assertRaisesRegex(verifier.VerificationError, "ubiquity-kvstore"):
            verifier.validate_entitlements(
                entitlements, self.policy, label="signed app"
            )

    def test_profile_identity_must_be_exact_pawgoo_identity(self):
        profile = copy.deepcopy(self.fixture["profile"])
        profile["TeamIdentifier"] = ["6S245NCUPQ"]
        with self.assertRaisesRegex(verifier.VerificationError, "TeamIdentifier"):
            verifier.validate_profile(
                profile,
                self.policy,
                ["IPHONE-TEST-UDID"],
                now=datetime(2026, 7, 20, tzinfo=timezone.utc),
            )

    def test_code_signature_identity_must_be_exact(self):
        details = copy.deepcopy(self.fixture["signature_details"])
        details["TeamIdentifier"] = "6S245NCUPQ"
        with self.assertRaisesRegex(verifier.VerificationError, "TeamIdentifier"):
            verifier.validate_signature_details(details, self.policy)

    def test_expected_commit_must_be_full_sha(self):
        for value in ("", "abc", "g" * 40, "a" * 39):
            with self.subTest(value=value):
                with self.assertRaisesRegex(verifier.VerificationError, "40-character"):
                    verifier.validate_commit(value)


if __name__ == "__main__":
    unittest.main()
