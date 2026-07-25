import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


class ReleaseContentInventoryTests(unittest.TestCase):
    def setUp(self):
        self.repository_root = Path(__file__).resolve().parents[3]
        self.verifier = (
            self.repository_root / "Scripts" / "verify-release-content-inventory.sh"
        )

    def test_parent_notice_route_accepts_additional_grouped_destinations(self):
        result = self.run_route_verifier(
            """
            enum GuardianDestination {
                var parentSectionForBack: GuardianParentSection? {
                    switch self {
                    case .speechPermissions, .familySync, .thirdPartyNotices:
                        .appAndFamily
                    case .dashboard:
                        nil
                    }
                }
            }
            """
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("route verified", result.stdout)

    def test_parent_notice_route_rejects_a_removed_notice_destination(self):
        result = self.run_route_verifier(
            """
            enum GuardianDestination {
                var parentSectionForBack: GuardianParentSection? {
                    switch self {
                    case .speechPermissions, .familySync:
                        .appAndFamily
                    case .thirdPartyNotices, .dashboard:
                        nil
                    }
                }
            }
            """
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Third-Party Notices is not routed back to App & Family",
            result.stderr,
        )

    def test_inventory_records_resolved_human_evidence(self):
        inventory = (
            self.repository_root / "Docs" / "APP_STORE_CONTENT_RIGHTS.md"
        ).read_text(encoding="utf-8")

        self.assertIn(
            "No unresolved content-rights evidence blocker remains",
            inventory,
        )
        self.assertIn("issues/33#issuecomment-5066488733", inventory)
        self.assertIn(
            "85a98c0275800457e53d8607312650a6621afd3ce2e2f165c0c6fa2ab47ee73f",
            inventory,
        )
        self.assertNotIn("Missing; #33", inventory)
        self.assertNotIn("rights-chain confirmation is blocked by #33", inventory)

    def run_route_verifier(self, source: str) -> subprocess.CompletedProcess[str]:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".swift", encoding="utf-8"
        ) as fixture:
            fixture.write(textwrap.dedent(source))
            fixture.flush()
            return subprocess.run(
                [
                    str(self.verifier),
                    "--verify-parent-notice-route",
                    fixture.name,
                ],
                check=False,
                capture_output=True,
                text=True,
            )


if __name__ == "__main__":
    unittest.main()
