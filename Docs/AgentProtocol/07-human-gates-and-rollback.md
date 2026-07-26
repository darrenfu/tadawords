# Human gates and policy rollback

[Back to module index](README.md)

Standing merge authorization never covers destructive child-data operations,
irreversible provider or account mutations, credentials or authentication,
materially ambiguous product choices, or a target environment that differs
from the tested artifact. Those actions still require the applicable explicit
human confirmation and must remain blocked until it is obtained.

To roll back to the prior comment gate, revert the policy change introduced for
Issue #85, reinstall the verified Issue Agent bundle, preserve its logs/state/
worktrees, confirm no pending merge intent, restore the recorded pre-Issue-#85
branch-protection state, and verify one 900-second safe no-op poll. Until that
rollback is verified, disable the worker or apply a blocker; do not hand-edit
the installed worker. The restored policy again requires
`/merge <current-head-sha>`.
