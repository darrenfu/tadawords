#!/usr/bin/env python3

"""Local single-writer and shared delivery-lane leases.

GitHub Issues, branches, and PRs remain the durable cross-machine ownership
record. This tool serializes writers, Xcode, signing, devices, and TestFlight on
one Mac without exposing credentials or device data.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


ALLOWED_KINDS = {
    "pr-writer",
    "heavy-xcode",
    "signing-archive",
    "iphone",
    "ipad",
    "testflight",
}
SAFE_COMPONENT = re.compile(r"^[A-Za-z0-9._-]+$")
DEFAULT_ROOT = (
    Path.home()
    / "Library"
    / "Application Support"
    / "TadaWordsDelivery"
    / "leases"
)


class LeaseError(RuntimeError):
    pass


class LeaseConflict(LeaseError):
    pass


def validate_component(label: str, value: str) -> str:
    if not value or not SAFE_COMPONENT.fullmatch(value):
        raise LeaseError(
            f"{label} must contain only letters, numbers, dot, underscore, or hyphen"
        )
    return value


class LeaseStore:
    def __init__(self, root: Path) -> None:
        self.root = root.expanduser().resolve()

    def path(self, kind: str, resource: str) -> Path:
        validate_component("kind", kind)
        validate_component("resource", resource)
        if kind not in ALLOWED_KINDS:
            raise LeaseError(f"unsupported lease kind: {kind}")
        return self.root / f"{kind}--{resource}.json"

    @contextmanager
    def locked(self) -> Iterator[None]:
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.root, 0o700)
        lock_path = self.root / ".manager.lock"
        with lock_path.open("a+", encoding="utf-8") as stream:
            os.chmod(lock_path, 0o600)
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)

    def read(self, kind: str, resource: str) -> dict[str, Any] | None:
        path = self.path(kind, resource)
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return None
        except (OSError, json.JSONDecodeError) as error:
            raise LeaseError(f"cannot read lease {path}: {error}") from error
        if not isinstance(payload, dict):
            raise LeaseError(f"invalid lease payload: {path}")
        return payload

    def write(self, path: Path, payload: dict[str, Any]) -> None:
        file_descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.", dir=self.root
        )
        temporary = Path(temporary_name)
        try:
            with os.fdopen(file_descriptor, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, indent=2, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
            directory_descriptor = os.open(self.root, os.O_RDONLY)
            try:
                os.fsync(directory_descriptor)
            finally:
                os.close(directory_descriptor)
        finally:
            temporary.unlink(missing_ok=True)

    def acquire(
        self,
        *,
        kind: str,
        resource: str,
        owner: str,
        ttl_seconds: int,
        metadata: dict[str, Any],
        now: int | None = None,
    ) -> dict[str, Any]:
        validate_component("owner", owner)
        if ttl_seconds < 60 or ttl_seconds > 86_400:
            raise LeaseError("ttl-seconds must be between 60 and 86400")
        current_time = int(time.time()) if now is None else now
        path = self.path(kind, resource)
        with self.locked():
            existing = self.read(kind, resource)
            if (
                existing
                and int(existing.get("expires_at", 0)) > current_time
                and existing.get("owner") != owner
            ):
                raise LeaseConflict(
                    f"{kind}:{resource} is held by {existing.get('owner')} "
                    f"until {existing.get('expires_at')}"
                )
            created_at = (
                int(existing.get("created_at", current_time))
                if existing and existing.get("owner") == owner
                else current_time
            )
            payload: dict[str, Any] = {
                "schema_version": 1,
                "kind": kind,
                "resource": resource,
                "owner": owner,
                "created_at": created_at,
                "renewed_at": current_time,
                "expires_at": current_time + ttl_seconds,
            }
            payload.update({key: value for key, value in metadata.items() if value})
            self.write(path, payload)
            return payload

    def release(self, *, kind: str, resource: str, owner: str) -> dict[str, Any]:
        validate_component("owner", owner)
        path = self.path(kind, resource)
        with self.locked():
            existing = self.read(kind, resource)
            if existing is None:
                raise LeaseError(f"lease does not exist: {kind}:{resource}")
            if existing.get("owner") != owner:
                raise LeaseConflict(
                    f"{kind}:{resource} is owned by {existing.get('owner')}, not {owner}"
                )
            path.unlink()
            directory_descriptor = os.open(self.root, os.O_RDONLY)
            try:
                os.fsync(directory_descriptor)
            finally:
                os.close(directory_descriptor)
            return existing


def parser() -> argparse.ArgumentParser:
    command_parser = argparse.ArgumentParser(description=__doc__)
    command_parser.add_argument(
        "--root",
        type=Path,
        default=Path(os.environ.get("TADA_DELIVERY_LEASE_ROOT", DEFAULT_ROOT)),
        help="override the local lease store",
    )
    commands = command_parser.add_subparsers(dest="command", required=True)

    def common(subparser: argparse.ArgumentParser, *, owner: bool) -> None:
        subparser.add_argument("--kind", required=True, choices=sorted(ALLOWED_KINDS))
        subparser.add_argument("--resource", required=True)
        if owner:
            subparser.add_argument("--owner", required=True)

    acquire = commands.add_parser("acquire")
    common(acquire, owner=True)
    acquire.add_argument("--ttl-seconds", type=int, default=14_400)
    acquire.add_argument("--issue")
    acquire.add_argument("--pr")
    acquire.add_argument("--branch")
    acquire.add_argument("--head")
    acquire.add_argument("--note")

    release = commands.add_parser("release")
    common(release, owner=True)

    status = commands.add_parser("status")
    common(status, owner=False)
    return command_parser


def main() -> int:
    arguments = parser().parse_args()
    store = LeaseStore(arguments.root)
    try:
        if arguments.command == "acquire":
            payload = store.acquire(
                kind=arguments.kind,
                resource=arguments.resource,
                owner=arguments.owner,
                ttl_seconds=arguments.ttl_seconds,
                metadata={
                    "issue": arguments.issue,
                    "pr": arguments.pr,
                    "branch": arguments.branch,
                    "head": arguments.head,
                    "note": arguments.note,
                    "pid": os.getpid(),
                },
            )
        elif arguments.command == "release":
            released = store.release(
                kind=arguments.kind,
                resource=arguments.resource,
                owner=arguments.owner,
            )
            payload = {"released": True, "lease": released}
        else:
            with store.locked():
                lease = store.read(arguments.kind, arguments.resource)
            payload = {
                "active": bool(
                    lease and int(lease.get("expires_at", 0)) > int(time.time())
                ),
                "lease": lease,
            }
    except LeaseConflict as error:
        print(str(error), file=sys.stderr)
        return 2
    except LeaseError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
