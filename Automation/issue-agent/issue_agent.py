#!/usr/bin/env python3
"""Read-only GitHub preflight for the Tada Words release-batch worker."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import socket
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any, Iterable


READY_LABEL = "agent-ready"
CLAIMED_LABEL = "agent-claimed"
RECLAIMED_LABEL = "agent-reclaimed"
IMPLEMENTATION_PR_LABEL = "implementation-in-pr"
CLAIMED_LABELS = {CLAIMED_LABEL, RECLAIMED_LABEL}
BLOCKING_LABELS = {"needs-human-clarification", "agent-blocked"}
AGENT_PR_LABELS = {"awaiting-human-review", "human-approved"}
AUTOMATIC_MERGE_READY_LABEL = "awaiting-human-review"
MERGE_EVENT_TYPES = {"automatic_merge_candidate", "merge_authorized"}
DEFAULT_MAX_ACTIVE_BATCHES = 1
MAX_CLAIMS_PER_POLL = 1
VERSION_RE = re.compile(r"(?<![0-9])v?(\d+)\.(\d+)\.(\d+)(?![0-9])")
BUILD_RE = re.compile(r"(?<![0-9])(20\d{8})(?![0-9])")
PRIORITY_RE = re.compile(
    r"(?im)(?:^|\n)(?:\s*##\s*priority\s*\n\s*|\s*priority\s*:\s*)(P[0-3])\b"
)
MERGE_RE = re.compile(r"^/merge\s+([0-9a-fA-F]{7,40})\s*$")
RESUME_RE = re.compile(r"^/resume(?:\s+([0-9a-fA-F]{7,40}))?\s*$")
CLOSING_ISSUE_RE = re.compile(
    r"(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?[ \t]+#(\d+)"
)
BRANCH_MARKER_RE = re.compile(
    r"tada-issue-agent:coverage:branch-[^\s>]+.*?branch `([^`]+)` at `([0-9a-f]{7,40})`",
    re.IGNORECASE | re.DOTALL,
)
LEASE_COMMENT_RE = re.compile(
    r"tada-issue-agent:lease:[^\s>]+.*?Remote lease `([^`]+)` is `([0-9a-f]{40})`",
    re.IGNORECASE | re.DOTALL,
)

AREA_KEYWORDS: dict[str, tuple[str, ...]] = {
    "parent": (
        "parent",
        "guardian",
        "profile",
        "kid setup",
        "family",
        "家长",
        "家长端",
        "孩子档案",
    ),
    "audio": (
        "audio",
        "speech",
        "voice",
        "pronunciation",
        "recording",
        "sound",
        "ducking",
        "tts",
        "发音",
        "录音",
        "音频",
        "声音",
    ),
    "import": (
        "ocr",
        "import",
        "word pool",
        "preset",
        "scan",
        "photo",
        "导入",
        "词库",
        "拍照",
        "识别",
    ),
    "automation": (
        "automation",
        "release",
        "worktree",
        "github",
        "version",
        "ci",
        "agent",
        "自动化",
        "版本",
    ),
}


class CommandError(RuntimeError):
    pass


def run(command: list[str], *, cwd: Path | None = None) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip()
        raise CommandError(f"{' '.join(command)} failed: {message}")
    return completed.stdout


def run_json(command: list[str], *, cwd: Path | None = None) -> Any:
    output = run(command, cwd=cwd)
    try:
        return json.loads(output)
    except json.JSONDecodeError as error:
        raise CommandError(f"invalid JSON from {' '.join(command)}: {error}") from error


def label_names(item: dict[str, Any]) -> set[str]:
    labels = item.get("labels") or []
    return {
        label["name"] if isinstance(label, dict) else str(label)
        for label in labels
        if label
    }


def infer_area(issue: dict[str, Any]) -> str:
    labels = label_names(issue)
    explicit = sorted(
        label.removeprefix("area:")
        for label in labels
        if label.startswith("area:")
    )
    if explicit:
        return explicit[0]

    text = f"{issue.get('title', '')}\n{issue.get('body', '')}".casefold()
    scores = {
        area: sum(text.count(keyword) for keyword in keywords)
        for area, keywords in AREA_KEYWORDS.items()
    }
    best_area, best_score = max(scores.items(), key=lambda pair: pair[1])
    return best_area if best_score else "unclassified"


def issue_priority(issue: dict[str, Any]) -> tuple[int, str]:
    labels = label_names(issue)
    for rank in range(4):
        value = f"priority:P{rank}"
        if value in labels:
            return rank, f"P{rank}"
    match = PRIORITY_RE.search(str(issue.get("body") or ""))
    if match:
        value = match.group(1).upper()
        return int(value[1:]), value
    return 4, "unspecified"


def explicit_batch_key(issue: dict[str, Any]) -> str:
    batch_labels = sorted(
        label for label in label_names(issue) if label.startswith("batch:")
    )
    if batch_labels:
        return batch_labels[0]
    return f"issue:{int(issue['number'])}"


def is_ready(issue: dict[str, Any]) -> bool:
    labels = label_names(issue)
    return (
        READY_LABEL in labels
        and not labels.intersection(CLAIMED_LABELS)
        and IMPLEMENTATION_PR_LABEL not in labels
        and not labels.intersection(BLOCKING_LABELS)
    )


def suggested_batches(
    issues: Iterable[dict[str, Any]], max_batch_size: int = 5
) -> list[dict[str, Any]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for issue in sorted(issues, key=lambda value: value["number"]):
        groups.setdefault(explicit_batch_key(issue), []).append(issue)

    batches: list[dict[str, Any]] = []
    for group in sorted(groups):
        candidates = sorted(
            groups[group], key=lambda value: (issue_priority(value)[0], value["number"])
        )
        while candidates:
            chunk, candidates = candidates[:max_batch_size], candidates[max_batch_size:]
            priorities = [issue_priority(issue) for issue in chunk]
            priority_rank, priority = min(priorities)
            areas = sorted({infer_area(issue) for issue in chunk})
            batches.append(
                {
                    "area": areas[0] if len(areas) == 1 else "cross-area",
                    "batch_key": group,
                    "priority": priority,
                    "priority_rank": priority_rank,
                    "issue_numbers": [issue["number"] for issue in chunk],
                    "titles": [issue["title"] for issue in chunk],
                    "requires_code_boundary_verification": True,
                }
            )
    return sorted(
        batches,
        key=lambda batch: (batch["priority_rank"], batch["issue_numbers"][0]),
    )


def is_agent_pull_request(pr: dict[str, Any]) -> bool:
    labels = label_names(pr)
    return (
        str(pr.get("headRefName") or "").startswith("agent/")
        or CLAIMED_LABEL in labels
        or bool(labels.intersection(AGENT_PR_LABELS))
        or any(label.startswith("batch:") for label in labels)
    )


def batch_admission(
    batches: list[dict[str, Any]],
    active_prs: list[dict[str, Any]],
    max_active_batches: int,
    max_claims_per_poll: int = MAX_CLAIMS_PER_POLL,
) -> dict[str, Any]:
    """Admit independent areas without allowing unbounded active PRs.

    One poll launches at most one new batch. This keeps GitHub mutations and
    version reservation deterministic while allowing unrelated batch PRs to
    coexist in separate worktrees and wait independently for human review.
    """

    if max_active_batches < 1:
        raise ValueError("max_active_batches must be at least 1")
    if max_claims_per_poll < 1:
        raise ValueError("max_claims_per_poll must be at least 1")

    active_by_area: dict[str, list[int]] = {}
    for pr in active_prs:
        active_by_area.setdefault(infer_area(pr), []).append(int(pr["number"]))

    available_slots = max(0, max_active_batches - len(active_prs))
    eligible: list[dict[str, Any]] = []
    blocked: list[dict[str, Any]] = []
    for batch in batches:
        active_numbers = active_by_area.get(str(batch["area"]), [])
        if active_numbers:
            blocked.append(
                {
                    **batch,
                    "reason": "area_has_active_pr",
                    "blocking_prs": sorted(active_numbers),
                }
            )
        else:
            eligible.append(batch)

    if available_slots == 0:
        blocked.extend(
            {
                **batch,
                "reason": "active_batch_limit_reached",
                "blocking_prs": sorted(int(pr["number"]) for pr in active_prs),
            }
            for batch in eligible
        )
        claimable: list[dict[str, Any]] = []
        deferred: list[dict[str, Any]] = []
    else:
        claim_limit = min(available_slots, max_claims_per_poll)
        claimable = eligible[:claim_limit]
        deferred = [
            {**batch, "reason": "one_new_batch_per_poll"}
            for batch in eligible[claim_limit:]
        ]

    return {
        "max_active_batches": max_active_batches,
        "active_batch_count": len(active_prs),
        "available_batch_slots": available_slots,
        "active_areas": sorted(active_by_area),
        "active_prs_by_area": {
            area: sorted(numbers) for area, numbers in sorted(active_by_area.items())
        },
        "claimable_batches": claimable,
        "blocked_batches": blocked,
        "deferred_batches": deferred,
    }


def parse_version(value: str) -> tuple[int, int, int] | None:
    match = VERSION_RE.search(value)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def format_version(version: tuple[int, int, int]) -> str:
    return ".".join(str(part) for part in version)


def next_patch_version(
    current: tuple[int, int, int], reserved: Iterable[tuple[int, int, int]]
) -> tuple[int, int, int]:
    highest = max([current, *reserved])
    return highest[0], highest[1], highest[2] + 1


def next_build_number(current: str, reserved: Iterable[str], now: dt.date) -> str:
    candidates = [int(current), *(int(value) for value in reserved)]
    date_prefix = int(now.strftime("%Y%m%d")) * 100
    highest = max(candidates)
    return str(max(date_prefix + 1, highest + 1))


def main_plist_values(control_repo: Path) -> tuple[str, str]:
    raw = subprocess.run(
        [
            "git",
            "show",
            "origin/main:Apps/TadaWordsApp/Info.plist",
        ],
        cwd=control_repo,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if raw.returncode != 0:
        raise CommandError(raw.stderr.decode().strip() or "unable to read main Info.plist")
    plist = plistlib.loads(raw.stdout)
    return str(plist["CFBundleShortVersionString"]), str(plist["CFBundleVersion"])


def remote_ref_text(control_repo: Path) -> str:
    return run(
        [
            "git",
            "for-each-ref",
            "--format=%(refname:short)",
            "refs/remotes/origin",
            "refs/tags",
        ],
        cwd=control_repo,
    )


def reserved_versions_and_builds(
    issues: list[dict[str, Any]], prs: list[dict[str, Any]], refs: str
) -> tuple[set[tuple[int, int, int]], set[str]]:
    version_text_parts = [refs]
    build_text_parts: list[str] = []
    for item in [*issues, *prs]:
        labels = label_names(item)
        version_text_parts.extend(
            label for label in labels if label.startswith("release:v")
        )
        build_text_parts.extend(
            label for label in labels if label.startswith("build:")
        )
        # Issue prose often discusses version examples or policy ceilings; it
        # is not a reservation. Open PR titles/heads are live reservations.
        if item.get("headRefName") is not None:
            version_text_parts.extend(
                [str(item.get("title") or ""), str(item.get("headRefName") or "")]
            )
        for line in str(item.get("body") or "").splitlines():
            normalized = line.strip().casefold()
            if "new version:" in normalized or "planned version:" in normalized:
                version_text_parts.append(line)
            if "build number:" in normalized or "planned build:" in normalized:
                build_text_parts.append(line)

    version_text = "\n".join(version_text_parts)
    build_text = "\n".join(build_text_parts)
    versions = {
        tuple(int(part) for part in match.groups())
        for match in VERSION_RE.finditer(version_text)
    }
    builds = {match.group(1) for match in BUILD_RE.finditer(build_text)}
    return versions, builds


def load_release_policy(path: Path) -> dict[str, Any]:
    try:
        policy = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CommandError(f"unable to read release policy {path}: {error}") from error
    if policy.get("schema_version") != 1:
        raise CommandError("release policy schema_version must be 1")
    release = policy.get("first_public_app_store_release")
    if not isinstance(release, dict):
        raise CommandError("release policy has no first_public_app_store_release state")
    status = release.get("status")
    if status not in {"incomplete", "released"}:
        raise CommandError("release policy status must be incomplete or released")
    ceiling = parse_version(str(release.get("version_ceiling") or ""))
    if ceiling is None:
        raise CommandError("release policy version_ceiling is malformed")
    if status == "released":
        required = (
            "public_app_store_url",
            "released_version",
            "released_build",
            "release_manifest",
            "owner_authorization",
        )
        missing = [key for key in required if not release.get(key)]
        if missing:
            raise CommandError(
                "released policy state is missing: " + ", ".join(missing)
            )
    return policy


def release_policy_ceiling(policy: dict[str, Any]) -> tuple[int, int, int] | None:
    release = policy["first_public_app_store_release"]
    if release["status"] == "released":
        return None
    ceiling = parse_version(str(release["version_ceiling"]))
    if ceiling is None:
        raise CommandError("release policy version_ceiling is malformed")
    return ceiling


def enforce_release_ceiling(
    versions: Iterable[tuple[int, int, int]], policy: dict[str, Any], *, context: str
) -> None:
    ceiling = release_policy_ceiling(policy)
    if ceiling is None:
        return
    violations = sorted(version for version in versions if version > ceiling)
    if violations:
        values = ", ".join(f"v{format_version(value)}" for value in violations)
        raise CommandError(
            f"{context} exceeds the pre-App Store ceiling "
            f"v{format_version(ceiling)}: {values}"
        )


def owner_login(repo: str) -> str:
    owner, separator, _ = repo.partition("/")
    if not separator:
        raise ValueError("repo must use owner/name form")
    return owner


def sha_matches(requested: str, current: str) -> bool:
    return len(requested) >= 7 and current.casefold().startswith(requested.casefold())


def pr_body_digest(body: str) -> str:
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def pull_request_events(
    repo: str,
    prs: list[dict[str, Any]],
    acknowledged: set[str],
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    owner = owner_login(repo)
    for pr in prs:
        labels = label_names(pr)
        head_name = str(pr.get("headRefName") or "")
        if not (head_name.startswith("agent/") or labels.intersection(AGENT_PR_LABELS)):
            continue

        number = int(pr["number"])
        head = str(pr.get("headRefOid") or "")
        base = str(pr.get("baseRefName") or "")
        body = str(pr.get("body") or "")
        body_digest = pr_body_digest(body)
        closing_issues = sorted(exact_closing_issue_numbers(body))
        reviews = run_json(
            ["gh", "api", f"repos/{repo}/pulls/{number}/reviews", "--paginate"]
        )
        current_changes_requested = False
        for review in reviews:
            event_id = f"review:{review.get('id')}"
            if (
                review.get("state") == "CHANGES_REQUESTED"
                and review.get("commit_id") == head
            ):
                current_changes_requested = True
                if event_id not in acknowledged:
                    events.append(
                        {
                            "id": event_id,
                            "type": "changes_requested",
                            "pr": number,
                            "head": head,
                            "url": pr.get("url"),
                        }
                    )

        comments = run_json(
            ["gh", "api", f"repos/{repo}/issues/{number}/comments", "--paginate"]
        )
        for comment in comments:
            if (comment.get("user") or {}).get("login") != owner:
                continue
            body = str(comment.get("body") or "").strip()
            merge_match = MERGE_RE.fullmatch(body)
            resume_match = RESUME_RE.fullmatch(body)
            event_id = f"comment:{comment.get('id')}"
            if event_id in acknowledged:
                continue
            if (
                merge_match
                and sha_matches(merge_match.group(1), head)
                and base == "main"
            ):
                events.append(
                    {
                        "id": event_id,
                        "type": "merge_authorized",
                        "pr": number,
                        "head": head,
                        "base": base,
                        "body_digest": body_digest,
                        "closing_issues": closing_issues,
                        "url": pr.get("url"),
                    }
                )
            elif resume_match and (
                resume_match.group(1) is None
                or sha_matches(resume_match.group(1), head)
            ):
                events.append(
                    {
                        "id": event_id,
                        "type": "resume_requested",
                        "pr": number,
                        "head": head,
                        "url": pr.get("url"),
                    }
                )

        auto_merge_event_id = f"auto-merge:{number}:{head}:{body_digest}"
        if (
            auto_merge_event_id not in acknowledged
            and len(head) == 40
            and base == "main"
            and AUTOMATIC_MERGE_READY_LABEL in labels
            and not bool(pr.get("isDraft"))
            and not labels.intersection(BLOCKING_LABELS)
            and str(pr.get("reviewDecision") or "") != "CHANGES_REQUESTED"
            and not current_changes_requested
        ):
            events.append(
                {
                    "id": auto_merge_event_id,
                    "type": "automatic_merge_candidate",
                    "pr": number,
                    "head": head,
                    "base": base,
                    "body_digest": body_digest,
                    "closing_issues": closing_issues,
                    "url": pr.get("url"),
                }
            )
    return events


def issue_resume_events(
    repo: str,
    issues: list[dict[str, Any]],
    acknowledged: set[str],
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    owner = owner_login(repo)
    for issue in issues:
        if not label_names(issue).intersection(BLOCKING_LABELS):
            continue
        number = int(issue["number"])
        comments = run_json(
            ["gh", "api", f"repos/{repo}/issues/{number}/comments", "--paginate"]
        )
        for comment in comments:
            event_id = f"comment:{comment.get('id')}"
            if event_id in acknowledged:
                continue
            if (comment.get("user") or {}).get("login") != owner:
                continue
            if RESUME_RE.fullmatch(str(comment.get("body") or "").strip()):
                events.append(
                    {
                        "id": event_id,
                        "type": "issue_resume_requested",
                        "issue": number,
                        "url": issue.get("url"),
                    }
                )
    return events


def parse_github_time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def exact_closing_issue_numbers(text: str) -> set[int]:
    return {int(match.group(1)) for match in CLOSING_ISSUE_RE.finditer(text)}


def git_is_ancestor(control_repo: Path, ancestor: str, descendant: str) -> bool:
    completed = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=control_repo,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return completed.returncode == 0


def git_trees_match(control_repo: Path, left: str, right: str) -> bool:
    left_tree = run(["git", "rev-parse", f"{left}^{{tree}}"], cwd=control_repo).strip()
    right_tree = run(["git", "rev-parse", f"{right}^{{tree}}"], cwd=control_repo).strip()
    return bool(left_tree) and left_tree == right_tree


def issue_comments(repo: str, number: int) -> list[dict[str, Any]]:
    return run_json(
        ["gh", "api", f"repos/{repo}/issues/{number}/comments", "--paginate"]
    )


def branch_coverage_from_comments(
    repo: str, issue: dict[str, Any], control_repo: Path
) -> list[dict[str, Any]]:
    number = int(issue["number"])
    coverage: list[dict[str, Any]] = []
    for comment in issue_comments(repo, number):
        if (comment.get("user") or {}).get("login") != owner_login(repo):
            continue
        body = str(comment.get("body") or "")
        match = BRANCH_MARKER_RE.search(body)
        if not match:
            continue
        branch, recorded_head = match.groups()
        ref = f"refs/remotes/origin/{branch}"
        current = subprocess.run(
            ["git", "rev-parse", "--verify", ref],
            cwd=control_repo,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        if current.returncode != 0:
            continue
        current_head = current.stdout.strip()
        if not sha_matches(recorded_head, current_head) and not git_is_ancestor(
            control_repo, recorded_head, current_head
        ):
            continue
        coverage.append(
            {
                "type": "remote_branch",
                "branch": branch,
                "recorded_head": recorded_head,
                "current_head": current_head,
                "comment_url": comment.get("html_url"),
            }
        )
    return coverage


def lease_ownership_from_comments(
    repo: str, issue_number: int
) -> dict[str, str] | None:
    for comment in reversed(issue_comments(repo, issue_number)):
        if (comment.get("user") or {}).get("login") != owner_login(repo):
            continue
        match = LEASE_COMMENT_RE.search(str(comment.get("body") or ""))
        if match:
            branch, commit = match.groups()
            return {
                "lease_branch": branch,
                "lease_ref": f"refs/heads/{branch}",
                "lease_commit": commit,
            }
    return None


def lease_issue_numbers(lease_branch: str, fallback: int) -> list[int]:
    match = re.search(r"/batch-([0-9]+(?:-[0-9]+)*)$", lease_branch)
    if not match:
        return [fallback]
    return sorted({int(value) for value in match.group(1).split("-")})


def explicit_remote_branch_coverage(
    issue_number: int, control_repo: Path
) -> list[dict[str, Any]]:
    coverage: list[dict[str, Any]] = []
    refs = run(
        [
            "git",
            "for-each-ref",
            "--format=%(refname:short) %(objectname)",
            "refs/remotes/origin",
        ],
        cwd=control_repo,
    ).splitlines()
    branch_number_re = re.compile(
        rf"(?:^|[-_/])(?:issue[-_/]?)?{issue_number}(?:$|[-_/])",
        re.IGNORECASE,
    )
    for line in refs:
        ref_name, _, head = line.partition(" ")
        if ref_name in {"origin/HEAD", "origin/main"} or "/leases/" in ref_name:
            continue
        branch = ref_name.removeprefix("origin/")
        name_match = bool(branch_number_re.search(branch))
        log = run(
            ["git", "log", "--format=%B", "--max-count=100", f"origin/main..{ref_name}"],
            cwd=control_repo,
        )
        closing_match = issue_number in exact_closing_issue_numbers(log)
        ahead = int(
            run(
                ["git", "rev-list", "--count", f"origin/main..{ref_name}"],
                cwd=control_repo,
            ).strip()
            or "0"
        )
        if ahead == 0 or (not name_match and not closing_match):
            continue
        coverage.append(
            {
                "type": "remote_branch",
                "branch": branch,
                "current_head": head,
                "commits_ahead_of_main": ahead,
                "evidence": "issue_number_in_branch" if name_match else "exact_closing_commit",
            }
        )
    return coverage


def issue_timeline(repo: str, number: int) -> list[dict[str, Any]]:
    owner, name = repo.split("/", 1)
    query = """
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    issue(number:$number){
      timelineItems(last:100,itemTypes:[REOPENED_EVENT,CLOSED_EVENT]){
        nodes{
          __typename
          ... on ReopenedEvent{createdAt actor{login}}
          ... on ClosedEvent{
            createdAt
            closer{
              __typename
              ... on PullRequest{number mergedAt mergeCommit{oid} baseRefName}
            }
          }
        }
      }
    }
  }
}
""".strip()
    result = run_json(
        [
            "gh",
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-F",
            f"owner={owner}",
            "-F",
            f"name={name}",
            "-F",
            f"number={number}",
        ]
    )
    return (
        result.get("data", {})
        .get("repository", {})
        .get("issue", {})
        .get("timelineItems", {})
        .get("nodes", [])
    )


def was_reopened_after(events: list[dict[str, Any]], moment: str) -> bool:
    merged_at = parse_github_time(moment)
    return any(
        event.get("__typename") == "ReopenedEvent"
        and parse_github_time(str(event["createdAt"])) > merged_at
        for event in events
    )


def exact_pull_request_coverage(
    repo: str, issue: dict[str, Any], control_repo: Path
) -> list[dict[str, Any]]:
    number = int(issue["number"])
    details = run_json(
        [
            "gh",
            "issue",
            "view",
            str(number),
            "--repo",
            repo,
            "--json",
            "closedByPullRequestsReferences",
        ]
    )
    coverage: list[dict[str, Any]] = []
    for reference in details.get("closedByPullRequestsReferences") or []:
        pr_number = int(reference["number"])
        pr = run_json(
            [
                "gh",
                "pr",
                "view",
                str(pr_number),
                "--repo",
                repo,
                "--json",
                "number,state,mergedAt,mergeCommit,baseRefName,headRefName,headRefOid,url",
            ]
        )
        state = str(pr.get("state") or "")
        if state == "OPEN":
            head = str(pr.get("headRefOid") or "")
            marker = f"tada-issue-agent:coverage:pr-{pr_number}:{head}"
            marker_exists = any(
                marker in str(comment.get("body") or "")
                and (comment.get("user") or {}).get("login") == owner_login(repo)
                for comment in issue_comments(repo, number)
            )
            coverage.append(
                {
                    "type": "open_pull_request",
                    "action": (
                        "none"
                        if IMPLEMENTATION_PR_LABEL in label_names(issue)
                        and marker_exists
                        else "link_open_pull_request"
                    ),
                    "pr": pr_number,
                    "head": head,
                    "url": pr.get("url"),
                }
            )
            continue
        if state != "MERGED" or pr.get("baseRefName") != "main":
            continue
        merge_commit = (pr.get("mergeCommit") or {}).get("oid")
        merged_at = pr.get("mergedAt")
        if not merge_commit or not merged_at:
            continue
        if not git_is_ancestor(control_repo, str(merge_commit), "origin/main"):
            continue
        events = issue_timeline(repo, number)
        if was_reopened_after(events, str(merged_at)):
            coverage.append(
                {
                    "type": "merged_pull_request",
                    "action": "none",
                    "reason": "issue_reopened_after_merge",
                    "pr": pr_number,
                    "merge_commit": merge_commit,
                    "merged_at": merged_at,
                    "url": pr.get("url"),
                }
            )
            continue
        coverage.append(
            {
                "type": "merged_pull_request",
                "action": "close_stale_issue",
                "pr": pr_number,
                "merge_commit": merge_commit,
                "merged_at": merged_at,
                "url": pr.get("url"),
            }
        )
    return coverage


def coverage_for_issue(
    repo: str, issue: dict[str, Any], control_repo: Path
) -> list[dict[str, Any]]:
    exact = exact_pull_request_coverage(repo, issue, control_repo)
    if any(
        entry.get("type") == "open_pull_request"
        or entry.get("action") == "close_stale_issue"
        for entry in exact
    ):
        return exact
    markers = branch_coverage_from_comments(repo, issue, control_repo)
    if markers:
        return [*exact, *markers]
    return [
        *exact,
        *explicit_remote_branch_coverage(int(issue["number"]), control_repo),
    ]


def coverage_protects_issue(entries: Iterable[dict[str, Any]]) -> bool:
    return any(
        entry.get("type") in {"open_pull_request", "remote_branch"}
        or entry.get("action") == "close_stale_issue"
        for entry in entries
    )


def stale_claim_events(
    issues: list[dict[str, Any]],
    acknowledged: set[str],
    now: dt.datetime,
    stale_hours: int,
    protected_issue_numbers: set[int] | None = None,
) -> list[dict[str, Any]]:
    protected_issue_numbers = protected_issue_numbers or set()
    events: list[dict[str, Any]] = []
    threshold = now - dt.timedelta(hours=stale_hours)
    for issue in issues:
        labels = label_names(issue)
        if not labels.intersection(CLAIMED_LABELS) or labels.intersection(BLOCKING_LABELS):
            continue
        number = int(issue["number"])
        if number in protected_issue_numbers:
            continue
        updated_at = parse_github_time(str(issue["updatedAt"]))
        event_id = f"stale:{number}:{issue['updatedAt']}"
        if updated_at < threshold and event_id not in acknowledged:
            events.append(
                {
                    "id": event_id,
                    "type": "stale_claim",
                    "issue": number,
                    "updatedAt": issue["updatedAt"],
                    "url": issue.get("url"),
                }
            )
    return events


def read_state(state_dir: Path) -> dict[str, Any]:
    state_file = state_dir / "state.json"
    if not state_file.exists():
        return {"acknowledged_event_ids": []}
    with state_file.open(encoding="utf-8") as handle:
        return json.load(handle)


def write_state(state_dir: Path, state: dict[str, Any]) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    target = state_dir / "state.json"
    temporary = state_dir / "state.json.tmp"
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, target)


def inspect(args: argparse.Namespace) -> dict[str, Any]:
    control_repo = Path(args.control_repo).resolve()
    state_dir = Path(args.state_dir).resolve()
    release_policy_path = Path(args.release_policy).resolve()
    release_policy = load_release_policy(release_policy_path)
    state = read_state(state_dir)
    acknowledged = set(state.get("acknowledged_event_ids") or [])

    run(
        [
            "git",
            "fetch",
            "origin",
            "--prune",
            "+refs/heads/*:refs/remotes/origin/*",
        ],
        cwd=control_repo,
    )
    issues = run_json(
        [
            "gh",
            "issue",
            "list",
            "--repo",
            args.repo,
            "--state",
            "open",
            "--limit",
            "200",
            "--json",
            "number,title,body,labels,updatedAt,url",
        ]
    )
    prs = run_json(
        [
            "gh",
            "pr",
            "list",
            "--repo",
            args.repo,
            "--state",
            "open",
            "--limit",
            "100",
            "--json",
            "number,title,body,headRefName,headRefOid,baseRefName,labels,reviewDecision,isDraft,updatedAt,url",
        ]
    )

    coverage_candidates = [
        issue
        for issue in issues
        if is_ready(issue) or label_names(issue).intersection(CLAIMED_LABELS)
    ]
    coverage_by_issue: dict[int, list[dict[str, Any]]] = {}
    for issue in coverage_candidates:
        issue_coverage = coverage_for_issue(args.repo, issue, control_repo)
        if issue_coverage:
            coverage_by_issue[int(issue["number"])] = issue_coverage
    covered_issue_numbers = {
        number
        for number, entries in coverage_by_issue.items()
        if coverage_protects_issue(entries)
    }
    reconciliation_actions = [
        {"issue": number, **coverage}
        for number, entries in sorted(coverage_by_issue.items())
        for coverage in entries
        if coverage.get("action") not in {None, "none"}
    ]
    closing_issue_numbers = {
        int(action["issue"])
        for action in reconciliation_actions
        if action.get("action") == "close_stale_issue"
    }
    reconciliation_actions.extend(
        {
            "issue": int(issue["number"]),
            "action": "release_blocked_claim",
            "type": "blocked_claim",
            "blocking_labels": sorted(label_names(issue).intersection(BLOCKING_LABELS)),
            "updated_at": issue.get("updatedAt"),
        }
        for issue in issues
        if label_names(issue).intersection(CLAIMED_LABELS)
        and label_names(issue).intersection(BLOCKING_LABELS)
        and int(issue["number"]) not in closing_issue_numbers
    )

    ready = [
        issue
        for issue in issues
        if is_ready(issue) and int(issue["number"]) not in covered_issue_numbers
    ]
    agent_prs = [pr for pr in prs if is_agent_pull_request(pr)]
    events = pull_request_events(args.repo, prs, acknowledged)
    events.extend(issue_resume_events(args.repo, issues, acknowledged))
    now = dt.datetime.now(dt.timezone.utc)
    events.extend(
        stale_claim_events(
            issues,
            acknowledged,
            now=now,
            stale_hours=args.stale_hours,
            protected_issue_numbers=covered_issue_numbers,
        )
    )

    current_version_text, current_build = main_plist_values(control_repo)
    current_version = parse_version(current_version_text)
    if current_version is None:
        raise CommandError(f"invalid main version: {current_version_text}")
    reserved_versions, reserved_builds = reserved_versions_and_builds(
        issues, prs, remote_ref_text(control_repo)
    )
    proposed_version = next_patch_version(current_version, reserved_versions)
    enforce_release_ceiling(
        [current_version, *reserved_versions, proposed_version],
        release_policy,
        context="current, reserved, or suggested version",
    )
    proposed_build = next_build_number(
        current_build, reserved_builds, now=now.date()
    )

    batches = suggested_batches(ready, args.max_batch_size)
    admission = batch_admission(
        batches,
        agent_prs,
        max_active_batches=args.max_active_batches,
    )
    if events:
        admission["deferred_batches"] = [
            {**batch, "reason": "actionable_event_has_priority"}
            for batch in (
                admission["claimable_batches"] + admission["deferred_batches"]
            )
        ]
        admission["claimable_batches"] = []

    claimable_batches = admission["claimable_batches"]
    queue_paused = bool(ready) and not bool(claimable_batches)
    should_run = bool(events) or bool(claimable_batches)
    return {
        "schema_version": 2,
        "generated_at": now.isoformat(),
        "repo": args.repo,
        "control_repo": str(control_repo),
        "worktree_root": str(Path(args.worktree_root).resolve()),
        "should_run": should_run,
        "has_reconciliation_actions": bool(reconciliation_actions),
        "queue_paused": queue_paused,
        "queue_paused_by_open_agent_pr": queue_paused and bool(agent_prs),
        "ready_issues": ready,
        "suggested_batches": batches,
        **admission,
        "active_agent_prs": agent_prs,
        "coverage_by_issue": {
            str(number): entries
            for number, entries in sorted(coverage_by_issue.items())
        },
        "reconciliation_actions": reconciliation_actions,
        "events": events,
        "version_context": {
            "main_version": current_version_text,
            "main_build": current_build,
            "reserved_versions": sorted(
                f"v{format_version(value)}" for value in reserved_versions
            ),
            "suggested_next_patch": f"v{format_version(proposed_version)}",
            "suggested_next_build": proposed_build,
            "note": "The agent must recheck and atomically reserve before editing.",
        },
        "release_policy": {
            "path": str(release_policy_path),
            "sha256": hashlib.sha256(release_policy_path.read_bytes()).hexdigest(),
            "first_public_app_store_release": release_policy[
                "first_public_app_store_release"
            ],
        },
    }


def read_snapshot(path: str | Path) -> dict[str, Any]:
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def write_snapshot(path: str | Path, snapshot: dict[str, Any]) -> None:
    target = Path(path)
    temporary = target.with_suffix(f"{target.suffix}.tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(snapshot, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, target)


def live_issue(repo: str, number: int) -> dict[str, Any]:
    return run_json(
        [
            "gh",
            "issue",
            "view",
            str(number),
            "--repo",
            repo,
            "--json",
            "number,title,body,state,labels,updatedAt,url,closedByPullRequestsReferences",
        ]
    )


def comment_with_marker(
    repo: str, number: int, marker: str, body: str
) -> str | None:
    for comment in issue_comments(repo, number):
        if (
            marker in str(comment.get("body") or "")
            and (comment.get("user") or {}).get("login") == owner_login(repo)
        ):
            return str(comment.get("html_url") or "") or None
    return run(
        [
            "gh",
            "issue",
            "comment",
            str(number),
            "--repo",
            repo,
            "--body",
            f"<!-- {marker} -->\n{body}",
        ]
    ).strip()


def reconcile(args: argparse.Namespace) -> dict[str, Any]:
    snapshot = read_snapshot(args.snapshot)
    control_repo = Path(args.control_repo).resolve()
    run(
        [
            "git",
            "fetch",
            "origin",
            "--prune",
            "+refs/heads/*:refs/remotes/origin/*",
        ],
        cwd=control_repo,
    )
    results: list[dict[str, Any]] = []
    for requested in snapshot.get("reconciliation_actions") or []:
        number = int(requested["issue"])
        issue = live_issue(args.repo, number)
        if issue.get("state") != "OPEN":
            results.append({"issue": number, "result": "already_closed"})
            continue
        if requested.get("action") == "release_blocked_claim":
            blocking_labels = sorted(label_names(issue).intersection(BLOCKING_LABELS))
            if not blocking_labels or not label_names(issue).intersection(
                CLAIMED_LABELS
            ):
                results.append(
                    {"issue": number, "result": "blocked_claim_already_released"}
                )
                continue
            lease = lease_ownership_from_comments(args.repo, number)
            companion_numbers = (
                lease_issue_numbers(str(lease["lease_branch"]), number)
                if lease
                else [number]
            )
            marker = (
                f"tada-issue-agent:blocker-release:observed-{number}-"
                f"{requested.get('updated_at') or 'unknown'}"
            )
            comment_with_marker(
                args.repo,
                number,
                marker,
                (
                    "The scheduler found this claimed Issue blocked by: "
                    f"{', '.join(blocking_labels)}. It is releasing the visible "
                    "claim and any owner-verified lease so it cannot occupy the "
                    "priority queue. Resolve the blocker and perform a fresh reclaim "
                    "before continuing."
                ),
            )
            for companion in companion_numbers:
                companion_issue = live_issue(args.repo, companion)
                if companion_issue.get("state") == "OPEN":
                    remove_claim_labels(args.repo, companion_issue)
                if companion != number:
                    comment_with_marker(
                        args.repo,
                        companion,
                        f"tada-issue-agent:companion-release:observed-{number}",
                        (
                            f"The shared reservation was released because Issue #{number} "
                            "is blocked. This Issue must be freshly reclaimed before work."
                        ),
                    )
            if lease:
                release_reservation_lease(lease, control_repo)
            results.append(
                {
                    "issue": number,
                    "result": "released_blocked_claim",
                    "blocking_labels": blocking_labels,
                    "released_issue_numbers": companion_numbers,
                    "released_lease": lease.get("lease_branch") if lease else None,
                }
            )
            continue
        live_coverage = coverage_for_issue(args.repo, issue, control_repo)
        matching = next(
            (
                item
                for item in live_coverage
                if item.get("action") == requested.get("action")
                and item.get("pr") == requested.get("pr")
            ),
            None,
        )
        if not matching:
            raise CommandError(
                f"Issue #{number} coverage changed; refusing stale reconciliation"
            )

        if matching["action"] == "link_open_pull_request":
            run(
                [
                    "gh",
                    "issue",
                    "edit",
                    str(number),
                    "--repo",
                    args.repo,
                    "--add-label",
                    IMPLEMENTATION_PR_LABEL,
                    "--add-label",
                    CLAIMED_LABEL,
                ]
            )
            marker = f"tada-issue-agent:coverage:pr-{matching['pr']}:{matching['head']}"
            comment_with_marker(
                args.repo,
                number,
                marker,
                (
                    f"Implementation is already owned by PR #{matching['pr']} "
                    f"({matching['url']}) at `{matching['head']}`. The Issue stays "
                    "open until that exact implementation is merged; duplicate pickup is skipped."
                ),
            )
            results.append(
                {
                    "issue": number,
                    "result": "linked_open_pull_request",
                    "pr": matching["pr"],
                }
            )
        elif matching["action"] == "close_stale_issue":
            marker = f"tada-issue-agent:coverage:merged-pr-{matching['pr']}"
            body = (
                f"Closing as already implemented by merged PR #{matching['pr']} "
                f"({matching['url']}) at `{matching['merge_commit']}`. The PR has an "
                "exact closing reference, targets `main`, its merge commit is reachable "
                "from fresh `origin/main`, and no later reopen event exists."
            )
            comment_with_marker(args.repo, number, marker, body)
            run(
                [
                    "gh",
                    "issue",
                    "close",
                    str(number),
                    "--repo",
                    args.repo,
                    "--reason",
                    "completed",
                ]
            )
            results.append(
                {
                    "issue": number,
                    "result": "closed_as_stale",
                    "pr": matching["pr"],
                }
            )
        else:
            raise CommandError(f"unsupported reconciliation action: {matching['action']}")
    return {"results": results}


def create_lease_commit(
    control_repo: Path, issue_numbers: list[int], worker: str
) -> tuple[str, str]:
    parent = run(["git", "rev-parse", "origin/main"], cwd=control_repo).strip()
    tree = run(["git", "rev-parse", "origin/main^{tree}"], cwd=control_repo).strip()
    message = (
        "Tada Words Issue Agent lease\n\n"
        f"Worker: {worker}\n"
        f"Issues: {','.join(str(number) for number in issue_numbers)}\n"
        f"Base: {parent}\n"
    )
    environment = os.environ.copy()
    environment.update(
        {
            "GIT_AUTHOR_NAME": "Tada Words Issue Agent",
            "GIT_AUTHOR_EMAIL": "issue-agent@localhost",
            "GIT_COMMITTER_NAME": "Tada Words Issue Agent",
            "GIT_COMMITTER_EMAIL": "issue-agent@localhost",
        }
    )
    completed = subprocess.run(
        ["git", "commit-tree", tree, "-p", parent],
        cwd=control_repo,
        check=False,
        input=message,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
    )
    if completed.returncode != 0:
        raise CommandError(completed.stderr.strip() or "unable to create lease commit")
    return completed.stdout.strip(), parent


def reserve(args: argparse.Namespace) -> dict[str, Any]:
    snapshot = read_snapshot(args.snapshot)
    batches = snapshot.get("claimable_batches") or []
    if not batches:
        return {"reserved": False, "reason": "no_claimable_batch"}
    if len(batches) != 1:
        raise CommandError("refusing to reserve more than one batch in a poll")

    control_repo = Path(args.control_repo).resolve()
    release_policy_path = Path(args.release_policy).resolve()
    release_policy = load_release_policy(release_policy_path)
    snapshot_policy = snapshot.get("release_policy") or {}
    policy_sha = hashlib.sha256(release_policy_path.read_bytes()).hexdigest()
    if snapshot_policy.get("sha256") != policy_sha:
        raise CommandError("release policy changed after inspection; refusing reservation")
    proposed = parse_version(
        str((snapshot.get("version_context") or {}).get("suggested_next_patch") or "")
    )
    if proposed is None:
        raise CommandError("snapshot has no valid suggested version")
    enforce_release_ceiling([proposed], release_policy, context="suggested version")
    run(
        [
            "git",
            "fetch",
            "origin",
            "--prune",
            "+refs/heads/*:refs/remotes/origin/*",
        ],
        cwd=control_repo,
    )
    issue_numbers = sorted(int(value) for value in batches[0]["issue_numbers"])
    live_issues: list[dict[str, Any]] = []
    for number in issue_numbers:
        issue = live_issue(args.repo, number)
        if issue.get("state") != "OPEN" or not is_ready(issue):
            raise CommandError(f"Issue #{number} is no longer safely claimable")
        coverage = coverage_for_issue(args.repo, issue, control_repo)
        if coverage_protects_issue(coverage):
            raise CommandError(
                f"Issue #{number} already has PR or remote-branch coverage"
            )
        live_issues.append(issue)

    token = uuid.uuid4().hex
    worker = f"{socket.gethostname()}:{os.getpid()}:{token[:12]}"
    # The visible reclaim label is deliberately the first mutation. A unique
    # remote lease commit below is the cross-process compare-and-swap winner.
    labeled_numbers: list[int] = []
    try:
        for issue in live_issues:
            run(
                [
                    "gh",
                    "issue",
                    "edit",
                    str(issue["number"]),
                    "--repo",
                    args.repo,
                    "--add-label",
                    RECLAIMED_LABEL,
                    "--add-label",
                    CLAIMED_LABEL,
                ]
            )
            labeled_numbers.append(int(issue["number"]))
    except CommandError:
        # No lease exists yet, so best-effort release only labels this attempt
        # added to Issues that were freshly verified as unclaimed.
        for number in labeled_numbers:
            try:
                remove_claim_labels(args.repo, live_issue(args.repo, number))
            except CommandError:
                pass
        raise

    lease_commit, base = create_lease_commit(control_repo, issue_numbers, worker)
    suffix = "-".join(str(number) for number in issue_numbers)
    lease_branch = f"agent/leases/batch-{suffix}"
    lease_ref = f"refs/heads/{lease_branch}"
    pushed = subprocess.run(
        ["git", "push", "origin", f"{lease_commit}:{lease_ref}"],
        cwd=control_repo,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if pushed.returncode != 0:
        # If the authoritative ref is absent, no contender won; undo this
        # attempt's visible claims. If the check itself fails or another commit
        # owns the ref, leave claims in place and fail closed for recovery.
        remote_check = subprocess.run(
            ["git", "ls-remote", "--heads", "origin", lease_ref],
            cwd=control_repo,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if remote_check.returncode == 0 and not remote_check.stdout.strip():
            for number in labeled_numbers:
                try:
                    remove_claim_labels(args.repo, live_issue(args.repo, number))
                except CommandError:
                    pass
        raise CommandError(
            "remote lease was not acquired; another worker may own the batch: "
            + (pushed.stderr.strip() or pushed.stdout.strip())
        )
    remote = run(
        ["git", "ls-remote", "--heads", "origin", lease_ref], cwd=control_repo
    ).strip()
    if not remote.startswith(lease_commit):
        raise CommandError("remote lease verification failed after push")

    for number in issue_numbers:
        marker = f"tada-issue-agent:lease:{token}"
        comment_with_marker(
            args.repo,
            number,
            marker,
            (
                f"Reclaimed by `{worker}` before implementation. Remote lease "
                f"`{lease_branch}` is `{lease_commit}` from `origin/main` `{base}`. "
                "Other agents must skip this Issue unless the lease is explicitly recovered."
            ),
        )

    reservation = {
        "worker": worker,
        "token": token,
        "issue_numbers": issue_numbers,
        "lease_branch": lease_branch,
        "lease_ref": lease_ref,
        "lease_commit": lease_commit,
        "base": base,
        "reserved_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    snapshot["reservation"] = reservation
    write_snapshot(args.snapshot, snapshot)
    return {"reserved": True, **reservation}


def live_pull_request(repo: str, number: int) -> dict[str, Any]:
    return run_json(
        [
            "gh",
            "pr",
            "view",
            str(number),
            "--repo",
            repo,
            "--json",
            "number,state,headRefOid,baseRefName,body,mergeCommit,mergedAt,labels,url",
        ]
    )


def linked_issues_closed_by_pull_request(
    repo: str, issue_numbers: Iterable[int], pull_request_number: int
) -> bool:
    numbers = [int(issue_number) for issue_number in issue_numbers]
    if not numbers:
        return False
    for issue_number in numbers:
        issue = live_issue(repo, int(issue_number))
        closing_pull_requests = {
            int(reference["number"])
            for reference in issue.get("closedByPullRequestsReferences") or []
            if reference.get("number") is not None
        }
        if (
            issue.get("state") != "CLOSED"
            or pull_request_number not in closing_pull_requests
        ):
            return False
    return True


def issue_has_durable_outcome(
    repo: str, number: int, control_repo: Path
) -> bool:
    issue = live_issue(repo, number)
    if issue.get("state") == "CLOSED":
        return True
    if label_names(issue).intersection(BLOCKING_LABELS):
        return True
    return coverage_protects_issue(coverage_for_issue(repo, issue, control_repo))


def reserved_issue_has_durable_outcome(
    repo: str, number: int, control_repo: Path
) -> bool:
    issue = live_issue(repo, number)
    if issue.get("state") == "CLOSED":
        return True
    # A blocker on reserved work is durable only through the release command,
    # which proves report + claim removal + lease release as one outcome.
    return coverage_protects_issue(coverage_for_issue(repo, issue, control_repo))


def event_has_durable_outcome(
    repo: str, event: dict[str, Any], control_repo: Path
) -> bool:
    event_type = str(event.get("type") or "")
    if event.get("pr") is not None:
        pull_request_number = int(event["pr"])
        pr = live_pull_request(repo, pull_request_number)
        state = str(pr.get("state") or "")
        current_head = str(pr.get("headRefOid") or "")
        expected_head = str(event.get("head") or "")
        if state == "OPEN":
            return current_head != expected_head
        if event_type not in MERGE_EVENT_TYPES:
            return True
        if state == "CLOSED":
            return False
        if state != "MERGED":
            return False
        expected_base = str(event.get("base") or "")
        expected_body_digest = str(event.get("body_digest") or "")
        live_body = str(pr.get("body") or "")
        expected_closing_issues = sorted(
            {int(number) for number in event.get("closing_issues") or []}
        )
        live_closing_issues = sorted(exact_closing_issue_numbers(live_body))
        merge_commit = str((pr.get("mergeCommit") or {}).get("oid") or "")
        if (
            not expected_head
            or current_head != expected_head
            or expected_base != "main"
            or pr.get("baseRefName") != expected_base
            or not expected_body_digest
            or pr_body_digest(live_body) != expected_body_digest
            or live_closing_issues != expected_closing_issues
            or not merge_commit
            or not git_is_ancestor(control_repo, merge_commit, "origin/main")
            or not git_trees_match(control_repo, expected_head, merge_commit)
        ):
            return False
        return not expected_closing_issues or linked_issues_closed_by_pull_request(
            repo, expected_closing_issues, pull_request_number
        )
    if event.get("issue") is not None:
        number = int(event["issue"])
        if event_type == "issue_resume_requested":
            issue = live_issue(repo, number)
            return issue.get("state") == "CLOSED" or not label_names(issue).intersection(
                BLOCKING_LABELS
            )
        return issue_has_durable_outcome(repo, number, control_repo)
    return False


def release_reservation_lease(
    reservation: dict[str, Any], control_repo: Path
) -> None:
    lease_ref = str(reservation["lease_ref"])
    lease_commit = str(reservation["lease_commit"])
    remote = run(
        ["git", "ls-remote", "--heads", "origin", lease_ref], cwd=control_repo
    ).strip()
    if not remote:
        return
    if not remote.startswith(lease_commit):
        raise CommandError("refusing to release a lease now owned by another commit")
    run(
        [
            "git",
            "push",
            f"--force-with-lease={lease_ref}:{lease_commit}",
            "origin",
            f":{lease_ref}",
        ],
        cwd=control_repo,
    )


def remove_claim_labels(repo: str, issue: dict[str, Any]) -> None:
    labels = label_names(issue)
    for label in sorted(labels.intersection(CLAIMED_LABELS)):
        run(
            [
                "gh",
                "issue",
                "edit",
                str(issue["number"]),
                "--repo",
                repo,
                "--remove-label",
                label,
            ]
        )


def release(args: argparse.Namespace) -> dict[str, Any]:
    snapshot = read_snapshot(args.snapshot)
    reservation = snapshot.get("reservation")
    if not reservation:
        raise CommandError("cannot release work without a verified reservation")
    issue_number = int(args.issue)
    reserved_numbers = [int(value) for value in reservation.get("issue_numbers") or []]
    if issue_number not in reserved_numbers:
        raise CommandError(f"Issue #{issue_number} is not owned by this reservation")
    reason = Path(args.reason_file).read_text(encoding="utf-8").strip()
    if not reason:
        raise CommandError("blocker report must not be empty")

    issue = live_issue(args.repo, issue_number)
    token = str(reservation["token"])
    marker = f"tada-issue-agent:blocker-release:{token}"
    comment_with_marker(
        args.repo,
        issue_number,
        marker,
        (
            "Pickup released because a blocker prevents safe progress.\n\n"
            f"**Blocker report**\n\n{reason}\n\n"
            "The claim labels and verified remote lease are being released. "
            "After the blocker is resolved, this Issue must pass a fresh reclaim."
        ),
    )
    run(
        [
            "gh",
            "issue",
            "edit",
            str(issue_number),
            "--repo",
            args.repo,
            "--add-label",
            "agent-blocked",
        ]
    )
    for number in reserved_numbers:
        live = live_issue(args.repo, number)
        remove_claim_labels(args.repo, live)
        if number != issue_number:
            comment_with_marker(
                args.repo,
                number,
                f"tada-issue-agent:companion-release:{token}",
                (
                    f"This batch reservation was released because Issue #{issue_number} "
                    "reported a blocker. No implementation ownership remains; a future "
                    "pickup must reclaim this Issue again."
                ),
            )
    control_repo = Path(args.control_repo).resolve()
    release_reservation_lease(reservation, control_repo)
    release_record = {
        "issue": issue_number,
        "marker": marker,
        "reason": reason,
        "released_issue_numbers": reserved_numbers,
        "released_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    snapshot["release"] = release_record
    write_snapshot(args.snapshot, snapshot)
    return release_record


def release_has_durable_outcome(
    repo: str,
    release_record: dict[str, Any],
    reservation: dict[str, Any],
    control_repo: Path,
) -> bool:
    blocker_issue = int(release_record["issue"])
    for number in release_record.get("released_issue_numbers") or []:
        issue = live_issue(repo, int(number))
        if label_names(issue).intersection(CLAIMED_LABELS):
            return False
        if int(number) == blocker_issue and "agent-blocked" not in label_names(issue):
            return False
        if int(number) == blocker_issue:
            marker = str(release_record.get("marker") or "")
            if not marker or not any(
                marker in str(comment.get("body") or "")
                and (comment.get("user") or {}).get("login") == owner_login(repo)
                for comment in issue_comments(repo, blocker_issue)
            ):
                return False
    remote = run(
        ["git", "ls-remote", "--heads", "origin", str(reservation["lease_ref"])],
        cwd=control_repo,
    ).strip()
    return not remote


def acknowledge(args: argparse.Namespace) -> None:
    state_dir = Path(args.state_dir).resolve()
    snapshot = read_snapshot(args.snapshot)
    if args.require_durable_outcome:
        if not args.repo or not args.control_repo:
            raise ValueError(
                "--repo and --control-repo are required with --require-durable-outcome"
            )
        control_repo = Path(args.control_repo).resolve()
        run(
            [
                "git",
                "fetch",
                "origin",
                "--prune",
                "+refs/heads/*:refs/remotes/origin/*",
            ],
            cwd=control_repo,
        )
        incomplete_events = [
            str(event.get("id") or event.get("type") or "unknown")
            for event in snapshot.get("events") or []
            if not event_has_durable_outcome(args.repo, event, control_repo)
        ]
        if incomplete_events:
            raise CommandError(
                "events lack a durable GitHub outcome: " + ", ".join(incomplete_events)
            )
        reservation = snapshot.get("reservation")
        if snapshot.get("claimable_batches") and not reservation:
            raise CommandError("claimable work was not durably reserved")
        if reservation:
            release_record = snapshot.get("release")
            if release_record:
                if not release_has_durable_outcome(
                    args.repo, release_record, reservation, control_repo
                ):
                    raise CommandError("released batch lacks a durable released state")
            else:
                incomplete_issues = [
                    int(number)
                    for number in reservation.get("issue_numbers") or []
                    if not reserved_issue_has_durable_outcome(
                        args.repo, int(number), control_repo
                    )
                ]
                if incomplete_issues:
                    raise CommandError(
                        "reserved Issues lack a durable outcome: "
                        + ", ".join(f"#{number}" for number in incomplete_issues)
                    )
                release_reservation_lease(reservation, control_repo)
    state = read_state(state_dir)
    acknowledged = set(state.get("acknowledged_event_ids") or [])
    acknowledged.update(
        str(event["id"]) for event in snapshot.get("events") or [] if event.get("id")
    )
    state["acknowledged_event_ids"] = sorted(acknowledged)[-500:]
    state["last_successful_run"] = dt.datetime.now(dt.timezone.utc).isoformat()
    write_state(state_dir, state)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)

    inspect_parser = commands.add_parser("inspect")
    inspect_parser.add_argument("--repo", required=True)
    inspect_parser.add_argument("--control-repo", required=True)
    inspect_parser.add_argument("--worktree-root", required=True)
    inspect_parser.add_argument("--state-dir", required=True)
    inspect_parser.add_argument(
        "--release-policy",
        default=str(Path(__file__).with_name("release-policy.json")),
    )
    inspect_parser.add_argument("--max-batch-size", type=int, default=5)
    inspect_parser.add_argument(
        "--max-active-batches", type=int, default=DEFAULT_MAX_ACTIVE_BATCHES
    )
    inspect_parser.add_argument("--stale-hours", type=int, default=6)
    inspect_parser.add_argument("--pretty", action="store_true")

    reconcile_parser = commands.add_parser("reconcile")
    reconcile_parser.add_argument("--snapshot", required=True)
    reconcile_parser.add_argument("--repo", required=True)
    reconcile_parser.add_argument("--control-repo", required=True)

    reserve_parser = commands.add_parser("reserve")
    reserve_parser.add_argument("--snapshot", required=True)
    reserve_parser.add_argument("--repo", required=True)
    reserve_parser.add_argument("--control-repo", required=True)
    reserve_parser.add_argument(
        "--release-policy",
        default=str(Path(__file__).with_name("release-policy.json")),
    )

    release_parser = commands.add_parser("release")
    release_parser.add_argument("--snapshot", required=True)
    release_parser.add_argument("--repo", required=True)
    release_parser.add_argument("--control-repo", required=True)
    release_parser.add_argument("--issue", required=True, type=int)
    release_parser.add_argument("--reason-file", required=True)

    acknowledge_parser = commands.add_parser("acknowledge")
    acknowledge_parser.add_argument("--snapshot", required=True)
    acknowledge_parser.add_argument("--state-dir", required=True)
    acknowledge_parser.add_argument("--repo")
    acknowledge_parser.add_argument("--control-repo")
    acknowledge_parser.add_argument(
        "--require-durable-outcome", action="store_true"
    )
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "inspect":
            result = inspect(args)
            json.dump(result, sys.stdout, indent=2 if args.pretty else None, sort_keys=True)
            sys.stdout.write("\n")
        elif args.command == "reconcile":
            json.dump(reconcile(args), sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
        elif args.command == "reserve":
            json.dump(reserve(args), sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
        elif args.command == "release":
            json.dump(release(args), sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
        else:
            acknowledge(args)
    except (CommandError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"issue-agent preflight failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
