#!/usr/bin/env python3

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
        agents = self.document("AGENTS.md")
        readme = self.document("Automation/issue-agent/README.md")

        self.assertIn("roll back to the prior comment gate", agents)
        self.assertIn("restore the prior mandatory-comment merge gate", readme)
        self.assertIn("900-second", readme)
        self.assertIn("safe no-op poll", readme)

    def test_device_na_exception_excludes_every_packaged_metadata_change(self):
        agents = self.document("AGENTS.md")
        template = self.document(".github/pull_request_template.md")
        prompt = self.document("Automation/issue-agent/agent-prompt.md")
        release_notes = self.document("FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md")

        for document in (agents, template, prompt):
            with self.subTest(document=document[:40]):
                normalized = " ".join(document.split()).casefold()
                self.assertIn("version/build metadata", normalized)
                self.assertIn("generated xcode project", normalized)
        self.assertNotIn(
            "Simulator and physical-device testing are intentionally not applicable",
            release_notes,
        )
        normalized_release_notes = " ".join(release_notes.split())
        self.assertIn(
            "signed LocalQA iPhone and iPad evidence is pending",
            normalized_release_notes,
        )


if __name__ == "__main__":
    unittest.main()
