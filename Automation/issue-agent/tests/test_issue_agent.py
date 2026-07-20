#!/usr/bin/env python3

import datetime as dt
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).parents[1] / "issue_agent.py"
SPEC = importlib.util.spec_from_file_location("issue_agent", MODULE_PATH)
assert SPEC and SPEC.loader
issue_agent = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(issue_agent)

TEST_MAIN_OID = "9" * 40
TEST_PROTECTION_DIGEST = "8" * 64
TEST_REPO = "owner/repo"


def canonical_issue_refs(*numbers):
    return [f"{TEST_REPO}#{number}" for number in numbers]


def pull_request_events(
    repo, pull_requests, acknowledged, *, closing_issue_refs=()
):
    candidates = [
        {"baseRefOid": TEST_MAIN_OID, **pull_request}
        for pull_request in pull_requests
    ]
    with mock.patch.object(
        issue_agent,
        "live_closing_issue_references",
        return_value=list(closing_issue_refs),
    ):
        return issue_agent.pull_request_events(
            repo,
            candidates,
            acknowledged,
            TEST_MAIN_OID,
            TEST_PROTECTION_DIGEST,
        )


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
        self.assertFalse(
            issue_agent.is_ready(
                issue(4, "Audio", ["agent-ready", "agent-reclaimed"])
            )
        )
        self.assertFalse(
            issue_agent.is_ready(
                issue(5, "Audio", ["agent-ready", "implementation-in-pr"])
            )
        )

    def test_explicit_area_wins_over_keywords(self):
        candidate = issue(
            1,
            "Fix audio wording in Parent Home",
            ["agent-ready", "area:parent"],
        )
        self.assertEqual(issue_agent.infer_area(candidate), "parent")

    def test_area_similarity_does_not_implicitly_group_issues(self):
        candidates = [
            issue(1, "Fix pronunciation", ["agent-ready"]),
            issue(2, "Audio ducking", ["agent-ready"]),
            issue(3, "Parent Gate copy", ["agent-ready"]),
        ]
        batches = issue_agent.suggested_batches(candidates)
        self.assertEqual(
            [batch["issue_numbers"] for batch in batches], [[1], [2], [3]]
        )

    def test_explicit_batch_size_is_bounded(self):
        candidates = [
            issue(
                index,
                f"Audio issue {index}",
                ["agent-ready", "area:audio", "batch:audio-v0.6.8"],
            )
            for index in range(1, 8)
        ]
        batches = issue_agent.suggested_batches(candidates, max_batch_size=5)
        self.assertEqual([len(batch["issue_numbers"]) for batch in batches], [5, 2])

    def test_priority_orders_pickup_before_issue_number(self):
        candidates = [
            issue(1, "Normal", ["agent-ready", "priority:P2"]),
            issue(20, "Urgent", ["agent-ready", "priority:P0"]),
            issue(3, "High", ["agent-ready", "priority:P1"]),
        ]
        batches = issue_agent.suggested_batches(candidates)
        self.assertEqual(
            [batch["issue_numbers"] for batch in batches], [[20], [3], [1]]
        )
        self.assertEqual(
            [batch["priority"] for batch in batches], ["P0", "P1", "P2"]
        )

    def test_priority_can_be_read_from_structured_issue_body(self):
        candidate = issue(
            44,
            "Family Sync",
            ["agent-ready"],
            body="## Priority\n\nP0. This is first.",
        )
        self.assertEqual(issue_agent.issue_priority(candidate), (0, "P0"))

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

    def test_issue_policy_examples_do_not_reserve_versions(self):
        issues = [
            issue(
                38,
                "Cap versions at v1.0.0",
                ["agent-ready"],
                body="Reject v1.0.1, v1.1.0, and v2.0.0.",
            )
        ]
        versions, _ = issue_agent.reserved_versions_and_builds(
            issues, [], "origin/main\norigin/agent/batch-automation-v0.6.7"
        )
        self.assertEqual(versions, {(0, 6, 7)})

    def test_pre_app_store_policy_accepts_versions_below_or_at_ceiling(self):
        policy = {
            "first_public_app_store_release": {
                "status": "incomplete",
                "version_ceiling": "1.0.0",
            }
        }
        issue_agent.enforce_release_ceiling(
            [(0, 9, 9), (0, 10, 0), (1, 0, 0)], policy, context="test"
        )

    def test_pre_app_store_policy_rejects_versions_above_ceiling(self):
        policy = {
            "first_public_app_store_release": {
                "status": "incomplete",
                "version_ceiling": "1.0.0",
            }
        }
        for version in ((1, 0, 1), (1, 1, 0), (2, 0, 0)):
            with self.subTest(version=version), self.assertRaisesRegex(
                issue_agent.CommandError, "exceeds the pre-App Store ceiling"
            ):
                issue_agent.enforce_release_ceiling(
                    [version], policy, context="test"
                )

    def test_released_policy_requires_owner_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release-policy.json"
            path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "first_public_app_store_release": {
                            "status": "released",
                            "version_ceiling": "1.0.0",
                        },
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                issue_agent.CommandError, "released policy state is missing"
            ):
                issue_agent.load_release_policy(path)

    def test_complete_owner_authorized_release_state_lifts_ceiling(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release-policy.json"
            path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "first_public_app_store_release": {
                            "status": "released",
                            "version_ceiling": "1.0.0",
                            "public_app_store_url": "https://apps.apple.com/app/id1",
                            "released_version": "1.0.0",
                            "released_build": "2026999901",
                            "release_manifest": "sha256:example",
                            "owner_authorization": "/release-policy abcdef1",
                        },
                    }
                ),
                encoding="utf-8",
            )
            policy = issue_agent.load_release_policy(path)
            issue_agent.enforce_release_ceiling(
                [(1, 0, 1), (2, 0, 0)], policy, context="test"
            )

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

    def test_standing_authorization_emits_exact_head_candidate_without_comment(self):
        head = "a" * 40
        body = "Closes #85\n"
        candidate = {
            "number": 85,
            "headRefName": "codex/auto-merge-exact-head-v0.7.11",
            "headRefOid": head,
            "baseRefName": "main",
            "labels": [{"name": "awaiting-human-review"}],
            "reviewDecision": "APPROVED",
            "isDraft": False,
            "body": body,
            "url": "https://example.test/pull/86",
        }

        with mock.patch.object(issue_agent, "run_json", side_effect=[[], []]):
            events = pull_request_events(
                TEST_REPO,
                [candidate],
                set(),
                closing_issue_refs=canonical_issue_refs(85),
            )

        closing_refs = canonical_issue_refs(85)
        closing_digest = issue_agent.closing_issue_references_digest(closing_refs)

        self.assertEqual(
            events,
            [
                {
                    "id": (
                        f"auto-merge:85:{head}:{TEST_MAIN_OID}:"
                        f"{issue_agent.pr_body_digest(body)}:{closing_digest}:"
                        f"{TEST_PROTECTION_DIGEST}"
                    ),
                    "type": "automatic_merge_candidate",
                    "pr": 85,
                    "head": head,
                    "base": "main",
                    "base_oid": TEST_MAIN_OID,
                    "body_digest": issue_agent.pr_body_digest(body),
                    "closing_issue_refs": closing_refs,
                    "closing_refs_digest": closing_digest,
                    "protection_digest": TEST_PROTECTION_DIGEST,
                    "url": "https://example.test/pull/86",
                }
            ],
        )

    def test_standing_authorization_never_bypasses_draft_or_blocker(self):
        base = {
            "number": 85,
            "headRefName": "agent/batch-automation-v0.7.11",
            "headRefOid": "b" * 40,
            "baseRefName": "main",
            "labels": [{"name": "awaiting-human-review"}],
            "reviewDecision": "APPROVED",
            "isDraft": False,
            "body": "Closes #85\n",
            "url": "https://example.test/pull/85",
        }
        cases = [
            {**base, "isDraft": True},
            {
                **base,
                "labels": [
                    {"name": "awaiting-human-review"},
                    {"name": "agent-blocked"},
                ],
            },
            {**base, "reviewDecision": "CHANGES_REQUESTED"},
        ]

        for candidate in cases:
            with self.subTest(candidate=candidate), mock.patch.object(
                issue_agent, "run_json", side_effect=[[], []]
            ):
                self.assertEqual(
                    pull_request_events("owner/repo", [candidate], set()),
                    [],
                )

    def test_standing_authorization_allows_a_refs_only_main_pr(self):
        body = "Refs #85\n"
        candidate = {
            "number": 85,
            "headRefName": "agent/batch-automation-v0.7.11",
            "headRefOid": "f" * 40,
            "baseRefName": "main",
            "labels": [{"name": "awaiting-human-review"}],
            "reviewDecision": "APPROVED",
            "isDraft": False,
            "body": body,
            "url": "https://example.test/pull/85",
        }

        with mock.patch.object(issue_agent, "run_json", side_effect=[[], []]):
            events = pull_request_events("owner/repo", [candidate], set())

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["closing_issue_refs"], [])
        self.assertEqual(
            events[0]["closing_refs_digest"],
            issue_agent.closing_issue_references_digest([]),
        )
        self.assertEqual(events[0]["body_digest"], issue_agent.pr_body_digest(body))

    def test_new_head_invalidates_acknowledged_auto_merge_candidate(self):
        old_head = "c" * 40
        new_head = "d" * 40
        body = "Closes #85\n"
        candidate = {
            "number": 85,
            "headRefName": "agent/batch-automation-v0.7.11",
            "headRefOid": new_head,
            "baseRefName": "main",
            "labels": [{"name": "awaiting-human-review"}],
            "reviewDecision": "APPROVED",
            "isDraft": False,
            "body": body,
            "url": "https://example.test/pull/85",
        }

        with mock.patch.object(issue_agent, "run_json", side_effect=[[], []]):
            events = pull_request_events(
                TEST_REPO,
                [candidate],
                {f"auto-merge:85:{old_head}:{issue_agent.pr_body_digest(body)}"},
                closing_issue_refs=canonical_issue_refs(85),
            )

        self.assertEqual(len(events), 1)
        closing_digest = issue_agent.closing_issue_references_digest(
            canonical_issue_refs(85)
        )
        self.assertEqual(
            events[0]["id"],
            (
                f"auto-merge:85:{new_head}:{TEST_MAIN_OID}:"
                f"{issue_agent.pr_body_digest(body)}:{closing_digest}:"
                f"{TEST_PROTECTION_DIGEST}"
            ),
        )
        self.assertEqual(events[0]["head"], new_head)

    def test_owner_merge_command_remains_an_optional_compatible_event(self):
        head = "e" * 40
        body = "Refs #85\n"
        candidate = {
            "number": 85,
            "headRefName": "agent/batch-automation-v0.7.11",
            "headRefOid": head,
            "baseRefName": "main",
            "labels": [],
            "reviewDecision": "APPROVED",
            "isDraft": False,
            "body": body,
            "url": "https://example.test/pull/85",
        }
        comments = [
            {
                "id": 101,
                "body": f"/merge {head}",
                "user": {"login": "owner"},
            }
        ]

        with mock.patch.object(issue_agent, "run_json", side_effect=[[], comments]):
            events = pull_request_events("owner/repo", [candidate], set())

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["type"], "merge_authorized")
        self.assertEqual(events[0]["head"], head)
        self.assertEqual(events[0]["base"], "main")
        self.assertEqual(events[0]["body_digest"], issue_agent.pr_body_digest(body))
        self.assertEqual(events[0]["closing_issue_refs"], [])

    def test_candidate_uses_github_sidebar_closing_refs_not_body_regex(self):
        head = "7" * 40
        body = "Refs #85\n"
        candidate = {
            "number": 85,
            "headRefName": "agent/batch-automation-v0.7.11",
            "headRefOid": head,
            "baseRefName": "main",
            "labels": [{"name": "awaiting-human-review"}],
            "reviewDecision": "APPROVED",
            "isDraft": False,
            "body": body,
            "url": "https://example.test/pull/85",
        }
        sidebar_refs = canonical_issue_refs(85)

        with mock.patch.object(issue_agent, "run_json", side_effect=[[], []]):
            events = pull_request_events(
                TEST_REPO,
                [candidate],
                set(),
                closing_issue_refs=sidebar_refs,
            )

        self.assertEqual(events[0]["closing_issue_refs"], sidebar_refs)
        self.assertEqual(
            events[0]["closing_refs_digest"],
            issue_agent.closing_issue_references_digest(sidebar_refs),
        )

    def test_body_edit_at_same_head_produces_a_new_auto_merge_event(self):
        head = "a" * 40
        candidate = {
            "number": 85,
            "headRefName": "agent/batch-automation-v0.7.11",
            "headRefOid": head,
            "baseRefName": "main",
            "labels": [{"name": "awaiting-human-review"}],
            "reviewDecision": "APPROVED",
            "isDraft": False,
            "body": "Refs #85\n",
            "url": "https://example.test/pull/85",
        }

        with mock.patch.object(issue_agent, "run_json", side_effect=[[], []]):
            first = pull_request_events("owner/repo", [candidate], set())
        updated = {**candidate, "body": "Refs #85\n\nUpdated evidence.\n"}
        with mock.patch.object(issue_agent, "run_json", side_effect=[[], []]):
            second = pull_request_events(
                "owner/repo", [updated], {first[0]["id"]}
            )

        self.assertEqual(len(second), 1)
        self.assertEqual(second[0]["head"], head)
        self.assertNotEqual(second[0]["id"], first[0]["id"])

    def test_standing_authorization_rejects_non_main_base(self):
        candidate = {
            "number": 85,
            "headRefName": "agent/batch-automation-v0.7.11",
            "headRefOid": "f" * 40,
            "baseRefName": "feature/stacked-base",
            "labels": [{"name": "awaiting-human-review"}],
            "reviewDecision": "APPROVED",
            "isDraft": False,
            "body": "Closes #85\n",
            "url": "https://example.test/pull/85",
        }

        with mock.patch.object(issue_agent, "run_json", side_effect=[[], []]):
            self.assertEqual(
                pull_request_events("owner/repo", [candidate], set()),
                [],
            )

    def test_live_pull_request_refetches_body_and_base_for_merge_contract(self):
        with mock.patch.object(issue_agent, "run_json", return_value={}) as run_json:
            issue_agent.live_pull_request("owner/repo", 85)

        fields = run_json.call_args.args[0][-1]
        self.assertIn("body", fields)
        self.assertIn("baseRefName", fields)
        self.assertIn("baseRefOid", fields)
        self.assertIn("statusCheckRollup", fields)


if __name__ == "__main__":
    unittest.main()
