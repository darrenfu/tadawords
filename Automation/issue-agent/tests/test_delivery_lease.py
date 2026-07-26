#!/usr/bin/env python3

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[3]
SCRIPT = REPOSITORY_ROOT / "Scripts" / "delivery-lease.py"
SPEC = importlib.util.spec_from_file_location("delivery_lease", SCRIPT)
assert SPEC and SPEC.loader
delivery_lease = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = delivery_lease
SPEC.loader.exec_module(delivery_lease)


class DeliveryLeaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.store = delivery_lease.LeaseStore(Path(self.temporary.name))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def acquire(self, owner: str, now: int = 100):
        return self.store.acquire(
            kind="pr-writer",
            resource="PR-141",
            owner=owner,
            ttl_seconds=60,
            metadata={"issue": "141", "branch": "agent/pipeline"},
            now=now,
        )

    def test_same_owner_can_renew_and_release(self):
        first = self.acquire("session-a")
        renewed = self.acquire("session-a", now=120)
        self.assertEqual(first["created_at"], renewed["created_at"])
        self.assertEqual(renewed["expires_at"], 180)
        released = self.store.release(
            kind="pr-writer", resource="PR-141", owner="session-a"
        )
        self.assertEqual(released["owner"], "session-a")
        self.assertIsNone(self.store.read("pr-writer", "PR-141"))

    def test_live_other_owner_fails_closed(self):
        self.acquire("session-a")
        with self.assertRaises(delivery_lease.LeaseConflict):
            self.acquire("session-b", now=120)

    def test_expired_lease_can_be_reclaimed(self):
        self.acquire("session-a")
        reclaimed = self.acquire("session-b", now=161)
        self.assertEqual(reclaimed["owner"], "session-b")
        self.assertEqual(reclaimed["created_at"], 161)

    def test_release_requires_exact_owner(self):
        self.acquire("session-a")
        with self.assertRaises(delivery_lease.LeaseConflict):
            self.store.release(
                kind="pr-writer", resource="PR-141", owner="session-b"
            )

    def test_path_components_cannot_escape_store(self):
        with self.assertRaises(delivery_lease.LeaseError):
            self.store.path("pr-writer", "../outside")


if __name__ == "__main__":
    unittest.main()
