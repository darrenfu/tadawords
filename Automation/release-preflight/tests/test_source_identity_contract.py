import plistlib
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


class SourceIdentityContractTests(unittest.TestCase):
    def test_project_keeps_normal_and_localqa_identities_independent(self):
        project = (REPO_ROOT / "project.yml").read_text(encoding="utf-8")

        self.assertIn("bundleIdPrefix: app.tadawords", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: app.tadawords.app", project)
        self.assertIn(
            "PRODUCT_BUNDLE_IDENTIFIER: app.tadawords.app.uitests", project
        )
        self.assertIn(
            "PRODUCT_BUNDLE_IDENTIFIER: com.tadawords.app.localqa", project
        )
        self.assertIn(
            "PRODUCT_BUNDLE_IDENTIFIER: com.tadawords.app.uitests", project
        )
        self.assertIn(
            "PRODUCT_BUNDLE_IDENTIFIER: com.tadawords.app.devicetests", project
        )
        self.assertEqual(project.count("DEVELOPMENT_TEAM: 7R78Q4HP86"), 4)
        self.assertNotIn("6S245NCUPQ", project)
        self.assertEqual(project.count("APS_ENVIRONMENT: development"), 1)
        self.assertEqual(project.count("APS_ENVIRONMENT: production"), 1)

    def test_normal_entitlements_are_cloudkit_only_and_localqa_is_empty(self):
        with (REPO_ROOT / "Apps/TadaWordsApp/TadaWords.entitlements").open(
            "rb"
        ) as handle:
            normal = plistlib.load(handle)
        with (REPO_ROOT / "Apps/TadaWordsApp/TadaWordsLocalQA.entitlements").open(
            "rb"
        ) as handle:
            localqa = plistlib.load(handle)

        self.assertEqual(normal["aps-environment"], "$(APS_ENVIRONMENT)")
        self.assertEqual(
            normal["com.apple.developer.icloud-container-identifiers"],
            ["iCloud.com.tadawords.app"],
        )
        self.assertEqual(
            normal["com.apple.developer.icloud-services"], ["CloudKit"]
        )
        self.assertNotIn(
            "com.apple.developer.ubiquity-kvstore-identifier", normal
        )
        self.assertEqual(localqa, {})

    def test_runtime_uses_bundle_identity_without_changing_data_namespaces(self):
        speech = (
            REPO_ROOT
            / "Sources/TadaWordsApplePlatform/AppleSpeechRecognitionService.swift"
        ).read_text(encoding="utf-8")
        bootstrap = (
            REPO_ROOT / "Sources/TadaWordsAppShell/ApplicationBootstrap.swift"
        ).read_text(encoding="utf-8")
        access = (
            REPO_ROOT
            / "Sources/TadaWordsApplePlatform/CloudKitFamilyAccessManager.swift"
        ).read_text(encoding="utf-8")
        transport = (
            REPO_ROOT
            / "Sources/TadaWordsApplePlatform/CloudKitFamilySyncTransport.swift"
        ).read_text(encoding="utf-8")
        persistence = (
            REPO_ROOT
            / "Sources/TadaWordsApplePlatform/CloudKitFamilySyncPersistence.swift"
        ).read_text(encoding="utf-8")
        voiceprint = (
            REPO_ROOT
            / "Sources/TadaWordsApplePlatform/KeychainDeviceVoiceprintRepository.swift"
        ).read_text(encoding="utf-8")

        runtime_subsystem = (
            'subsystem: Bundle.main.bundleIdentifier ?? "app.tadawords.app"'
        )
        self.assertIn(runtime_subsystem, speech)
        self.assertIn(runtime_subsystem, bootstrap)
        self.assertNotIn('subsystem: "com.tadawords.app"', speech)
        self.assertNotIn('subsystem: "com.tadawords.app"', bootstrap)

        self.assertIn('"iCloud.com.tadawords.app"', access)
        self.assertIn('"iCloud.com.tadawords.app"', transport)
        self.assertIn('service: String = "com.tadawords.device-voiceprints"', voiceprint)
        self.assertIn('zonePrefix = "TadaProfile-"', persistence)
        self.assertIn('rootPrefix = "profile-root-"', persistence)
        self.assertIn('subscriptionID: "tada-family-private-v2"', transport)
        self.assertIn('subscriptionID: "tada-family-shared-v2"', transport)


if __name__ == "__main__":
    unittest.main()
