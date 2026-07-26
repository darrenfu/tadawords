#!/usr/bin/env python3

"""Run focused, PR, or release-candidate checks from changed paths."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[1]
SWIFT_PREFIXES = ("Apps/", "Sources/", "Tests/")
SWIFT_FILES = {"Package.swift", "Package.resolved", "project.yml"}
ISSUE_AGENT_PREFIX = "Automation/issue-agent/"
ISSUE_POLICY_FILES = {
    "AGENTS.md",
    "Makefile",
    ".github/pull_request_template.md",
    "Docs/DEVELOPMENT_PIPELINE.md",
    "Docs/DEVELOPMENT_PIPELINE.zh-CN.md",
    "Scripts/delivery-checks.py",
    "Scripts/delivery-lease.py",
}
RELEASE_PREFIX = "Automation/release-preflight/"
RELEASE_FILES = {
    "Config/release-candidate-policy.json",
    "Scripts/release-candidate-preflight.py",
    "Scripts/verify-pawgoo-development-app.py",
}


class CheckPlanError(RuntimeError):
    pass


@dataclass(frozen=True)
class Step:
    name: str
    command: tuple[str, ...]


def changed_paths(base: str, head: str) -> list[str]:
    commands = (
        ("git", "diff", "--name-only", f"{base}...{head}"),
        ("git", "diff", "--name-only"),
        ("git", "diff", "--name-only", "--cached"),
        ("git", "ls-files", "--others", "--exclude-standard"),
    )
    paths: set[str] = set()
    for command in commands:
        result = subprocess.run(
            command,
            cwd=REPOSITORY_ROOT,
            check=True,
            text=True,
            capture_output=True,
        )
        paths.update(line for line in result.stdout.splitlines() if line)
    return sorted(paths)


def has_swift_change(paths: list[str]) -> bool:
    return any(
        path in SWIFT_FILES
        or path.startswith(SWIFT_PREFIXES)
        or path.endswith(".xcodeproj/project.pbxproj")
        for path in paths
    )


def has_issue_agent_change(paths: list[str]) -> bool:
    return any(path.startswith(ISSUE_AGENT_PREFIX) or path in ISSUE_POLICY_FILES for path in paths)


def has_release_change(paths: list[str]) -> bool:
    return any(path.startswith(RELEASE_PREFIX) or path in RELEASE_FILES for path in paths)


def build_plan(
    mode: str, paths: list[str], swift_test_filter: str | None = None
) -> list[Step]:
    if mode not in {"changed", "pr", "rc"}:
        raise CheckPlanError(f"unsupported mode: {mode}")
    if mode == "rc":
        return [
            Step("lint", ("make", "lint")),
            Step("swift-tests", ("make", "test")),
            Step("issue-agent-tests", ("make", "test-automation")),
            Step("release-preflight-tests", ("make", "test-release-preflight")),
        ]

    plan: list[Step] = []
    if has_swift_change(paths):
        plan.append(Step("lint", ("make", "lint")))
        if mode == "changed":
            if not swift_test_filter:
                raise CheckPlanError(
                    "Swift paths changed; check-changed requires TEST_FILTER"
                )
            plan.append(
                Step(
                    "focused-swift-tests",
                    ("swift", "test", "--filter", swift_test_filter),
                )
            )
        else:
            plan.append(Step("swift-tests", ("make", "test")))
    if has_issue_agent_change(paths):
        plan.append(Step("issue-agent-tests", ("make", "test-automation")))
    if has_release_change(paths):
        plan.append(
            Step("release-preflight-tests", ("make", "test-release-preflight"))
        )
    return plan


def parser() -> argparse.ArgumentParser:
    command_parser = argparse.ArgumentParser(description=__doc__)
    command_parser.add_argument("--mode", required=True, choices=("changed", "pr", "rc"))
    command_parser.add_argument("--base", default="origin/main")
    command_parser.add_argument("--head", default="HEAD")
    command_parser.add_argument("--swift-test-filter")
    command_parser.add_argument(
        "--changed-file",
        action="append",
        default=[],
        help="explicit changed path; repeat for tests or non-git callers",
    )
    command_parser.add_argument("--dry-run", action="store_true")
    return command_parser


def main() -> int:
    arguments = parser().parse_args()
    paths = (
        sorted(set(arguments.changed_file))
        if arguments.changed_file
        else changed_paths(arguments.base, arguments.head)
    )
    try:
        plan = build_plan(arguments.mode, paths, arguments.swift_test_filter)
    except CheckPlanError as error:
        print(str(error), file=sys.stderr)
        return 2
    print(
        json.dumps(
            {
                "mode": arguments.mode,
                "base": arguments.base,
                "head": arguments.head,
                "changed_paths": paths,
                "steps": [
                    {"name": step.name, "command": list(step.command)} for step in plan
                ],
            },
            indent=2,
            sort_keys=True,
        )
    )
    if arguments.dry_run:
        return 0
    for step in plan:
        print(f"==> {step.name}", flush=True)
        result = subprocess.run(step.command, cwd=REPOSITORY_ROOT, check=False)
        if result.returncode:
            return result.returncode
    if not plan:
        print("No changed-path checks are required.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
