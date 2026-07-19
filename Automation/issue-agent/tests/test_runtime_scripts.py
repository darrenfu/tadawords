#!/usr/bin/env python3

import json
import os
import plistlib
import shutil
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ISSUE_AGENT_ROOT = Path(__file__).parents[1]
RUNNER = ISSUE_AGENT_ROOT / "run.sh"
INSTALLER = ISSUE_AGENT_ROOT / "install-launch-agent.sh"
PLIST_TEMPLATE = ISSUE_AGENT_ROOT / "com.tadawords.issue-agent.plist.template"


def write_executable(path: Path, contents: str) -> None:
    path.write_text(contents, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class RunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()
        shutil.copy2(RUNNER, self.runtime / "run.sh")
        (self.runtime / "agent-prompt.md").write_text("Test prompt\n")
        self.call_log = self.root / "core-calls.jsonl"
        self.codex_args = self.root / "codex-args.txt"
        write_executable(
            self.runtime / "issue_agent.py",
            """#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

command = sys.argv[1]
with Path(os.environ["FAKE_CALL_LOG"]).open("a", encoding="utf-8") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")

if command == "inspect":
    counter = Path(os.environ["FAKE_INSPECT_COUNTER"])
    count = int(counter.read_text() or "0") if counter.exists() else 0
    counter.write_text(str(count + 1))
    reconcile = os.environ.get("FAKE_RECONCILIATION") == "1" and count == 0
    claimable = os.environ.get("FAKE_CLAIMABLE") == "1" and not reconcile
    event = os.environ.get("FAKE_EVENT") == "1" and not reconcile
    print(json.dumps({
        "should_run": reconcile or claimable or event,
        "reconciliation_actions": [{"issue_number": 1}] if reconcile else [],
        "claimable_batches": [{"issue_numbers": [2]}] if claimable else [],
        "events": [{"id": "event-1"}] if event else [],
    }))
elif command == "reserve":
    snapshot = Path(sys.argv[sys.argv.index("--snapshot") + 1])
    payload = json.loads(snapshot.read_text())
    payload["reserved"] = True
    snapshot.write_text(json.dumps(payload))
elif command == "acknowledge":
    raise SystemExit(int(os.environ.get("FAKE_ACK_EXIT", "0")))
""",
        )
        write_executable(
            self.root / "codex",
            """#!/bin/sh
printf '%s\\n' "$@" >"$FAKE_CODEX_ARGS"
cat >/dev/null
if [ -n "${FAKE_CODEX_READY:-}" ]; then
  touch "$FAKE_CODEX_READY"
fi
sleep "${FAKE_CODEX_SLEEP:-0}"
printf '%s\\n' '{"type":"turn.completed"}'
exit "${FAKE_CODEX_EXIT:-0}"
""",
        )
        self.state = self.root / "state"
        self.logs = self.root / "logs"
        self.worktrees = self.root / "worktrees"
        self.control = self.root / "control"
        self.control.mkdir()
        self.environment = {
            **os.environ,
            "TADA_AGENT_CONFIG": str(self.root / "missing.env"),
            "TADA_AGENT_REPO": "owner/repo",
            "TADA_AGENT_CONTROL_REPO": str(self.control),
            "TADA_AGENT_WORKTREE_ROOT": str(self.worktrees),
            "TADA_AGENT_STATE_DIR": str(self.state),
            "TADA_AGENT_LOG_DIR": str(self.logs),
            "TADA_AGENT_CODEX_BIN": str(self.root / "codex"),
            "FAKE_CALL_LOG": str(self.call_log),
            "FAKE_CODEX_ARGS": str(self.codex_args),
            "FAKE_INSPECT_COUNTER": str(self.root / "inspect-count"),
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_worker(self, **updates: str) -> subprocess.CompletedProcess[str]:
        environment = {**self.environment, **updates}
        return subprocess.run(
            ["/bin/zsh", str(self.runtime / "run.sh")],
            text=True,
            capture_output=True,
            env=environment,
            timeout=10,
            check=False,
        )

    def calls(self) -> list[list[str]]:
        if not self.call_log.exists():
            return []
        return [json.loads(line) for line in self.call_log.read_text().splitlines()]

    def test_claimable_batch_is_reserved_before_sol_ultra_and_durable_ack(self):
        result = self.run_worker(FAKE_CLAIMABLE="1")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in self.calls()], ["inspect", "reserve", "acknowledge"])
        reserve = self.calls()[1]
        self.assertIn("--repo", reserve)
        self.assertIn("--control-repo", reserve)
        acknowledge = self.calls()[2]
        self.assertIn("--repo", acknowledge)
        self.assertIn("--control-repo", acknowledge)
        self.assertIn("--require-durable-outcome", acknowledge)
        arguments = self.codex_args.read_text().splitlines()
        self.assertIn("gpt-5.6-sol", arguments)
        self.assertIn('model_reasoning_effort="ultra"', arguments)

    def test_reconciliation_runs_then_reinspects_without_starting_codex(self):
        result = self.run_worker(FAKE_RECONCILIATION="1")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [call[0] for call in self.calls()],
            ["inspect", "reconcile", "inspect"],
        )
        self.assertFalse(self.codex_args.exists())

    def test_missing_durable_outcome_is_not_acknowledged(self):
        result = self.run_worker(FAKE_EVENT="1", FAKE_ACK_EXIT="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call[0] for call in self.calls()], ["inspect", "acknowledge"])
        self.assertIn("no durable GitHub outcome", (self.logs / "poll.log").read_text())

    def test_lockf_contention_skips_before_inspection(self):
        self.state.mkdir(parents=True)
        ready = self.root / "lock-ready"
        holder_script = self.root / "hold-lock.sh"
        write_executable(
            holder_script,
            """#!/bin/sh
touch "$LOCK_READY"
sleep 2
""",
        )
        holder = subprocess.Popen(
            [
                "/usr/bin/lockf",
                "-k",
                str(self.state / "run.lock"),
                str(holder_script),
            ],
            env={**os.environ, "LOCK_READY": str(ready)},
        )
        try:
            deadline = time.monotonic() + 1.0
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "lock holder did not start")
            result = self.run_worker(FAKE_EVENT="1")
        finally:
            holder.wait(timeout=4)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertIn("another worker holds", (self.logs / "poll.log").read_text())

    def test_runner_keeps_its_fd_lock_for_the_whole_worker(self):
        ready = self.root / "codex-ready"
        first_environment = {
            **self.environment,
            "FAKE_EVENT": "1",
            "FAKE_CODEX_READY": str(ready),
            "FAKE_CODEX_SLEEP": "2",
        }
        first = subprocess.Popen(
            ["/bin/zsh", str(self.runtime / "run.sh")],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=first_environment,
        )
        try:
            deadline = time.monotonic() + 1.0
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "first worker did not reach Codex")
            second = self.run_worker(FAKE_EVENT="1")
        finally:
            first_stdout, first_stderr = first.communicate(timeout=4)

        self.assertEqual(first.returncode, 0, first_stderr or first_stdout)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual([call[0] for call in self.calls()], ["inspect", "acknowledge"])
        self.assertIn("another worker holds", (self.logs / "poll.log").read_text())


class InstallerTests(unittest.TestCase):
    def test_plist_runs_every_fifteen_minutes(self):
        with PLIST_TEMPLATE.open("rb") as stream:
            payload = plistlib.load(stream)
        self.assertEqual(payload["StartInterval"], 900)

    def test_installer_probes_catalog_then_backs_up_and_can_roll_back(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            install_root = root / "install"
            bin_dir = install_root / "bin"
            bin_dir.mkdir(parents=True)
            (bin_dir / "run.sh").write_text("old-run\n")
            (bin_dir / "agent.env").write_text("old-env\n")
            (bin_dir / "agent.env").chmod(0o600)
            (install_root / "control-repo" / ".git").mkdir(parents=True)

            launch_agent = root / "LaunchAgents" / "com.tadawords.issue-agent.plist"
            launch_agent.parent.mkdir()
            with launch_agent.open("wb") as stream:
                plistlib.dump({"Label": "com.tadawords.issue-agent.old"}, stream)

            model_catalog = root / "models_cache.json"
            model_catalog.write_text(
                json.dumps(
                    {
                        "models": [
                            {
                                "slug": "gpt-5.6-sol",
                                "supported_reasoning_levels": [
                                    {"effort": "medium"},
                                    {"effort": "ultra"},
                                ],
                            }
                        ]
                    }
                )
            )
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            operation_log = root / "operations.log"
            write_executable(fake_bin / "gh", "#!/bin/sh\nexit 0\n")
            write_executable(fake_bin / "git", "#!/bin/sh\nexit 0\n")
            write_executable(
                fake_bin / "launchctl",
                """#!/bin/sh
if [ "$1" = bootout ]; then
  find "$TADA_AGENT_INSTALL_ROOT/backups" -name manifest.sha256 -size +0 | grep -q . || exit 91
fi
if [ "$1" = bootstrap ] && [ "${FAKE_FAIL_BOOTSTRAP_ONCE:-0}" = 1 ] && [ ! -f "$FAKE_BOOTSTRAP_FAILURE_MARKER" ]; then
  touch "$FAKE_BOOTSTRAP_FAILURE_MARKER"
  exit 92
fi
printf '%s\\n' "$*" >>"$FAKE_OPERATION_LOG"
exit 0
""",
            )
            codex = fake_bin / "codex"
            write_executable(
                codex,
                """#!/bin/sh
case "$*" in
  *--version*) printf '%s\\n' 'codex-cli-test'; exit 0 ;;
  'login status') exit 0 ;;
esac
previous=''
for argument in "$@"; do
  if [ "$previous" = output ]; then
    printf '%s\\n' READY >"$argument"
    previous=''
  elif [ "$argument" = --output-last-message ]; then
    previous=output
  fi
done
printf '%s\\n' '{"type":"turn.completed"}'
""",
            )

            environment = {
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "TADA_AGENT_INSTALL_ROOT": str(install_root),
                "TADA_AGENT_WORKTREE_ROOT": str(root / "worktrees"),
                "TADA_AGENT_LOG_DIR": str(root / "logs"),
                "TADA_AGENT_LAUNCH_AGENT": str(launch_agent),
                "TADA_AGENT_LAUNCH_DOMAIN": "gui/test",
                "TADA_AGENT_MODEL_CATALOG": str(model_catalog),
                "TADA_AGENT_CODEX_BIN": str(codex),
                "FAKE_OPERATION_LOG": str(operation_log),
                "FAKE_BOOTSTRAP_FAILURE_MARKER": str(root / "bootstrap-failed"),
            }
            install_result = subprocess.run(
                ["/bin/zsh", str(INSTALLER)],
                text=True,
                capture_output=True,
                env=environment,
                timeout=20,
                check=False,
            )
            self.assertEqual(install_result.returncode, 0, install_result.stderr)

            backups = list((install_root / "backups").iterdir())
            self.assertEqual(len(backups), 1)
            backup = backups[0]
            self.assertEqual((backup / "bin" / "run.sh").read_text(), "old-run\n")
            self.assertTrue((backup / "manifest.sha256").stat().st_size > 0)
            self.assertIn("TADA_AGENT_REASONING_EFFORT='ultra'", (bin_dir / "agent.env").read_text())
            self.assertIn("TADA_AGENT_MAX_ACTIVE_BATCHES='1'", (bin_dir / "agent.env").read_text())
            self.assertEqual(stat.S_IMODE((bin_dir / "agent.env").stat().st_mode), 0o600)
            with launch_agent.open("rb") as stream:
                self.assertEqual(plistlib.load(stream)["StartInterval"], 900)
            self.assertIn("900-second interval", install_result.stdout)

            rollback_result = subprocess.run(
                ["/bin/zsh", str(INSTALLER), "--rollback", str(backup)],
                text=True,
                capture_output=True,
                env=environment,
                timeout=20,
                check=False,
            )
            self.assertEqual(rollback_result.returncode, 0, rollback_result.stderr)
            self.assertEqual((bin_dir / "run.sh").read_text(), "old-run\n")
            with launch_agent.open("rb") as stream:
                restored = plistlib.load(stream)
            self.assertEqual(restored["Label"], "com.tadawords.issue-agent.old")

            failed_install = subprocess.run(
                ["/bin/zsh", str(INSTALLER)],
                text=True,
                capture_output=True,
                env={**environment, "FAKE_FAIL_BOOTSTRAP_ONCE": "1"},
                timeout=20,
                check=False,
            )
            self.assertNotEqual(failed_install.returncode, 0)
            self.assertIn("restoring the verified backup", failed_install.stderr)
            self.assertEqual((bin_dir / "run.sh").read_text(), "old-run\n")
            with launch_agent.open("rb") as stream:
                restored_after_failure = plistlib.load(stream)
            self.assertEqual(
                restored_after_failure["Label"],
                "com.tadawords.issue-agent.old",
            )

            operation_log.unlink(missing_ok=True)
            rejected = subprocess.run(
                ["/bin/zsh", str(INSTALLER)],
                text=True,
                capture_output=True,
                env={**environment, "TADA_AGENT_REASONING_EFFORT": "unsupported"},
                timeout=20,
                check=False,
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("does not advertise reasoning effort", rejected.stderr)
            self.assertFalse(operation_log.exists(), "launchd changed before catalog validation")


if __name__ == "__main__":
    unittest.main()
