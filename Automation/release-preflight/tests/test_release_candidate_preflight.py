#!/usr/bin/env python3

import importlib.util
import json
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[3] / "Scripts/release-candidate-preflight.py"
SPEC = importlib.util.spec_from_file_location("release_candidate_preflight", MODULE_PATH)
assert SPEC and SPEC.loader
preflight = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preflight)


def write_plist(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        plistlib.dump(value, stream)


def base_info(version: str = "0.6.7", build: str = "2026071804") -> dict:
    return {
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "TadaWordsGitCommit": "$(TADA_GIT_COMMIT)",
    }


def source_fixture(root: Path) -> dict:
    write_plist(root / "Apps/TadaWordsApp/Info.plist", base_info())
    write_plist(root / "Apps/TadaWordsApp/InfoLocalQA.plist", base_info())
    (root / "project.yml").write_text(
        """MARKETING_VERSION: 0.6.7
CURRENT_PROJECT_VERSION: 2026071804
PRODUCT_BUNDLE_IDENTIFIER: com.tadawords.app
PRODUCT_BUNDLE_IDENTIFIER: com.tadawords.app.localqa
"""
    )
    project = root / "TadaWords.xcodeproj/project.pbxproj"
    project.parent.mkdir(parents=True)
    project.write_text(
        """MARKETING_VERSION = 0.6.7;
CURRENT_PROJECT_VERSION = 2026071804;
PRODUCT_BUNDLE_IDENTIFIER = com.tadawords.app;
PRODUCT_BUNDLE_IDENTIFIER = com.tadawords.app.localqa;
"""
    )
    return {"bundle_id": "com.tadawords.app"}


def valid_entitlements(team: str = "TEAM123") -> dict:
    return {
        "application-identifier": f"{team}.com.tadawords.app",
        "aps-environment": "production",
        "com.apple.developer.icloud-container-environment": "Production",
        "com.apple.developer.icloud-container-identifiers": [
            "iCloud.com.tadawords.app"
        ],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.team-identifier": team,
        "com.apple.developer.ubiquity-kvstore-identifier": f"{team}.com.tadawords.app",
        "keychain-access-groups": [f"{team}.com.tadawords.app"],
        "get-task-allow": False,
    }


def canonical_policy() -> dict:
    root = MODULE_PATH.parents[1]
    return json.loads((root / "Config/release-candidate-policy.json").read_text())


class ReleaseCandidatePreflightTests(unittest.TestCase):
    def test_repository_source_entitlements_match_canonical_policy(self):
        root = MODULE_PATH.parents[1]
        policy = canonical_policy()
        with (root / "Apps/TadaWordsApp/TadaWords.entitlements").open("rb") as stream:
            source_entitlements = plistlib.load(stream)

        self.assertEqual(source_entitlements, policy["source_entitlements"])
        self.assertEqual(
            source_entitlements["aps-environment"], "$(APS_ENVIRONMENT)"
        )
        self.assertEqual(
            policy["source_entitlements"]["aps-environment"],
            "$(APS_ENVIRONMENT)",
        )

    def test_dirty_release_source_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(
                ["git", "config", "user.email", "preflight@example.invalid"],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "Preflight Test"], cwd=root, check=True
            )
            (root / "tracked").write_text("clean")
            subprocess.run(["git", "add", "tracked"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=root, check=True)
            (root / "tracked").write_text("dirty")
            with self.assertRaisesRegex(preflight.PreflightError, "release source is dirty"):
                preflight.assert_clean_repository(root)

    def test_source_version_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            policy = source_fixture(root)
            write_plist(
                root / "Apps/TadaWordsApp/InfoLocalQA.plist",
                base_info(version="0.6.6"),
            )
            with self.assertRaisesRegex(preflight.PreflightError, "LocalQA source version"):
                preflight.validate_source_identity(root, policy)

    def test_generated_build_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            policy = source_fixture(root)
            project = root / "TadaWords.xcodeproj/project.pbxproj"
            project.write_text(project.read_text().replace("2026071804", "2026071803"))
            with self.assertRaisesRegex(preflight.PreflightError, "generated project build"):
                preflight.validate_source_identity(root, policy)

    def test_wrong_bundle_id_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            policy = source_fixture(root)
            policy["bundle_id"] = "com.example.wrong"
            with self.assertRaisesRegex(preflight.PreflightError, "expected production/LocalQA"):
                preflight.validate_source_identity(root, policy)

    def test_wrong_team_entitlement_fails(self):
        entitlements = valid_entitlements(team="WRONG")
        with self.assertRaisesRegex(preflight.PreflightError, "application-identifier"):
            preflight.validate_signed_entitlements(
                entitlements, canonical_policy(), "TEAM123"
            )

    def test_unexpected_entitlement_fails(self):
        entitlements = valid_entitlements()
        entitlements["com.apple.developer.healthkit"] = True
        with self.assertRaisesRegex(preflight.PreflightError, "unexpected signed entitlements"):
            preflight.validate_signed_entitlements(
                entitlements, canonical_policy(), "TEAM123"
            )

    def test_valid_production_push_entitlement_passes_for_export(self):
        preflight.validate_signed_entitlements(
            valid_entitlements(), canonical_policy(), "TEAM123", "export"
        )

    def test_missing_production_push_entitlement_fails_for_export(self):
        entitlements = valid_entitlements()
        del entitlements["aps-environment"]
        with self.assertRaisesRegex(preflight.PreflightError, "aps-environment"):
            preflight.validate_signed_entitlements(
                entitlements, canonical_policy(), "TEAM123", "export"
            )

    def test_development_push_entitlement_fails_for_export(self):
        entitlements = valid_entitlements()
        entitlements["aps-environment"] = "development"
        with self.assertRaisesRegex(preflight.PreflightError, "aps-environment"):
            preflight.validate_signed_entitlements(
                entitlements, canonical_policy(), "TEAM123", "export"
            )

    def test_localqa_entitlements_cannot_be_export_evidence(self):
        entitlements = {
            "application-identifier": "TEAM123.com.tadawords.app.localqa",
            "com.apple.developer.team-identifier": "TEAM123",
            "get-task-allow": True,
        }
        with self.assertRaisesRegex(preflight.PreflightError, "application-identifier"):
            preflight.validate_signed_entitlements(
                entitlements, canonical_policy(), "TEAM123", "export"
            )

    def test_archive_may_be_development_signed_but_export_must_be_production(self):
        entitlements = valid_entitlements()
        entitlements["aps-environment"] = "development"
        entitlements["com.apple.developer.icloud-container-environment"] = "Development"
        entitlements["get-task-allow"] = True
        preflight.validate_signed_entitlements(
            entitlements, canonical_policy(), "TEAM123", "archive"
        )
        entitlements["aps-environment"] = "production"
        with self.assertRaisesRegex(
            preflight.PreflightError, "icloud-container-environment"
        ):
            preflight.validate_signed_entitlements(
                entitlements, canonical_policy(), "TEAM123", "export"
            )

    def test_missing_privacy_manifest_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Tada Words.app"
            app.mkdir()
            write_plist(
                app / "Info.plist",
                {"CFBundleExecutable": "Tada Words", "CFBundleIcons": {"primary": {}}},
            )
            (app / "Tada Words").write_bytes(b"binary")
            policy = {"required_app_resources": ["PrivacyInfo.xcprivacy"]}
            with self.assertRaisesRegex(preflight.PreflightError, "PrivacyInfo.xcprivacy"):
                preflight.validate_app_resources(app, app, policy, {})

    def test_missing_icon_resource_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Tada Words.app"
            app.mkdir()
            write_plist(
                app / "Info.plist",
                {"CFBundleExecutable": "Tada Words", "CFBundleIcons": {"primary": {}}},
            )
            write_plist(app / "PrivacyInfo.xcprivacy", {})
            (app / "Tada Words").write_bytes(b"binary")
            policy = {
                "required_app_resources": ["PrivacyInfo.xcprivacy", "AppIcon*.png"]
            }
            with self.assertRaisesRegex(preflight.PreflightError, "AppIcon"):
                preflight.validate_app_resources(app, app, policy, {})

    def test_identity_guardrail_receives_expected_team(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "arguments.json"
            verifier = root / "verifier"
            verifier.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$@\" | python3 -c "
                "'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))' "
                f"> '{output}'\n"
            )
            verifier.chmod(0o755)
            app = root / "App.app"
            app.mkdir()
            preflight.verify_signed_identity(
                verifier,
                app,
                "0.6.7",
                "2026071804",
                "a" * 40,
                "com.tadawords.app",
                "TEAM123",
            )
            self.assertEqual(json.loads(output.read_text())[-1], "TEAM123")

    def test_manifest_gate_names_remain_distinct(self):
        source = MODULE_PATH.read_text()
        for gate in (
            '"simulator": "separate_not_run"',
            '"physical_install": "separate_not_run"',
            '"physical_launch_smoke": "separate_not_run"',
            '"automated_device_tests": "separate_not_run"',
            '"human_acceptance": "separate_human_gate_not_run"',
            '"testflight_upload": "prohibited_not_run"',
        ):
            self.assertIn(gate, source)


if __name__ == "__main__":
    unittest.main()
