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
