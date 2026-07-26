#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[3]
SCRIPT = REPOSITORY_ROOT / "Scripts" / "delivery-checks.py"
SPEC = importlib.util.spec_from_file_location("delivery_checks", SCRIPT)
assert SPEC and SPEC.loader
delivery_checks = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = delivery_checks
SPEC.loader.exec_module(delivery_checks)


class DeliveryCheckPlanTests(unittest.TestCase):
    def names(self, mode: str, paths: list[str], test_filter: str | None = None):
        return [
            step.name
            for step in delivery_checks.build_plan(mode, paths, test_filter)
        ]

    def test_docs_policy_change_runs_issue_agent_contract_only(self):
        self.assertEqual(
            self.names("pr", ["AGENTS.md", "Docs/DEVELOPMENT_PIPELINE.md"]),
            ["issue-agent-tests"],
        )

    def test_swift_pr_does_not_run_unrelated_delivery_suites(self):
        self.assertEqual(
            self.names("pr", ["Sources/TadaWordsDomain/PracticeSettings.swift"]),
            ["lint", "swift-tests"],
        )

    def test_focused_swift_change_requires_filter(self):
        with self.assertRaises(delivery_checks.CheckPlanError):
            self.names("changed", ["Sources/TadaWordsDomain/PracticeSettings.swift"])
        self.assertEqual(
            self.names(
                "changed",
                ["Sources/TadaWordsDomain/PracticeSettings.swift"],
                "PracticeSettingsTests",
            ),
            ["lint", "focused-swift-tests"],
        )

    def test_release_paths_run_only_release_preflight_tests(self):
        self.assertEqual(
            self.names(
                "pr",
                ["Automation/release-preflight/tests/test_release_candidate_preflight.py"],
            ),
            ["release-preflight-tests"],
        )

    def test_rc_always_runs_the_full_gate(self):
        self.assertEqual(
            self.names("rc", []),
            [
                "lint",
                "swift-tests",
                "issue-agent-tests",
                "release-preflight-tests",
            ],
        )


if __name__ == "__main__":
    unittest.main()
