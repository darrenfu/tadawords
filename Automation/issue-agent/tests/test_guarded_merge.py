#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from argparse import Namespace
from contextlib import ExitStack
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).parents[1] / "issue_agent.py"
SPEC = importlib.util.spec_from_file_location("issue_agent_guarded", MODULE_PATH)
assert SPEC and SPEC.loader
issue_agent = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(issue_agent)

HEAD = "a" * 40
BASE = "b" * 40
MERGE = "c" * 40
LEASE = "e" * 40
BODY = "Closes #85\n"
REPO = "owner/repo"
CLOSING_REFS = [f"{REPO}#85"]
CLOSING_REFS_DIGEST = issue_agent.closing_issue_references_digest(CLOSING_REFS)


def protection(**overrides):
    value = {
        "required_status_checks": {
            "strict": True,
            "contexts": [issue_agent.EXACT_HEAD_STATUS_CONTEXT],
        },
        "enforce_admins": {"enabled": True},
        "required_pull_request_reviews": {"required_approving_review_count": 0},
        "required_linear_history": {"enabled": True},
        "required_conversation_resolution": {"enabled": True},
        "allow_force_pushes": {"enabled": False},
        "allow_deletions": {"enabled": False},
    }
    value.update(overrides)
    return value


PROTECTION_DIGEST = issue_agent.branch_protection_contract(protection())


def event(**overrides):
    value = {
        "id": (
            f"auto-merge:86:{HEAD}:{BASE}:body:"
            f"{CLOSING_REFS_DIGEST}:{PROTECTION_DIGEST}"
        ),
        "type": "automatic_merge_candidate",
        "pr": 86,
        "head": HEAD,
        "base": "main",
        "base_oid": BASE,
        "body_digest": issue_agent.pr_body_digest(BODY),
        "closing_issue_refs": CLOSING_REFS,
        "closing_refs_digest": CLOSING_REFS_DIGEST,
        "protection_digest": PROTECTION_DIGEST,
        "url": "https://example.test/pull/86",
    }
    value.update(overrides)
    return value


def pull_request(*, exact_gate=False, **overrides):
    checks = []
    if exact_gate:
        checks.append(
            {
                "__typename": "StatusContext",
                "context": issue_agent.EXACT_HEAD_STATUS_CONTEXT,
                "state": "SUCCESS",
            }
        )
    value = {
        "number": 86,
        "state": "OPEN",
        "headRefOid": HEAD,
        "baseRefName": "main",
        "baseRefOid": BASE,
        "body": BODY,
        "labels": [{"name": "awaiting-human-review"}],
        "isDraft": False,
        "reviewDecision": "APPROVED",
        "mergeable": "MERGEABLE",
        "mergeStateStatus": "CLEAN" if exact_gate else "BLOCKED",
        "statusCheckRollup": checks,
        "mergeCommit": None,
        "url": "https://example.test/pull/86",
    }
    value.update(overrides)
    return value


class ProtectionContractTests(unittest.TestCase):
    def test_valid_contract_has_stable_digest(self):
        self.assertEqual(
            issue_agent.branch_protection_contract(protection()),
            PROTECTION_DIGEST,
        )
        self.assertEqual(len(PROTECTION_DIGEST), 64)

    def test_missing_server_side_guard_fails_closed(self):
        cases = [
            {"required_status_checks": {"strict": False, "contexts": []}},
            {"required_status_checks": {"strict": True, "contexts": []}},
            {"enforce_admins": {"enabled": False}},
            {"required_pull_request_reviews": None},
            {"required_linear_history": {"enabled": False}},
            {"required_conversation_resolution": {"enabled": False}},
            {"allow_force_pushes": {"enabled": True}},
            {"allow_deletions": {"enabled": True}},
        ]
        for override in cases:
            with self.subTest(override=override), self.assertRaises(
                issue_agent.CommandError
            ):
                issue_agent.branch_protection_contract(protection(**override))

    def test_digest_changes_with_status_app_and_review_requirements(self):
        app_one = protection(
            required_status_checks={
                "strict": True,
                "contexts": [],
                "checks": [
                    {
                        "context": issue_agent.EXACT_HEAD_STATUS_CONTEXT,
                        "app_id": 101,
                    }
                ],
            }
        )
        app_two = protection(
            required_status_checks={
                "strict": True,
                "contexts": [],
                "checks": [
                    {
                        "context": issue_agent.EXACT_HEAD_STATUS_CONTEXT,
                        "app_id": 202,
                    }
                ],
            }
        )
        review_changed = protection(
            required_pull_request_reviews={
                "required_approving_review_count": 1,
                "dismiss_stale_reviews": True,
                "require_code_owner_reviews": True,
                "require_last_push_approval": True,
            }
        )

        self.assertNotEqual(
            issue_agent.branch_protection_contract(app_one),
            issue_agent.branch_protection_contract(app_two),
        )
        self.assertNotEqual(
            PROTECTION_DIGEST,
            issue_agent.branch_protection_contract(review_changed),
        )

    def test_pull_request_bypass_actor_is_rejected_not_omitted_from_digest(self):
        for kind in ("users", "teams", "apps"):
            reviews = {
                "required_approving_review_count": 0,
                "bypass_pull_request_allowances": {
                    "users": [],
                    "teams": [],
                    "apps": [],
                    kind: [{"slug": "bypass-actor"}],
                },
            }
            with self.subTest(kind=kind), self.assertRaisesRegex(
                issue_agent.CommandError, "bypass actors"
            ):
                issue_agent.branch_protection_contract(
                    protection(required_pull_request_reviews=reviews)
                )

    def test_exact_gate_must_be_success_and_duplicates_all_pass(self):
        for state in ("PENDING", "FAILURE", "ERROR"):
            with self.subTest(state=state):
                candidate = pull_request(
                    statusCheckRollup=[
                        {
                            "context": issue_agent.EXACT_HEAD_STATUS_CONTEXT,
                            "state": state,
                        }
                    ]
                )
                self.assertFalse(
                    issue_agent.pull_request_checks_pass(
                        candidate, require_exact_gate=True
                    )
                )
        duplicate = pull_request(
            statusCheckRollup=[
                {
                    "context": issue_agent.EXACT_HEAD_STATUS_CONTEXT,
                    "state": "SUCCESS",
                },
                {
                    "name": issue_agent.EXACT_HEAD_STATUS_CONTEXT,
                    "status": "COMPLETED",
                    "conclusion": "FAILURE",
                },
            ]
        )
        self.assertFalse(
            issue_agent.pull_request_checks_pass(
                duplicate, require_exact_gate=True
            )
        )

    def test_latest_review_from_same_reviewer_wins(self):
        reviews = [
            {
                "id": 1,
                "commit_id": HEAD,
                "state": "CHANGES_REQUESTED",
                "user": {"login": "reviewer"},
            },
            {
                "id": 2,
                "commit_id": HEAD,
                "state": "APPROVED",
                "user": {"login": "reviewer"},
            },
        ]
        self.assertEqual(
            issue_agent.current_head_changes_requested_review_ids(reviews, HEAD),
            set(),
        )

    def test_candidate_requires_per_pr_base_oid_to_match_fresh_main(self):
        candidate = {
            **pull_request(),
            "headRefName": "agent/batch-automation-v0.7.11",
        }
        with (
            mock.patch.object(
                issue_agent,
                "live_closing_issue_references",
                return_value=CLOSING_REFS,
            ),
            mock.patch.object(issue_agent, "run_json", side_effect=[[], []]),
        ):
            events = issue_agent.pull_request_events(
                REPO, [candidate], set(), "d" * 40, PROTECTION_DIGEST
            )
        self.assertEqual(events, [])

    def test_base_oid_change_creates_a_distinct_candidate_identity(self):
        first = {
            **pull_request(),
            "headRefName": "agent/batch-automation-v0.7.11",
        }
        second_base = "d" * 40
        second = {**first, "baseRefOid": second_base}
        with (
            mock.patch.object(
                issue_agent,
                "live_closing_issue_references",
                return_value=CLOSING_REFS,
            ),
            mock.patch.object(issue_agent, "run_json", side_effect=[[], []]),
        ):
            first_events = issue_agent.pull_request_events(
                REPO, [first], set(), BASE, PROTECTION_DIGEST
            )
        with (
            mock.patch.object(
                issue_agent,
                "live_closing_issue_references",
                return_value=CLOSING_REFS,
            ),
            mock.patch.object(issue_agent, "run_json", side_effect=[[], []]),
        ):
            second_events = issue_agent.pull_request_events(
                REPO, [second], set(), second_base, PROTECTION_DIGEST
            )
        self.assertNotEqual(first_events[0]["id"], second_events[0]["id"])

    def test_live_candidate_drift_fails_closed(self):
        cases = [
            pull_request(headRefOid="d" * 40),
            pull_request(baseRefOid="d" * 40),
            pull_request(body="Closes #85\nCloses #99\n"),
            pull_request(labels=[{"name": "agent-blocked"}]),
            pull_request(isDraft=True),
            pull_request(reviewDecision="CHANGES_REQUESTED"),
            pull_request(mergeable="CONFLICTING"),
        ]
        for candidate in cases:
            with self.subTest(candidate=candidate), mock.patch.object(
                issue_agent, "git_is_ancestor", return_value=True
            ):
                with self.assertRaises(issue_agent.CommandError):
                    issue_agent.validate_live_merge_candidate(
                        event(),
                        candidate,
                        [],
                        CLOSING_REFS,
                        PROTECTION_DIGEST,
                        BASE,
                        Path("/control"),
                        require_exact_gate=False,
                    )

    def test_live_candidate_rejects_canonical_closing_reference_drift(self):
        with mock.patch.object(issue_agent, "git_is_ancestor", return_value=True):
            with self.assertRaisesRegex(
                issue_agent.CommandError, "canonical closing references changed"
            ):
                issue_agent.validate_live_merge_candidate(
                    event(),
                    pull_request(),
                    [],
                    [f"{REPO}#99"],
                    PROTECTION_DIGEST,
                    BASE,
                    Path("/control"),
                    require_exact_gate=False,
                )


class CanonicalClosingIssueReferenceTests(unittest.TestCase):
    @staticmethod
    def page(nodes, *, has_next=False, cursor=None):
        return {
            "data": {
                "repository": {
                    "pullRequest": {
                        "closingIssuesReferences": {
                            "nodes": nodes,
                            "pageInfo": {
                                "hasNextPage": has_next,
                                "endCursor": cursor,
                            },
                        }
                    }
                }
            }
        }

    def test_graphql_closing_references_paginate_and_canonicalize(self):
        pages = [
            self.page(
                [
                    {
                        "number": 99,
                        "repository": {"nameWithOwner": "OWNER/REPO"},
                    }
                ],
                has_next=True,
                cursor="cursor-1",
            ),
            self.page(
                [
                    {
                        "number": 85,
                        "repository": {"nameWithOwner": "owner/repo"},
                    },
                    {
                        "number": 99,
                        "repository": {"nameWithOwner": "owner/repo"},
                    },
                ]
            ),
        ]
        with mock.patch.object(
            issue_agent, "run_json", side_effect=pages
        ) as run_json:
            refs = issue_agent.live_closing_issue_references(REPO, 86)

        self.assertEqual(refs, [f"{REPO}#85", f"{REPO}#99"])
        first_command = run_json.call_args_list[0].args[0]
        second_command = run_json.call_args_list[1].args[0]
        self.assertFalse(any(value.startswith("after=") for value in first_command))
        self.assertIn("after=cursor-1", second_command)

    def test_graphql_closing_reference_rejects_cross_repo_target(self):
        response = self.page(
            [
                {
                    "number": 85,
                    "repository": {"nameWithOwner": "other/repo"},
                }
            ]
        )
        with mock.patch.object(issue_agent, "run_json", return_value=response):
            with self.assertRaisesRegex(
                issue_agent.CommandError, "cross-repository"
            ):
                issue_agent.live_closing_issue_references(REPO, 86)

    def test_graphql_pagination_fails_closed_when_cursor_does_not_advance(self):
        page = self.page([], has_next=True, cursor="stuck")
        with mock.patch.object(issue_agent, "run_json", side_effect=[page, page]):
            with self.assertRaisesRegex(
                issue_agent.CommandError, "pagination did not advance"
            ):
                issue_agent.live_closing_issue_references(REPO, 86)

    def test_graphql_partial_or_malformed_page_fails_closed(self):
        valid = self.page([])
        cases = [
            [],
            {**valid, "errors": [{"message": "partial timeout"}]},
            {
                "data": {
                    "repository": {
                        "pullRequest": {
                            "closingIssuesReferences": {
                                "nodes": None,
                                "pageInfo": {
                                    "hasNextPage": False,
                                    "endCursor": None,
                                },
                            }
                        }
                    }
                }
            },
            {
                "data": {
                    "repository": {
                        "pullRequest": {
                            "closingIssuesReferences": {
                                "nodes": [],
                                "pageInfo": {"endCursor": None},
                            }
                        }
                    }
                }
            },
        ]
        for response in cases:
            with self.subTest(response=response), mock.patch.object(
                issue_agent, "run_json", return_value=response
            ):
                with self.assertRaises(issue_agent.CommandError):
                    issue_agent.live_closing_issue_references(REPO, 86)


class GuardedMergeTests(unittest.TestCase):
    def args(self, snapshot, state_dir):
        return Namespace(
            snapshot=str(snapshot),
            state_dir=str(state_dir),
            repo=REPO,
            control_repo="/control",
            event_id=event()["id"],
            confirm_gates_head=HEAD,
        )

    def write_snapshot(self, root):
        path = Path(root) / "snapshot.json"
        path.write_text(
            json.dumps(
                {"repo": "owner/repo", "events": [event()]}, sort_keys=True
            ),
            encoding="utf-8",
        )
        return path

    def common_context(self, *, second_base=BASE):
        stack = ExitStack()
        stack.enter_context(
            mock.patch.object(
                issue_agent, "fetch_origin", side_effect=[BASE, BASE, second_base]
            )
        )
        stack.enter_context(
            mock.patch.object(
                issue_agent,
                "live_pull_request",
                side_effect=[
                    pull_request(),
                    pull_request(),
                    pull_request(exact_gate=True),
                ],
            )
        )
        stack.enter_context(
            mock.patch.object(
                issue_agent, "live_branch_protection", return_value=protection()
            )
        )
        stack.enter_context(
            mock.patch.object(
                issue_agent, "live_pull_request_reviews", return_value=[]
            )
        )
        stack.enter_context(
            mock.patch.object(
                issue_agent,
                "live_closing_issue_references",
                return_value=CLOSING_REFS,
            )
        )
        stack.enter_context(
            mock.patch.object(issue_agent, "git_is_ancestor", return_value=True)
        )
        stack.enter_context(
            mock.patch.object(issue_agent, "acquire_merge_critical_lease")
        )
        stack.enter_context(
            mock.patch.object(
                issue_agent, "create_merge_lease_commit", return_value=LEASE
            )
        )
        return stack

    def test_guarded_merge_uses_exact_sha_squash_without_admin(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = self.write_snapshot(directory)
            state_dir = Path(directory) / "state"
            status_response = {"state": "success"}
            merge_response = {"merged": True, "sha": MERGE}
            with self.common_context(), mock.patch.object(
                issue_agent, "run_json", side_effect=[status_response, merge_response]
            ) as run_json:
                result = issue_agent.guarded_merge(self.args(snapshot, state_dir))

            merge_command = run_json.call_args_list[-1].args[0]
            self.assertIn("PUT", merge_command)
            self.assertIn(f"sha={HEAD}", merge_command)
            self.assertIn("merge_method=squash", merge_command)
            self.assertNotIn("--admin", merge_command)
            self.assertIn(
                "commit_title=Guarded squash merge of PR #86", merge_command
            )
            self.assertIn(
                f"commit_message=Exact tested HEAD {HEAD}", merge_command
            )
            self.assertFalse(any(BODY.strip() in value for value in merge_command))
            self.assertEqual(result["state"], "merged_unverified")
            persisted = issue_agent.read_state(state_dir)["pending_merge_events"]
            self.assertEqual(persisted[0]["merge_commit"], MERGE)
            self.assertEqual(persisted[0]["attempts"], 1)

    def test_base_race_stops_before_merge_request_and_keeps_preparation(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = self.write_snapshot(directory)
            state_dir = Path(directory) / "state"
            with self.common_context(second_base="d" * 40), mock.patch.object(
                issue_agent, "run_json", return_value={"state": "success"}
            ) as run_json:
                with self.assertRaisesRegex(
                    issue_agent.CommandError, "base commit changed"
                ):
                    issue_agent.guarded_merge(self.args(snapshot, state_dir))

            self.assertEqual(len(run_json.call_args_list), 1)
            pending = issue_agent.read_state(state_dir)["pending_merge_events"]
            self.assertEqual(pending[0]["state"], "preparing")
            self.assertEqual(pending[0]["attempts"], 0)

    def test_protection_failure_prevents_status_and_merge_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = self.write_snapshot(directory)
            state_dir = Path(directory) / "state"
            with (
                mock.patch.object(issue_agent, "fetch_origin", return_value=BASE),
                mock.patch.object(
                    issue_agent, "live_pull_request", return_value=pull_request()
                ),
                mock.patch.object(
                    issue_agent,
                    "live_branch_protection",
                    return_value=protection(
                        required_status_checks={"strict": False, "contexts": []}
                    ),
                ),
                mock.patch.object(issue_agent, "run_json") as run_json,
            ):
                with self.assertRaises(issue_agent.CommandError):
                    issue_agent.guarded_merge(self.args(snapshot, state_dir))

            run_json.assert_not_called()
            self.assertFalse((state_dir / "state.json").exists())

    def test_different_pending_candidate_is_rejected_before_persistence(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            issue_agent.persist_pending_merge(
                state_dir,
                event(),
                state_name="acquiring_merge_lease",
                increment_attempt=False,
                lease_commit=LEASE,
            )
            second_head = "f" * 40
            second = event(
                id="auto-merge:87:second-candidate",
                pr=87,
                head=second_head,
            )
            snapshot = Path(directory) / "snapshot.json"
            snapshot.write_text(
                json.dumps({"repo": REPO, "events": [second]}, sort_keys=True),
                encoding="utf-8",
            )
            args = Namespace(
                snapshot=str(snapshot),
                state_dir=str(state_dir),
                repo=REPO,
                control_repo="/control",
                event_id=second["id"],
                confirm_gates_head=second_head,
            )
            with mock.patch.object(issue_agent, "fetch_origin") as fetch_origin:
                with self.assertRaisesRegex(
                    issue_agent.CommandError,
                    "another merge event is pending durable acknowledgement",
                ):
                    issue_agent.guarded_merge(args)

            fetch_origin.assert_not_called()
            pending = issue_agent.read_state(state_dir)["pending_merge_events"]
            self.assertEqual([value["id"] for value in pending], [event()["id"]])

    def test_merge_transport_failure_retains_pre_mutation_intent(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = self.write_snapshot(directory)
            state_dir = Path(directory) / "state"
            with self.common_context(), mock.patch.object(
                issue_agent,
                "run_json",
                side_effect=[
                    {"state": "success"},
                    issue_agent.CommandError("timeout after request"),
                ],
            ):
                with self.assertRaisesRegex(issue_agent.CommandError, "timeout"):
                    issue_agent.guarded_merge(self.args(snapshot, state_dir))

            pending = issue_agent.read_state(state_dir)["pending_merge_events"]
            self.assertEqual(pending[0]["state"], "request_sent_or_unknown")
            self.assertEqual(pending[0]["attempts"], 1)

    def test_already_merged_pending_intent_never_sends_second_merge(self):
        merged = pull_request(
            state="MERGED", mergeCommit={"oid": MERGE}, exact_gate=True
        )
        with tempfile.TemporaryDirectory() as directory:
            snapshot = self.write_snapshot(directory)
            state_dir = Path(directory) / "state"
            with (
                mock.patch.object(issue_agent, "fetch_origin", return_value=BASE),
                mock.patch.object(issue_agent, "live_pull_request", return_value=merged),
                mock.patch.object(
                    issue_agent, "event_has_durable_outcome", return_value=True
                ),
                mock.patch.object(issue_agent, "run_json") as run_json,
            ):
                result = issue_agent.guarded_merge(self.args(snapshot, state_dir))

            run_json.assert_not_called()
            self.assertEqual(result["merge_commit"], MERGE)

    def test_uncertain_open_request_is_never_sent_twice(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = self.write_snapshot(directory)
            state_dir = Path(directory) / "state"
            issue_agent.persist_pending_merge(
                state_dir,
                event(),
                state_name="request_sent_or_unknown",
                increment_attempt=True,
            )
            with (
                mock.patch.object(issue_agent, "fetch_origin", return_value=BASE),
                mock.patch.object(
                    issue_agent, "live_pull_request", return_value=pull_request()
                ),
                mock.patch.object(issue_agent, "run_json") as run_json,
            ):
                with self.assertRaisesRegex(
                    issue_agent.CommandError, "refusing a second request"
                ):
                    issue_agent.guarded_merge(self.args(snapshot, state_dir))

            run_json.assert_not_called()
            pending = issue_agent.read_state(state_dir)["pending_merge_events"]
            self.assertEqual(pending[0]["attempts"], 1)


class MergeCriticalLeaseTests(unittest.TestCase):
    def test_acquire_uses_remote_create_cas_and_verifies_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            issue_agent.persist_pending_merge(
                state_dir,
                event(),
                state_name="acquiring_merge_lease",
                increment_attempt=False,
                lease_commit=LEASE,
            )
            with (
                mock.patch.object(
                    issue_agent, "remote_ref_oid", side_effect=["", LEASE]
                ),
                mock.patch.object(issue_agent, "run", return_value="") as run,
            ):
                issue_agent.acquire_merge_critical_lease(
                    Path("/control"), state_dir, event()
                )

            command = run.call_args.args[0]
            self.assertIn(
                f"--force-with-lease={issue_agent.MERGE_CRITICAL_LEASE_REF}:"
                + "0" * 40,
                command,
            )
            self.assertIn(
                f"{LEASE}:{issue_agent.MERGE_CRITICAL_LEASE_REF}", command
            )

    def test_foreign_merge_lease_blocks_before_push(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            issue_agent.persist_pending_merge(
                state_dir,
                event(),
                state_name="acquiring_merge_lease",
                increment_attempt=False,
                lease_commit=LEASE,
            )
            with (
                mock.patch.object(
                    issue_agent, "remote_ref_oid", return_value="d" * 40
                ),
                mock.patch.object(issue_agent, "run") as run,
            ):
                with self.assertRaisesRegex(
                    issue_agent.CommandError, "already held"
                ):
                    issue_agent.acquire_merge_critical_lease(
                        Path("/control"), state_dir, event()
                    )

            run.assert_not_called()


class PendingIntentTests(unittest.TestCase):
    def test_pending_merge_intents_are_never_silently_truncated(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            for number in range(105):
                candidate = event(
                    id=f"pending:{number}",
                    pr=number + 1,
                    head=f"{number:040x}",
                )
                issue_agent.persist_pending_merge(
                    state_dir,
                    candidate,
                    state_name="preparing",
                    increment_attempt=False,
                )

            pending = issue_agent.read_state(state_dir)["pending_merge_events"]
            self.assertEqual(len(pending), 105)
            self.assertEqual(pending[0]["id"], "pending:0")

    def test_inspect_restores_pending_merge_when_pr_is_no_longer_open(self):
        pending = event()
        args = Namespace(
            control_repo="/control",
            state_dir="/state",
            release_policy=str(MODULE_PATH.with_name("release-policy.json")),
            repo="owner/repo",
            worktree_root="/worktrees",
            max_batch_size=5,
            max_active_batches=1,
            stale_hours=6,
        )

        def fake_run(command, **_kwargs):
            if command[:2] == ["git", "fetch"]:
                return ""
            if command == ["git", "rev-parse", "origin/main"]:
                return f"{BASE}\n"
            raise AssertionError(f"unexpected command: {command}")

        with (
            mock.patch.object(
                issue_agent,
                "read_state",
                return_value={
                    "acknowledged_event_ids": [],
                    "pending_merge_events": [pending],
                },
            ),
            mock.patch.object(issue_agent, "run", side_effect=fake_run),
            mock.patch.object(
                issue_agent, "live_branch_protection", return_value=protection()
            ),
            mock.patch.object(issue_agent, "run_json", side_effect=[[], []]),
            mock.patch.object(
                issue_agent,
                "main_plist_values",
                return_value=("0.7.11", "2026072011"),
            ),
            mock.patch.object(issue_agent, "remote_ref_text", return_value=""),
        ):
            result = issue_agent.inspect(args)

        self.assertEqual(result["events"], [pending])
        self.assertTrue(result["should_run"])

    def test_acknowledge_atomically_removes_verified_pending_event(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            snapshot_path = Path(directory) / "snapshot.json"
            pending = {
                **event(),
                "state": "merged_unverified",
                "attempts": 1,
                "lease_commit": LEASE,
            }
            issue_agent.write_state(
                state_dir,
                {"acknowledged_event_ids": [], "pending_merge_events": [pending]},
            )
            snapshot_path.write_text(
                json.dumps({"events": [pending], "claimable_batches": []}),
                encoding="utf-8",
            )
            args = Namespace(
                snapshot=str(snapshot_path),
                state_dir=str(state_dir),
                repo="owner/repo",
                control_repo="/control",
                require_durable_outcome=True,
            )
            with (
                mock.patch.object(issue_agent, "run", return_value=""),
                mock.patch.object(
                    issue_agent, "event_has_durable_outcome", return_value=True
                ),
                mock.patch.object(issue_agent, "release_merge_critical_lease"),
            ):
                issue_agent.acknowledge(args)

            state = issue_agent.read_state(state_dir)
            self.assertIn(pending["id"], state["acknowledged_event_ids"])
            self.assertEqual(state["pending_merge_events"], [])
            self.assertEqual(state["pending_lease_cleanups"], [])

    def test_acknowledge_persists_cleanup_before_release_and_recovers(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            snapshot_path = Path(directory) / "snapshot.json"
            pending = {
                **event(),
                "state": "merged_unverified",
                "attempts": 1,
                "lease_commit": LEASE,
            }
            issue_agent.write_state(
                state_dir,
                {"acknowledged_event_ids": [], "pending_merge_events": [pending]},
            )
            snapshot_path.write_text(
                json.dumps({"events": [pending], "claimable_batches": []}),
                encoding="utf-8",
            )
            args = Namespace(
                snapshot=str(snapshot_path),
                state_dir=str(state_dir),
                repo=REPO,
                control_repo="/control",
                require_durable_outcome=True,
            )
            with (
                mock.patch.object(issue_agent, "run", return_value=""),
                mock.patch.object(
                    issue_agent, "event_has_durable_outcome", return_value=True
                ),
                mock.patch.object(
                    issue_agent,
                    "release_merge_critical_lease",
                    side_effect=issue_agent.CommandError("network"),
                ),
            ):
                with self.assertRaisesRegex(issue_agent.CommandError, "network"):
                    issue_agent.acknowledge(args)

            durable = issue_agent.read_state(state_dir)
            self.assertIn(pending["id"], durable["acknowledged_event_ids"])
            self.assertEqual(durable["pending_merge_events"], [])
            self.assertEqual(
                durable["pending_lease_cleanups"][0]["lease_commit"], LEASE
            )
            cleanup_args = Namespace(
                state_dir=str(state_dir), control_repo="/control"
            )
            with mock.patch.object(
                issue_agent, "release_merge_critical_lease"
            ) as release:
                result = issue_agent.cleanup_pending_merge_leases(cleanup_args)

            release.assert_called_once_with(Path("/control"), LEASE)
            self.assertEqual(result, {"cleaned": 1})
            self.assertEqual(
                issue_agent.read_state(state_dir)["pending_lease_cleanups"], []
            )

    def test_failed_fsync_leaves_previous_state_readable(self):
        with tempfile.TemporaryDirectory() as directory:
            state_dir = Path(directory) / "state"
            old = {"acknowledged_event_ids": ["old"], "pending_merge_events": []}
            issue_agent.write_state(state_dir, old)
            with mock.patch.object(issue_agent.os, "fsync", side_effect=OSError("disk")):
                with self.assertRaisesRegex(OSError, "disk"):
                    issue_agent.write_state(
                        state_dir,
                        {"acknowledged_event_ids": ["new"], "pending_merge_events": []},
                    )
            self.assertEqual(issue_agent.read_state(state_dir), old)


if __name__ == "__main__":
    unittest.main()
