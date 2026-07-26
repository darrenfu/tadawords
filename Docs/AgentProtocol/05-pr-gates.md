# Pull requests and merge gates

[Back to module index](README.md)

Open one draft PR for the batch and link every Issue with separate `Closes`
lines. Record tier, HEAD SHA, included Issues, applicable evidence,
limitations, rollback, and manual acceptance. Record version/build/artifact
identity only when the PR owns a versioned artifact.

Stop before implementation for high-risk changes, destructive data work,
security/privacy/auth/payment work, public API or persistence changes, major
dependencies, architectural changes, or ambiguous product choices.

After all gates applicable to the declared tier pass, mark the PR ready and apply
`awaiting-human-review`; this is the merge-candidate marker, not proof that the
gates still pass. A new commit invalidates prior-HEAD evidence; remove or
disregard readiness and rerun only the matrix applicable to the new HEAD's tier.

Immediately before squash merge, re-fetch the PR and verify all of the
following against its unchanged full HEAD SHA:

- the PR is ready, mergeable, clean, and targets `main` directly; stacked or
  non-`main` PRs are never automatic merge candidates;
- the current PR body's SHA-256 digest and GitHub's complete canonical
  `closingIssuesReferences` set exactly match the candidate event; sidebar
  links and qualified same-repository syntax are included, while any cross-repo
  closing reference is rejected; any body, closing-reference, or base edit
  invalidates that event even when the commit SHA is unchanged;
- all required status checks and repository checks passed on this exact HEAD;
- all applicable simulator, signed-artifact, physical-device, regression, and
  manual-product evidence names this exact HEAD and target environment;
- no blocker or clarification label, unresolved requested change, stale
  evidence, dependency, or unresolved high-risk decision remains; and
- the target artifact and environment match what was tested.

Automatic merge additionally requires GitHub `main` protection to match
`Automation/issue-agent/main-branch-protection.json`: strict up-to-date checks,
admin enforcement, pull-request entry, linear history, resolved conversations,
no force push/deletion, and required `tadawords/exact-head-gates` status. The
candidate pins GitHub's per-PR `baseRefOid` and the protection-contract digest.
Missing or changed protection is a blocker, never a reason to use `--admin`.

The standing authorization recorded here permits Codex to squash-merge after
that preflight without waiting for another owner comment. An owner-authored
`/merge <current-head-sha>` comment is optional and still valid, but it cannot
replace or weaken any gate. A command naming an older SHA is invalid.
