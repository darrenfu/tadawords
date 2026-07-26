#!/usr/bin/env python3

import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[3]


class DeliveryPolicyContractTests(unittest.TestCase):
    def document(self, relative_path: str) -> str:
        return (REPOSITORY_ROOT / relative_path).read_text(encoding="utf-8")

    def test_standing_authorization_replaces_only_the_mandatory_comment(self):
        agents = self.document("AGENTS.md")
        template = self.document(".github/pull_request_template.md")
        readme = self.document("Automation/issue-agent/README.md")
        prompt = self.document("Automation/issue-agent/agent-prompt.md")

        self.assertIn("standing authorization", agents)
        self.assertIn("standing authorization", template)
        self.assertIn("standing authorization", readme)
        self.assertIn("standing\n  owner authorization", prompt)
        self.assertNotIn("The owner authorizes merge only by", agents)
        self.assertNotIn("must comment", template)
        self.assertIn("/merge <current-head-sha>", readme)
        self.assertIn("/merge <sha>", prompt)

    def test_preflight_invalidation_and_post_merge_evidence_stay_mandatory(self):
        documents = "\n".join(
            self.document(path)
            for path in (
                "AGENTS.md",
                ".github/pull_request_template.md",
                "Automation/issue-agent/README.md",
                "Automation/issue-agent/agent-prompt.md",
            )
        )

        for required in (
            "exact-HEAD",
            "new commit",
            "mergeable",
            "blocker",
            "origin/main",
            "merged tree",
            "Closes #N",
            "SHA-256",
            "stacked",
            "closed without merge",
        ):
            with self.subTest(required=required):
                self.assertIn(required.casefold(), documents.casefold())

    def test_rollback_to_the_prior_comment_gate_is_documented(self):
        agents = "\n".join(
            (
                self.document("AGENTS.md"),
                self.document(
                    "Docs/AgentProtocol/07-human-gates-and-rollback.md"
                ),
            )
        )
        readme = self.document("Automation/issue-agent/README.md")

        self.assertIn("roll back to the prior comment gate", agents)
        self.assertIn("restore the prior mandatory-comment merge gate", readme)
        self.assertIn("900-second", readme)
        self.assertIn("safe no-op poll", readme)

    def test_guarded_merge_and_server_side_base_protection_are_mandatory(self):
        agents = self.document("AGENTS.md")
        readme = self.document("Automation/issue-agent/README.md")
        prompt = self.document("Automation/issue-agent/agent-prompt.md")
        protection = json.loads(
            self.document("Automation/issue-agent/main-branch-protection.json")
        )
        documents = "\n".join((agents, readme, prompt))

        self.assertIn("guarded-merge", documents)
        self.assertIn("base oid", documents.casefold())
        self.assertIn("fsync", documents.casefold())
        self.assertIn("never uses an admin bypass", " ".join(readme.split()))
        self.assertTrue(protection["required_status_checks"]["strict"])
        self.assertNotIn("contexts", protection["required_status_checks"])
        self.assertTrue(protection["enforce_admins"])
        self.assertEqual(
            protection["required_status_checks"]["checks"][0]["context"],
            "tadawords/exact-head-gates",
        )
        self.assertFalse(protection["allow_force_pushes"])
        self.assertFalse(protection["allow_deletions"])

    def test_metadata_trust_boundary_and_no_resend_rule_are_explicit(self):
        documents = "\n".join(
            self.document(path)
            for path in (
                "AGENTS.md",
                "Docs/AgentProtocol/06-guarded-merge.md",
                ".github/pull_request_template.md",
                "Automation/issue-agent/README.md",
                "Automation/issue-agent/agent-prompt.md",
            )
        ).casefold()

        for required in (
            "closingissuesreferences",
            "merge-critical",
            "no cas for pr metadata",
            "trusted-operator boundary",
            "never resends",
        ):
            with self.subTest(required=required):
                self.assertIn(required, documents)

    def test_risk_tiers_replace_uniform_device_and_version_gates(self):
        agents = "\n".join(
            (
                self.document("AGENTS.md"),
                self.document("Docs/AgentProtocol/02-versioning-and-generation.md"),
                self.document("Docs/AgentProtocol/03-verification.md"),
            )
        )
        template = self.document(".github/pull_request_template.md")
        prompt = self.document("Automation/issue-agent/agent-prompt.md")
        pipeline = self.document("Docs/DEVELOPMENT_PIPELINE.md")
        makefile = self.document("Makefile")

        for document in (agents, template, prompt, pipeline):
            with self.subTest(document=document[:40]):
                normalized = " ".join(document.split()).casefold()
                for tier in ("r0", "r1", "r2", "r3", "r4"):
                    self.assertIn(tier, normalized)
        self.assertNotIn("Every PR must increment SemVer", prompt)
        self.assertIn("do not increment SemVer", prompt)
        self.assertIn("check-changed", makefile)
        self.assertIn("check-pr", makefile)
        self.assertIn("check-rc", makefile)

    def test_writer_session_compaction_and_evidence_reuse_are_mandatory(self):
        documents = "\n".join(
            self.document(path)
            for path in (
                "AGENTS.md",
                "Docs/DEVELOPMENT_PIPELINE.md",
                "Automation/issue-agent/agent-prompt.md",
            )
        ).casefold()

        for required in (
            "one writer",
            "pr-writer",
            "first context compaction",
            "2 kb",
            "unchanged",
            "reuse",
            "no subagents",
            "non-nested",
            "heavy-xcode",
        ):
            with self.subTest(required=required):
                self.assertIn(required, documents)

    def test_unattended_default_is_terra_medium_not_ultra(self):
        runner = self.document("Automation/issue-agent/run.sh")
        installer = self.document("Automation/issue-agent/install-launch-agent.sh")
        readme = self.document("Automation/issue-agent/README.md")

        for document in (runner, installer):
            self.assertIn("gpt-5.6-terra", document)
            self.assertIn("medium", document)
            self.assertNotIn("gpt-5.6-sol}", document)
            self.assertNotIn("REASONING_EFFORT:=ultra", document)
        self.assertIn("Ultra is\nnever the unattended default", readme)


if __name__ == "__main__":
    unittest.main()
