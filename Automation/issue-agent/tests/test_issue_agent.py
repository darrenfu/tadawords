#!/usr/bin/env python3

import datetime as dt
import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "issue_agent.py"
SPEC = importlib.util.spec_from_file_location("issue_agent", MODULE_PATH)
assert SPEC and SPEC.loader
issue_agent = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(issue_agent)


def issue(number, title, labels, body=""):
    return {
        "number": number,
        "title": title,
        "body": body,
        "labels": [{"name": label} for label in labels],
    }


def pull_request(number, area):
    return {
        "number": number,
        "title": f"Active {area} batch",
        "body": "",
        "headRefName": f"agent/batch-{area}-v0.5.{number}",
        "labels": [
            {"name": "agent-claimed"},
            {"name": f"area:{area}"},
        ],
    }


class IssueAgentTests(unittest.TestCase):
    def test_ready_requires_unclaimed_and_unblocked(self):
        self.assertTrue(issue_agent.is_ready(issue(1, "Audio", ["agent-ready"])))
        self.assertFalse(
            issue_agent.is_ready(
                issue(2, "Audio", ["agent-ready", "agent-claimed"])
            )
        )
        self.assertFalse(
            issue_agent.is_ready(
                issue(3, "Audio", ["agent-ready", "agent-blocked"])
            )
        )

    def test_explicit_area_wins_over_keywords(self):
        candidate = issue(
            1,
            "Fix audio wording in Parent Home",
            ["agent-ready", "area:parent"],
        )
        self.assertEqual(issue_agent.infer_area(candidate), "parent")

    def test_keywords_group_related_issues(self):
        candidates = [
            issue(1, "Fix pronunciation", ["agent-ready"]),
            issue(2, "Audio ducking", ["agent-ready"]),
            issue(3, "Parent Gate copy", ["agent-ready"]),
        ]
        batches = issue_agent.suggested_batches(candidates)
        by_area = {batch["area"]: batch["issue_numbers"] for batch in batches}
        self.assertEqual(by_area["audio"], [1, 2])
        self.assertEqual(by_area["parent"], [3])

    def test_batch_size_is_bounded(self):
        candidates = [
            issue(index, f"Audio issue {index}", ["agent-ready", "area:audio"])
            for index in range(1, 8)
        ]
        batches = issue_agent.suggested_batches(candidates, max_batch_size=5)
        self.assertEqual([len(batch["issue_numbers"]) for batch in batches], [5, 2])

    def test_oldest_issue_batch_is_considered_first(self):
        candidates = [
            issue(20, "Audio issue", ["agent-ready", "area:audio"]),
            issue(12, "Kid UI issue", ["agent-ready", "area:kid-ui"]),
        ]
        batches = issue_agent.suggested_batches(candidates)
        self.assertEqual([batch["issue_numbers"] for batch in batches], [[12], [20]])

    def test_unrelated_area_is_claimable_with_open_agent_pr(self):
        batches = issue_agent.suggested_batches(
            [issue(12, "Kid UI", ["agent-ready", "area:kid-ui"])]
        )
        admission = issue_agent.batch_admission(
            batches,
            [pull_request(10, "automation")],
            max_active_batches=2,
        )
        self.assertEqual(
            admission["claimable_batches"][0]["issue_numbers"], [12]
        )
        self.assertEqual(admission["active_areas"], ["automation"])
        self.assertEqual(admission["available_batch_slots"], 1)

    def test_same_area_waits_for_active_pr(self):
        batches = issue_agent.suggested_batches(
            [issue(13, "More audio", ["agent-ready", "area:audio"])]
        )
        admission = issue_agent.batch_admission(
            batches,
            [pull_request(11, "audio")],
            max_active_batches=2,
        )
        self.assertEqual(admission["claimable_batches"], [])
        self.assertEqual(admission["blocked_batches"][0]["reason"], "area_has_active_pr")
        self.assertEqual(admission["blocked_batches"][0]["blocking_prs"], [11])

    def test_global_active_batch_limit_blocks_an_unrelated_area(self):
        batches = issue_agent.suggested_batches(
            [issue(14, "Import polish", ["agent-ready", "area:import"])]
        )
        admission = issue_agent.batch_admission(
            batches,
            [pull_request(10, "automation"), pull_request(12, "kid-ui")],
            max_active_batches=2,
        )
        self.assertEqual(admission["claimable_batches"], [])
        self.assertEqual(
            admission["blocked_batches"][0]["reason"],
            "active_batch_limit_reached",
        )
        self.assertEqual(admission["available_batch_slots"], 0)

    def test_only_one_new_batch_is_claimable_per_poll(self):
        batches = issue_agent.suggested_batches(
            [
                issue(12, "Kid UI", ["agent-ready", "area:kid-ui"]),
                issue(13, "Audio", ["agent-ready", "area:audio"]),
            ]
        )
        admission = issue_agent.batch_admission(
            batches,
            [],
            max_active_batches=2,
        )
        self.assertEqual(
            [batch["issue_numbers"] for batch in admission["claimable_batches"]],
            [[12]],
        )
        self.assertEqual(
            admission["deferred_batches"][0]["reason"],
            "one_new_batch_per_poll",
        )

    def test_agent_pr_detection_accepts_batch_label(self):
        candidate = {
            "headRefName": "feature/custom-name",
            "labels": [{"name": "batch:kid-ui-v0.5.3"}],
        }
        self.assertTrue(issue_agent.is_agent_pull_request(candidate))

    def test_next_patch_skips_all_reservations(self):
        self.assertEqual(
            issue_agent.next_patch_version(
                (0, 5, 0), {(0, 5, 1), (0, 5, 2)}
            ),
            (0, 5, 3),
        )

    def test_reservations_ignore_device_os_versions_in_prose(self):
        issues = [
            issue(
                1,
                "Device handoff",
                ["release:v0.5.2", "build:2026071502"],
                body="iPhone runs iOS 26.5.1 and iPad runs iPadOS 26.5.2.",
            )
        ]
        prs = [
            {
                "title": "[v0.5.2] Device handoff",
                "body": "- New version: `v0.5.2`\n- Build number: `2026071502`\n- Device: iOS 26.5.1",
                "headRefName": "agent/batch-device-v0.5.2",
                "labels": [],
            }
        ]
        versions, builds = issue_agent.reserved_versions_and_builds(
            issues, prs, "origin/v0.5.1"
        )
        self.assertEqual(versions, {(0, 5, 1), (0, 5, 2)})
        self.assertEqual(builds, {"2026071502"})

    def test_build_number_is_monotonic_and_date_based(self):
        today = dt.date(2026, 7, 15)
        self.assertEqual(
            issue_agent.next_build_number(
                "2026071408", {"2026071501"}, now=today
            ),
            "2026071502",
        )

    def test_merge_command_must_name_current_sha(self):
        current = "abcdef1234567890"
        match = issue_agent.MERGE_RE.fullmatch("/merge abcdef1")
        self.assertIsNotNone(match)
        assert match
        self.assertTrue(issue_agent.sha_matches(match.group(1), current))
        self.assertIsNone(issue_agent.MERGE_RE.fullmatch("/merge"))
        self.assertFalse(issue_agent.sha_matches("1234567", current))


if __name__ == "__main__":
    unittest.main()
