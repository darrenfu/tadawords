#!/usr/bin/env python3
"""Read-only GitHub preflight for the Tada Words release-batch worker."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable


READY_LABEL = "agent-ready"
CLAIMED_LABEL = "agent-claimed"
BLOCKING_LABELS = {"needs-human-clarification", "agent-blocked"}
AGENT_PR_LABELS = {"awaiting-human-review", "human-approved"}
DEFAULT_MAX_ACTIVE_BATCHES = 2
MAX_CLAIMS_PER_POLL = 1
VERSION_RE = re.compile(r"(?<![0-9])v?(\d+)\.(\d+)\.(\d+)(?![0-9])")
BUILD_RE = re.compile(r"(?<![0-9])(20\d{8})(?![0-9])")
MERGE_RE = re.compile(r"^/merge\s+([0-9a-fA-F]{7,40})\s*$")
RESUME_RE = re.compile(r"^/resume(?:\s+([0-9a-fA-F]{7,40}))?\s*$")

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


def is_ready(issue: dict[str, Any]) -> bool:
    labels = label_names(issue)
    return (
        READY_LABEL in labels
        and CLAIMED_LABEL not in labels
        and not labels.intersection(BLOCKING_LABELS)
    )


def suggested_batches(
    issues: Iterable[dict[str, Any]], max_batch_size: int = 5
) -> list[dict[str, Any]]:
    areas: dict[str, list[dict[str, Any]]] = {}
    for issue in sorted(issues, key=lambda value: value["number"]):
        areas.setdefault(infer_area(issue), []).append(issue)

    batches: list[dict[str, Any]] = []
    for area in sorted(areas):
        candidates = areas[area]
        while candidates:
            chunk, candidates = candidates[:max_batch_size], candidates[max_batch_size:]
            batches.append(
                {
                    "area": area,
                    "issue_numbers": [issue["number"] for issue in chunk],
                    "titles": [issue["title"] for issue in chunk],
                    "requires_code_boundary_verification": True,
                }
            )
    return sorted(batches, key=lambda batch: batch["issue_numbers"][0])


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


def owner_login(repo: str) -> str:
    owner, separator, _ = repo.partition("/")
    if not separator:
        raise ValueError("repo must use owner/name form")
    return owner


def sha_matches(requested: str, current: str) -> bool:
    return len(requested) >= 7 and current.casefold().startswith(requested.casefold())


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
        reviews = run_json(
            ["gh", "api", f"repos/{repo}/pulls/{number}/reviews", "--paginate"]
        )
        for review in reviews:
            event_id = f"review:{review.get('id')}"
            if (
                event_id not in acknowledged
                and review.get("state") == "CHANGES_REQUESTED"
                and review.get("commit_id") == head
            ):
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
            if merge_match and sha_matches(merge_match.group(1), head):
                events.append(
                    {
                        "id": event_id,
                        "type": "merge_authorized",
                        "pr": number,
                        "head": head,
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


def stale_claim_events(
    issues: list[dict[str, Any]],
    prs: list[dict[str, Any]],
    acknowledged: set[str],
    now: dt.datetime,
    stale_hours: int,
) -> list[dict[str, Any]]:
    linked_text = "\n".join(str(pr.get("body") or "") for pr in prs)
    events: list[dict[str, Any]] = []
    threshold = now - dt.timedelta(hours=stale_hours)
    for issue in issues:
        labels = label_names(issue)
        if CLAIMED_LABEL not in labels or labels.intersection(BLOCKING_LABELS):
            continue
        number = int(issue["number"])
        if re.search(rf"(?<!\d)#{number}(?!\d)", linked_text):
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
    state = read_state(state_dir)
    acknowledged = set(state.get("acknowledged_event_ids") or [])

    run(["git", "fetch", "origin", "main", "--prune"], cwd=control_repo)
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
            "number,title,body,headRefName,headRefOid,labels,reviewDecision,isDraft,updatedAt,url",
        ]
    )

    ready = [issue for issue in issues if is_ready(issue)]
    agent_prs = [pr for pr in prs if is_agent_pull_request(pr)]
    events = pull_request_events(args.repo, prs, acknowledged)
    events.extend(issue_resume_events(args.repo, issues, acknowledged))
    now = dt.datetime.now(dt.timezone.utc)
    events.extend(
        stale_claim_events(
            issues, prs, acknowledged, now=now, stale_hours=args.stale_hours
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
        "queue_paused": queue_paused,
        "queue_paused_by_open_agent_pr": queue_paused and bool(agent_prs),
        "ready_issues": ready,
        "suggested_batches": batches,
        **admission,
        "active_agent_prs": agent_prs,
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
    }


def acknowledge(args: argparse.Namespace) -> None:
    state_dir = Path(args.state_dir).resolve()
    with Path(args.snapshot).open(encoding="utf-8") as handle:
        snapshot = json.load(handle)
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
    inspect_parser.add_argument("--max-batch-size", type=int, default=5)
    inspect_parser.add_argument(
        "--max-active-batches", type=int, default=DEFAULT_MAX_ACTIVE_BATCHES
    )
    inspect_parser.add_argument("--stale-hours", type=int, default=6)
    inspect_parser.add_argument("--pretty", action="store_true")

    acknowledge_parser = commands.add_parser("acknowledge")
    acknowledge_parser.add_argument("--snapshot", required=True)
    acknowledge_parser.add_argument("--state-dir", required=True)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "inspect":
            result = inspect(args)
            json.dump(result, sys.stdout, indent=2 if args.pretty else None, sort_keys=True)
            sys.stdout.write("\n")
        else:
            acknowledge(args)
    except (CommandError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"issue-agent preflight failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
