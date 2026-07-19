#!/usr/bin/env python3

import copy
import hashlib
import importlib.util
import json
import subprocess
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).parents[1] / "issue_agent.py"
SPEC = importlib.util.spec_from_file_location("issue_agent_scheduler", MODULE_PATH)
assert SPEC and SPEC.loader
issue_agent = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(issue_agent)


def issue(number: int, labels: list[str] | None = None) -> dict:
    return {
        "number": number,
        "title": f"Issue {number}",
        "body": "",
        "state": "OPEN",
        "labels": [{"name": label} for label in (labels or ["agent-ready"])],
        "updatedAt": "2026-07-18T12:00:00Z",
        "url": f"https://example.test/issues/{number}",
    }


class PullRequestCoverageTests(unittest.TestCase):
    def _coverage(
        self,
        *,
        state: str,
        timeline: list[dict] | None = None,
        ancestor: bool = True,
        issue_labels: list[str] | None = None,
    ) -> list[dict]:
        candidate = issue(47, issue_labels)
        merged_at = "2026-07-18T10:00:00Z"
        pull_request = {
            "number": 81,
            "state": state,
            "mergedAt": merged_at if state == "MERGED" else None,
            "mergeCommit": {"oid": "a" * 40} if state == "MERGED" else None,
            "baseRefName": "main",
            "headRefName": "agent/issue-47",
            "headRefOid": "b" * 40,
            "url": "https://example.test/pull/81",
        }

        def fake_run_json(command, **_kwargs):
            if command[:3] == ["gh", "issue", "view"]:
                return {"closedByPullRequestsReferences": [{"number": 81}]}
            if command[:3] == ["gh", "pr", "view"]:
                return pull_request
            if command[:3] == ["gh", "api", "graphql"]:
                return {
                    "data": {
                        "repository": {
                            "issue": {
                                "timelineItems": {"nodes": timeline or []}
                            }
                        }
                    }
                }
            raise AssertionError(f"unexpected command: {command}")

        with (
            mock.patch.object(issue_agent, "run_json", side_effect=fake_run_json),
            mock.patch.object(issue_agent, "git_is_ancestor", return_value=ancestor),
            mock.patch.object(issue_agent, "issue_comments", return_value=[]),
        ):
            return issue_agent.exact_pull_request_coverage(
                "owner/repo", candidate, Path("/control")
            )

    def test_exact_merged_pr_on_main_ancestor_produces_close_action(self):
        coverage = self._coverage(state="MERGED")

        self.assertEqual(len(coverage), 1)
        self.assertEqual(coverage[0]["type"], "merged_pull_request")
        self.assertEqual(coverage[0]["action"], "close_stale_issue")
        self.assertEqual(coverage[0]["pr"], 81)
        self.assertTrue(issue_agent.coverage_protects_issue(coverage))

    def test_reopen_after_merge_never_produces_close_action(self):
        coverage = self._coverage(
            state="MERGED",
            timeline=[
                {
                    "__typename": "ReopenedEvent",
                    "createdAt": "2026-07-18T11:00:00Z",
                    "actor": {"login": "owner"},
                }
            ],
        )

        self.assertEqual(coverage[0]["action"], "none")
        self.assertEqual(coverage[0]["reason"], "issue_reopened_after_merge")
        self.assertFalse(issue_agent.coverage_protects_issue(coverage))

    def test_open_exact_pr_produces_link_action(self):
        coverage = self._coverage(state="OPEN")

        self.assertEqual(
            coverage,
            [
                {
                    "type": "open_pull_request",
                    "action": "link_open_pull_request",
                    "pr": 81,
                    "head": "b" * 40,
                    "url": "https://example.test/pull/81",
                }
            ],
        )
        self.assertTrue(issue_agent.coverage_protects_issue(coverage))

    def test_fuzzy_issue_mentions_are_not_exact_closing_references(self):
        prose = "Related to #47; discusses #47; see #470."

        self.assertEqual(issue_agent.exact_closing_issue_numbers(prose), set())
        self.assertNotIn(
            47,
            issue_agent.exact_closing_issue_numbers("Closes #470"),
        )

    def test_branch_marker_and_explicit_issue_branch_are_detected(self):
        candidate = issue(47)
        marker = (
            "<!-- tada-issue-agent:coverage:branch-agent/issue-47 -->\n"
            "Implementation is on branch `agent/issue-47` at `abcdef1234567`."
        )
        completed = subprocess.CompletedProcess(
            args=["git"], returncode=0, stdout="abcdef1234567890\n", stderr=""
        )
        with (
            mock.patch.object(
                issue_agent,
                "issue_comments",
                return_value=[
                    {
                        "body": marker,
                        "html_url": "https://comment/1",
                        "user": {"login": "owner"},
                    }
                ],
            ),
            mock.patch.object(issue_agent.subprocess, "run", return_value=completed),
        ):
            marker_coverage = issue_agent.branch_coverage_from_comments(
                "owner/repo", candidate, Path("/control")
            )

        self.assertEqual(marker_coverage[0]["branch"], "agent/issue-47")

        def fake_run(command, **_kwargs):
            if command[:2] == ["git", "for-each-ref"]:
                return (
                    f"origin/main {'0' * 40}\n"
                    f"origin/agent/issue-47 {'1' * 40}\n"
                    f"origin/agent/issue-470 {'2' * 40}\n"
                    f"origin/agent/leases/batch-47 {'3' * 40}\n"
                )
            if command[:2] == ["git", "log"]:
                return "No closing reference here\n"
            if command[:2] == ["git", "rev-list"]:
                return "1\n" if "issue-47" in command[-1] else "0\n"
            raise AssertionError(f"unexpected command: {command}")

        with mock.patch.object(issue_agent, "run", side_effect=fake_run):
            explicit = issue_agent.explicit_remote_branch_coverage(
                47, Path("/control")
            )

        self.assertEqual([entry["branch"] for entry in explicit], ["agent/issue-47"])


class ReservationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.release_policy = MODULE_PATH.with_name("release-policy.json")
        self.snapshot = {
            "claimable_batches": [{"issue_numbers": [47]}],
            "events": [],
            "release_policy": {
                "sha256": hashlib.sha256(self.release_policy.read_bytes()).hexdigest()
            },
            "version_context": {"suggested_next_patch": "v0.6.8"},
        }
        self.args = Namespace(
            snapshot="/snapshot.json",
            repo="owner/repo",
            control_repo="/control",
            release_policy=str(self.release_policy),
        )

    def test_reserve_rechecks_live_coverage_before_any_claim_mutation(self):
        commands: list[list[str]] = []

        def fake_run(command, **_kwargs):
            commands.append(command)
            return ""

        with (
            mock.patch.object(
                issue_agent, "read_snapshot", return_value=copy.deepcopy(self.snapshot)
            ),
            mock.patch.object(issue_agent, "run", side_effect=fake_run),
            mock.patch.object(issue_agent, "live_issue", return_value=issue(47)),
            mock.patch.object(
                issue_agent,
                "coverage_for_issue",
                return_value=[{"type": "open_pull_request", "pr": 81}],
            ),
        ):
            with self.assertRaisesRegex(
                issue_agent.CommandError, "already has PR or remote-branch coverage"
            ):
                issue_agent.reserve(self.args)

        self.assertFalse(
            any(command[:3] == ["gh", "issue", "edit"] for command in commands)
        )

    def test_two_unique_lease_pushes_have_only_one_winner(self):
        push_results = iter(
            [
                subprocess.CompletedProcess(
                    args=["git"], returncode=0, stdout="", stderr=""
                ),
                subprocess.CompletedProcess(
                    args=["git"],
                    returncode=1,
                    stdout="",
                    stderr="non-fast-forward",
                ),
                subprocess.CompletedProcess(
                    args=["git"],
                    returncode=0,
                    stdout=(
                        f"{'a' * 40}\trefs/heads/agent/leases/batch-47\n"
                    ),
                    stderr="",
                ),
            ]
        )
        push_commands: list[list[str]] = []

        def fake_subprocess_run(command, **_kwargs):
            push_commands.append(command)
            return next(push_results)

        first_commit = "a" * 40
        second_commit = "c" * 40

        def fake_run(command, **_kwargs):
            if command[:3] == ["git", "ls-remote", "--heads"]:
                return f"{first_commit}\trefs/heads/agent/leases/batch-47\n"
            return ""

        with (
            mock.patch.object(
                issue_agent,
                "read_snapshot",
                side_effect=lambda _path: copy.deepcopy(self.snapshot),
            ),
            mock.patch.object(issue_agent, "write_snapshot"),
            mock.patch.object(issue_agent, "run", side_effect=fake_run),
            mock.patch.object(issue_agent, "live_issue", return_value=issue(47)),
            mock.patch.object(issue_agent, "coverage_for_issue", return_value=[]),
            mock.patch.object(
                issue_agent,
                "create_lease_commit",
                side_effect=[
                    (first_commit, "0" * 40),
                    (second_commit, "0" * 40),
                ],
            ),
            mock.patch.object(issue_agent, "comment_with_marker"),
            mock.patch.object(
                issue_agent.subprocess, "run", side_effect=fake_subprocess_run
            ),
        ):
            first = issue_agent.reserve(self.args)
            with self.assertRaisesRegex(
                issue_agent.CommandError, "remote lease was not acquired"
            ):
                issue_agent.reserve(self.args)

        self.assertTrue(first["reserved"])
        lease_pushes = [command for command in push_commands if command[:2] == ["git", "push"]]
        self.assertEqual(len(lease_pushes), 2)
        self.assertIn(first_commit, lease_pushes[0][-1])
        self.assertIn(second_commit, lease_pushes[1][-1])
        self.assertEqual(
            lease_pushes[0][-1].split(":", 1)[1],
            lease_pushes[1][-1].split(":", 1)[1],
        )


class ReleaseAndAcknowledgementTests(unittest.TestCase):
    def test_reconcile_reports_and_releases_preexisting_blocked_claim(self):
        snapshot = {
            "reconciliation_actions": [
                {
                    "issue": 47,
                    "action": "release_blocked_claim",
                    "type": "blocked_claim",
                    "blocking_labels": ["agent-blocked"],
                    "updated_at": "2026-07-18T16:00:00Z",
                }
            ]
        }
        blocked = issue(
            47, ["agent-ready", "agent-claimed", "agent-reclaimed", "agent-blocked"]
        )
        removed: list[int] = []
        comments: list[tuple] = []
        args = Namespace(
            snapshot="/snapshot.json", repo="owner/repo", control_repo="/control"
        )
        with (
            mock.patch.object(issue_agent, "read_snapshot", return_value=snapshot),
            mock.patch.object(issue_agent, "run", return_value=""),
            mock.patch.object(issue_agent, "live_issue", side_effect=[blocked, blocked]),
            mock.patch.object(
                issue_agent, "lease_ownership_from_comments", return_value=None
            ),
            mock.patch.object(
                issue_agent,
                "remove_claim_labels",
                side_effect=lambda _repo, value: removed.append(value["number"]),
            ),
            mock.patch.object(
                issue_agent,
                "comment_with_marker",
                side_effect=lambda *values: comments.append(values),
            ),
        ):
            result = issue_agent.reconcile(args)

        self.assertEqual(result["results"][0]["result"], "released_blocked_claim")
        self.assertEqual(removed, [47])
        self.assertIn("agent-blocked", comments[0][3])

    def test_lease_companions_are_derived_only_from_canonical_batch_ref(self):
        self.assertEqual(
            issue_agent.lease_issue_numbers("agent/leases/batch-47-48", 47),
            [47, 48],
        )
        self.assertEqual(
            issue_agent.lease_issue_numbers("agent/custom-branch", 47), [47]
        )

    def test_blocker_release_reports_then_removes_claims_and_lease_durably(self):
        lease_commit = "d" * 40
        lease_ref = "refs/heads/agent/leases/batch-47-48"
        reservation = {
            "token": "token-1",
            "issue_numbers": [47, 48],
            "lease_ref": lease_ref,
            "lease_commit": lease_commit,
        }
        claimed = ["agent-ready", "agent-claimed", "agent-reclaimed"]
        commands: list[list[str]] = []
        comments: list[tuple] = []

        def fake_run(command, **_kwargs):
            commands.append(command)
            if command[:3] == ["git", "ls-remote", "--heads"]:
                return f"{lease_commit}\t{lease_ref}\n"
            return ""

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            snapshot_path = root / "snapshot.json"
            snapshot_path.write_text(
                json.dumps({"reservation": reservation}), encoding="utf-8"
            )
            reason_path = root / "blocker.md"
            reason_path.write_text(
                "CloudKit capability needs the owner's paid-team approval.",
                encoding="utf-8",
            )
            args = Namespace(
                snapshot=str(snapshot_path),
                repo="owner/repo",
                control_repo=str(root),
                issue=47,
                reason_file=str(reason_path),
            )

            with (
                mock.patch.object(
                    issue_agent,
                    "live_issue",
                    side_effect=[issue(47, claimed), issue(47, claimed), issue(48, claimed)],
                ),
                mock.patch.object(issue_agent, "run", side_effect=fake_run),
                mock.patch.object(
                    issue_agent,
                    "comment_with_marker",
                    side_effect=lambda *values: comments.append(values),
                ),
            ):
                release_record = issue_agent.release(args)

            remove_commands = [
                command
                for command in commands
                if "--remove-label" in command
            ]
            self.assertEqual(len(remove_commands), 4)
            self.assertEqual(
                {(command[3], command[-1]) for command in remove_commands},
                {
                    ("47", "agent-claimed"),
                    ("47", "agent-reclaimed"),
                    ("48", "agent-claimed"),
                    ("48", "agent-reclaimed"),
                },
            )
            lease_deletes = [
                command
                for command in commands
                if command[:2] == ["git", "push"]
                and f":{lease_ref}" in command
            ]
            self.assertEqual(len(lease_deletes), 1)
            self.assertIn("CloudKit capability", comments[0][3])

            released_blocker = issue(47, ["agent-ready", "agent-blocked"])
            released_companion = issue(48, ["agent-ready"])
            with (
                mock.patch.object(
                    issue_agent,
                    "live_issue",
                    side_effect=[released_blocker, released_companion],
                ),
                mock.patch.object(
                    issue_agent,
                    "issue_comments",
                    return_value=[
                        {
                            "body": f"<!-- {release_record['marker']} -->\nBlocker report",
                            "user": {"login": "owner"},
                        }
                    ],
                ),
                mock.patch.object(issue_agent, "run", return_value=""),
            ):
                self.assertTrue(
                    issue_agent.release_has_durable_outcome(
                        "owner/repo", release_record, reservation, root
                    )
                )

    def test_no_durable_outcome_refuses_acknowledgement(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            snapshot = root / "snapshot.json"
            snapshot.write_text(
                json.dumps(
                    {
                        "events": [
                            {
                                "id": "comment:100",
                                "type": "resume_requested",
                                "pr": 81,
                                "head": "a" * 40,
                            }
                        ],
                        "claimable_batches": [],
                    }
                ),
                encoding="utf-8",
            )
            state = root / "state"
            args = Namespace(
                snapshot=str(snapshot),
                state_dir=str(state),
                repo="owner/repo",
                control_repo=str(root),
                require_durable_outcome=True,
            )

            with (
                mock.patch.object(issue_agent, "run", return_value=""),
                mock.patch.object(
                    issue_agent, "event_has_durable_outcome", return_value=False
                ),
            ):
                with self.assertRaisesRegex(
                    issue_agent.CommandError, "events lack a durable GitHub outcome"
                ):
                    issue_agent.acknowledge(args)

            self.assertFalse((state / "state.json").exists())


class PriorityTests(unittest.TestCase):
    def test_p0_is_picked_before_lower_priority_even_with_higher_issue_number(self):
        batches = issue_agent.suggested_batches(
            [
                issue(1, ["agent-ready", "priority:P3"]),
                issue(90, ["agent-ready", "priority:P0"]),
                issue(2, ["agent-ready", "priority:P1"]),
            ]
        )

        self.assertEqual(
            [(batch["priority"], batch["issue_numbers"]) for batch in batches],
            [("P0", [90]), ("P1", [2]), ("P3", [1])],
        )


if __name__ == "__main__":
    unittest.main()
