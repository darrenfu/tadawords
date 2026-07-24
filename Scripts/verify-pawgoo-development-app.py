#!/usr/bin/env python3
"""Fail closed unless an app is the exact PawGoo Development candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class VerificationError(RuntimeError):
    pass


CANONICAL_IDENTITY = {
    "team_id": "7R78Q4HP86",
    "team_name": "PawGoo LLC",
    "application_identifier_prefix": "7R78Q4HP86",
    "bundle_id": "app.tadawords.app",
    "localqa_bundle_id": "com.tadawords.app.localqa",
    "ui_test_bundle_id": "app.tadawords.app.uitests",
    "localqa_ui_test_bundle_id": "com.tadawords.app.uitests",
    "device_tests_bundle_id": "com.tadawords.app.devicetests",
    "icloud_container": "iCloud.com.tadawords.app",
    "voiceprint_service": "com.tadawords.device-voiceprints",
}

CANONICAL_DEVELOPMENT_ENTITLEMENT_CONTRACT = {
    "required_exact": {
        "application-identifier": "${APP_IDENTIFIER_PREFIX}.app.tadawords.app",
        "aps-environment": "development",
        "com.apple.developer.devicecheck.appattest-environment": "development",
        "com.apple.developer.icloud-container-environment": "Development",
        "com.apple.developer.icloud-container-identifiers": [
            "iCloud.com.tadawords.app"
        ],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.team-identifier": "${TEAM_ID}",
        "get-task-allow": True,
        "keychain-access-groups": [
            "${APP_IDENTIFIER_PREFIX}.app.tadawords.app"
        ],
    },
    "optional_exact": {
        "com.apple.developer.icloud-container-development-container-identifiers": [
            "iCloud.com.tadawords.app"
        ],
        "com.apple.developer.ubiquity-kvstore-identifier": (
            "${APP_IDENTIFIER_PREFIX}.app.tadawords.app"
        ),
    },
    "allowed_keys": [
        "application-identifier",
        "aps-environment",
        "com.apple.developer.devicecheck.appattest-environment",
        "com.apple.developer.icloud-container-development-container-identifiers",
        "com.apple.developer.icloud-container-environment",
        "com.apple.developer.icloud-container-identifiers",
        "com.apple.developer.icloud-services",
        "com.apple.developer.team-identifier",
        "com.apple.developer.ubiquity-kvstore-identifier",
        "get-task-allow",
        "keychain-access-groups",
    ],
}

APPLE_PROVISIONING_SIGNER_SHA256 = (
    "c0abbb34427f881028f3c1a7194c9c2b0202e66fcb7d2616acc6ff776351b0e9"
)


def run(command: list[str]) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        detail = (result.stderr or result.stdout).decode(errors="replace").strip()
        raise VerificationError(f"command failed ({' '.join(command)}): {detail}")
    return result


def read_plist(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise VerificationError(f"invalid or missing property list: {path}: {error}") from error
    if not isinstance(value, dict):
        raise VerificationError(f"property list root must be a dictionary: {path}")
    return value


def read_plist_bytes(payload: bytes, label: str) -> dict[str, Any]:
    try:
        value = plistlib.loads(payload)
    except plistlib.InvalidFileException as error:
        raise VerificationError(f"{label} is not a valid property list") from error
    if not isinstance(value, dict):
        raise VerificationError(f"{label} property list root must be a dictionary")
    return value


def tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(
        root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()
    ):
        relative = path.relative_to(root).as_posix().encode()
        mode = f"{path.lstat().st_mode & 0o7777:o}".encode()
        if path.is_symlink():
            digest.update(
                b"L\0" + relative + b"\0" + mode + b"\0"
                + os.readlink(path).encode() + b"\0"
            )
        elif path.is_dir():
            digest.update(b"D\0" + relative + b"\0" + mode + b"\0")
        elif path.is_file():
            digest.update(b"F\0" + relative + b"\0" + mode + b"\0")
            try:
                with path.open("rb") as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(block)
            except OSError as error:
                raise VerificationError(
                    f"could not hash app artifact entry: {path}"
                ) from error
            digest.update(b"\0")
        else:
            raise VerificationError(
                f"unsupported special file in app artifact: {path}"
            )
    return digest.hexdigest()


def snapshot_app(app: Path, destination: Path) -> str:
    before = tree_sha256(app)
    try:
        shutil.copytree(app, destination, symlinks=True)
    except OSError as error:
        raise VerificationError("could not snapshot app artifact") from error
    after = tree_sha256(app)
    snapshot = tree_sha256(destination)
    if before != after or before != snapshot:
        raise VerificationError("app artifact changed while it was being snapshotted")
    return snapshot


def load_policy(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise VerificationError(f"invalid or missing release policy: {path}: {error}") from error
    if not isinstance(value, dict):
        raise VerificationError("release policy root must be an object")
    for key, expected in CANONICAL_IDENTITY.items():
        if value.get(key) != expected:
            raise VerificationError(
                f"release policy identity mismatch for {key}; "
                f"expected={expected!r} actual={value.get(key)!r}"
            )
    if (
        value.get("development_signed_entitlements")
        != CANONICAL_DEVELOPMENT_ENTITLEMENT_CONTRACT
    ):
        raise VerificationError(
            "release policy Development entitlement contract is not canonical"
        )
    return value


def expand_tokens(value: Any, policy: dict[str, Any]) -> Any:
    if isinstance(value, str):
        return value.replace("${TEAM_ID}", str(policy["team_id"])).replace(
            "${APP_IDENTIFIER_PREFIX}",
            str(policy["application_identifier_prefix"]),
        )
    if isinstance(value, list):
        return [expand_tokens(item, policy) for item in value]
    if isinstance(value, dict):
        return {key: expand_tokens(item, policy) for key, item in value.items()}
    return value


def validate_commit(commit: str) -> None:
    if not re.fullmatch(r"[0-9a-fA-F]{40}", commit):
        raise VerificationError("expected commit must be a full 40-character hexadecimal SHA")


def validate_requested_device_udids(device_udids: list[str]) -> None:
    if not device_udids or any(not item.strip() for item in device_udids):
        raise VerificationError("at least one non-empty --device-udid is required")
    if len(device_udids) != len(set(device_udids)):
        raise VerificationError("--device-udid values must be unique")


def validate_info(
    info: dict[str, Any],
    expected_version: str,
    expected_build: str,
    expected_commit: str,
    policy: dict[str, Any],
) -> None:
    expected = {
        "CFBundleShortVersionString": expected_version,
        "CFBundleVersion": expected_build,
        "TadaWordsGitCommit": expected_commit,
        "CFBundleIdentifier": policy["bundle_id"],
    }
    for key, wanted in expected.items():
        actual = info.get(key)
        if actual != wanted:
            raise VerificationError(
                f"app Info.plist mismatch for {key}; expected={wanted!r} actual={actual!r}"
            )


def validate_macho_metadata(platform_output: str, architectures: list[str]) -> None:
    platforms = re.findall(
        r"^\s*platform\s+(\S+)\s*$", platform_output, flags=re.MULTILINE
    )
    if not platforms or set(platforms) != {"IOS"}:
        raise VerificationError(
            "app executable is not an iPhoneOS device binary; "
            f"platforms={sorted(set(platforms))}"
        )
    if architectures != ["arm64"]:
        raise VerificationError(
            "app executable must contain only the arm64 device architecture; "
            f"architectures={architectures}"
        )


def validate_installable_bundle(app: Path, info: dict[str, Any]) -> None:
    expected_info = {
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "UIDeviceFamily": [1, 2],
        "CFBundlePackageType": "APPL",
    }
    for key, expected in expected_info.items():
        actual = info.get(key)
        if actual != expected:
            raise VerificationError(
                f"app Info.plist mismatch for {key}; "
                f"expected={expected!r} actual={actual!r}"
            )

    executable_name = info.get("CFBundleExecutable")
    if (
        not isinstance(executable_name, str)
        or not executable_name
        or Path(executable_name).name != executable_name
    ):
        raise VerificationError("app Info.plist has an invalid CFBundleExecutable")
    executable = app / executable_name
    if (
        not executable.is_file()
        or executable.is_symlink()
        or executable.stat().st_mode & 0o111 == 0
    ):
        raise VerificationError(
            "app executable is missing, linked, or not executable"
        )

    platform_output = run(
        ["xcrun", "vtool", "-show-build", str(executable)]
    ).stdout.decode(errors="replace")
    architectures = (
        run(["xcrun", "lipo", "-archs", str(executable)])
        .stdout.decode(errors="replace")
        .split()
    )
    validate_macho_metadata(platform_output, architectures)


def validate_entitlements(
    entitlements: Any,
    policy: dict[str, Any],
    *,
    label: str,
) -> None:
    if not isinstance(entitlements, dict):
        raise VerificationError(f"{label} entitlements must be a dictionary")
    contract = policy["development_signed_entitlements"]
    allowed = set(contract.get("allowed_keys", []))
    unexpected = sorted(set(entitlements) - allowed)
    if unexpected:
        raise VerificationError(f"unexpected {label} entitlements: {unexpected}")

    required = expand_tokens(contract.get("required_exact", {}), policy)
    for key, expected in required.items():
        actual = entitlements.get(key)
        if actual != expected:
            raise VerificationError(
                f"{label} entitlement mismatch for {key}; "
                f"expected={expected!r} actual={actual!r}"
            )

    optional = expand_tokens(contract.get("optional_exact", {}), policy)
    for key, expected in optional.items():
        if key in entitlements and entitlements[key] != expected:
            raise VerificationError(
                f"{label} entitlement mismatch for {key}; "
                f"expected={expected!r} actual={entitlements[key]!r}"
            )


def parse_signature_details(payload: bytes) -> dict[str, str]:
    details: dict[str, str] = {}
    for line in payload.decode(errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        details[key.strip()] = value.strip()
    return details


def validate_signature_details(details: dict[str, str], policy: dict[str, Any]) -> None:
    expected = {
        "TeamIdentifier": str(policy["team_id"]),
        "Identifier": str(policy["bundle_id"]),
    }
    for key, wanted in expected.items():
        actual = details.get(key)
        if actual != wanted:
            raise VerificationError(
                f"code signature mismatch for {key}; expected={wanted!r} actual={actual!r}"
            )


def normalized_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def validate_profile_authorization(
    entitlements: Any,
    policy: dict[str, Any],
) -> None:
    """Validate the Development profile's authorization envelope.

    A provisioning profile is intentionally broader than the entitlements sealed
    into the app.  The signed app remains least privilege; this function accepts
    only the narrow Apple-issued wildcard forms that authorize that exact app.
    """
    if not isinstance(entitlements, dict):
        raise VerificationError(
            "provisioning profile entitlements must be a dictionary"
        )

    allowed_keys = {
        "application-identifier",
        "aps-environment",
        "com.apple.developer.devicecheck.appattest-environment",
        "com.apple.developer.icloud-container-development-container-identifiers",
        "com.apple.developer.icloud-container-environment",
        "com.apple.developer.icloud-container-identifiers",
        "com.apple.developer.icloud-services",
        "com.apple.developer.team-identifier",
        "com.apple.developer.ubiquity-container-identifiers",
        "com.apple.developer.ubiquity-kvstore-identifier",
        "get-task-allow",
        "keychain-access-groups",
    }
    unexpected = sorted(set(entitlements) - allowed_keys)
    if unexpected:
        raise VerificationError(
            f"unexpected provisioning profile entitlements: {unexpected}"
        )

    team_id = str(policy["team_id"])
    bundle_id = str(policy["bundle_id"])
    container = str(policy["icloud_container"])
    required_exact = {
        "application-identifier": f"{team_id}.{bundle_id}",
        "aps-environment": "development",
        "com.apple.developer.icloud-container-development-container-identifiers": [
            container
        ],
        "com.apple.developer.icloud-container-identifiers": [container],
        "com.apple.developer.team-identifier": team_id,
        "com.apple.developer.ubiquity-container-identifiers": [container],
        "com.apple.developer.ubiquity-kvstore-identifier": f"{team_id}.*",
        "get-task-allow": True,
    }
    for key, expected in required_exact.items():
        actual = entitlements.get(key)
        if actual != expected:
            raise VerificationError(
                "provisioning profile entitlement mismatch for "
                f"{key}; expected={expected!r} actual={actual!r}"
            )

    app_attest_environments = entitlements.get(
        "com.apple.developer.devicecheck.appattest-environment"
    )
    if isinstance(app_attest_environments, str):
        app_attest_authorized = app_attest_environments == "development"
    elif isinstance(app_attest_environments, list):
        app_attest_values = set(app_attest_environments)
        app_attest_authorized = (
            all(isinstance(item, str) for item in app_attest_environments)
            and len(app_attest_values) == len(app_attest_environments)
            and "development" in app_attest_values
            and app_attest_values <= {"development", "production"}
        )
    else:
        app_attest_authorized = False
    if not app_attest_authorized:
        raise VerificationError(
            "provisioning profile entitlement mismatch for "
            "com.apple.developer.devicecheck.appattest-environment; "
            "expected a narrow Apple-issued value that authorizes development"
        )

    environments = entitlements.get(
        "com.apple.developer.icloud-container-environment"
    )
    if (
        not isinstance(environments, list)
        or not all(isinstance(item, str) for item in environments)
        or set(environments) != {"Development", "Production"}
    ):
        raise VerificationError(
            "provisioning profile entitlement mismatch for "
            "com.apple.developer.icloud-container-environment; "
            "expected both Development and Production authorization"
        )

    services = entitlements.get("com.apple.developer.icloud-services")
    if services != "*" and services != ["CloudKit"]:
        raise VerificationError(
            "provisioning profile entitlement mismatch for "
            "com.apple.developer.icloud-services; expected '*' or ['CloudKit']"
        )

    keychain_groups = entitlements.get("keychain-access-groups")
    if (
        not isinstance(keychain_groups, list)
        or not all(isinstance(item, str) for item in keychain_groups)
        or set(keychain_groups) not in (
            {f"{team_id}.*"},
            {f"{team_id}.*", "com.apple.token"},
        )
    ):
        raise VerificationError(
            "provisioning profile entitlement mismatch for keychain-access-groups"
        )


def validate_app_authorized_by_profile(
    app_entitlements: dict[str, Any],
    profile_entitlements: dict[str, Any],
) -> None:
    """Bind each sealed app entitlement to the profile that authorizes it."""
    exact_or_member_keys = {
        "aps-environment",
        "com.apple.developer.devicecheck.appattest-environment",
        "com.apple.developer.icloud-container-environment",
    }
    list_subset_keys = {
        "com.apple.developer.icloud-container-development-container-identifiers",
        "com.apple.developer.icloud-container-identifiers",
    }
    for key in exact_or_member_keys:
        app_value = app_entitlements.get(key)
        profile_value = profile_entitlements.get(key)
        authorized = (
            app_value in profile_value
            if isinstance(profile_value, list)
            else app_value == profile_value
        )
        if not authorized:
            raise VerificationError(
                f"signed app entitlement is not authorized by profile: {key}"
            )

    for key in list_subset_keys:
        app_value = app_entitlements.get(key)
        if app_value is None:
            continue
        profile_value = profile_entitlements.get(key)
        if (
            not isinstance(app_value, list)
            or not isinstance(profile_value, list)
            or not set(app_value).issubset(set(profile_value))
        ):
            raise VerificationError(
                f"signed app entitlement is not authorized by profile: {key}"
            )

    app_services = app_entitlements.get("com.apple.developer.icloud-services")
    profile_services = profile_entitlements.get(
        "com.apple.developer.icloud-services"
    )
    if profile_services != "*" and (
        not isinstance(app_services, list)
        or not isinstance(profile_services, list)
        or not set(app_services).issubset(set(profile_services))
    ):
        raise VerificationError(
            "signed app entitlement is not authorized by profile: "
            "com.apple.developer.icloud-services"
        )

    app_keychain_groups = app_entitlements.get("keychain-access-groups", [])
    profile_keychain_groups = profile_entitlements.get(
        "keychain-access-groups", []
    )
    if not isinstance(app_keychain_groups, list) or not isinstance(
        profile_keychain_groups, list
    ):
        raise VerificationError(
            "signed app keychain-access-groups are not authorized by profile"
        )
    for group in app_keychain_groups:
        if not isinstance(group, str) or not any(
            authorization == group
            or (
                isinstance(authorization, str)
                and authorization.endswith("*")
                and group.startswith(authorization[:-1])
            )
            for authorization in profile_keychain_groups
        ):
            raise VerificationError(
                "signed app keychain-access-groups are not authorized by profile"
            )

    app_kvstore = app_entitlements.get(
        "com.apple.developer.ubiquity-kvstore-identifier"
    )
    if app_kvstore is not None:
        profile_kvstore = profile_entitlements.get(
            "com.apple.developer.ubiquity-kvstore-identifier"
        )
        authorized = app_kvstore == profile_kvstore or (
            isinstance(app_kvstore, str)
            and isinstance(profile_kvstore, str)
            and profile_kvstore.endswith("*")
            and app_kvstore.startswith(profile_kvstore[:-1])
        )
        if not authorized:
            raise VerificationError(
                "signed app entitlement is not authorized by profile: "
                "com.apple.developer.ubiquity-kvstore-identifier"
            )


def validate_signing_certificate(
    leaf_certificate: bytes,
    profile: dict[str, Any],
) -> None:
    certificates = profile.get("DeveloperCertificates")
    if not isinstance(certificates, list) or not certificates or not all(
        isinstance(item, bytes) and item for item in certificates
    ):
        raise VerificationError(
            "provisioning profile has no valid DeveloperCertificates"
        )
    if not leaf_certificate or leaf_certificate not in certificates:
        raise VerificationError(
            "app signing certificate is not authorized by provisioning profile"
        )


def validate_profile(
    profile: Any,
    policy: dict[str, Any],
    device_udids: list[str],
    *,
    now: datetime | None = None,
) -> None:
    if not isinstance(profile, dict):
        raise VerificationError("embedded provisioning profile must be a dictionary")

    expected_scalars = {
        "TeamName": str(policy["team_name"]),
    }
    for key, expected in expected_scalars.items():
        actual = profile.get(key)
        if actual != expected:
            raise VerificationError(
                f"provisioning profile mismatch for {key}; "
                f"expected={expected!r} actual={actual!r}"
            )

    expected_arrays = {
        "TeamIdentifier": [str(policy["team_id"])],
        "ApplicationIdentifierPrefix": [
            str(policy["application_identifier_prefix"])
        ],
    }
    for key, expected in expected_arrays.items():
        actual = profile.get(key)
        if actual != expected:
            raise VerificationError(
                f"provisioning profile mismatch for {key}; "
                f"expected={expected!r} actual={actual!r}"
            )

    for key in ("Name", "UUID"):
        if not isinstance(profile.get(key), str) or not profile[key].strip():
            raise VerificationError(f"provisioning profile has no valid {key}")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise VerificationError("provisioning profile has no valid ExpirationDate")
    reference = normalized_utc(now or datetime.now(timezone.utc))
    if normalized_utc(expiration) <= reference:
        raise VerificationError(
            "provisioning profile is expired; "
            f"expiration={normalized_utc(expiration).isoformat()} now={reference.isoformat()}"
        )

    if profile.get("ProvisionsAllDevices") is True:
        raise VerificationError("embedded profile is not a Development device profile")
    provisioned_devices = profile.get("ProvisionedDevices")
    if not isinstance(provisioned_devices, list) or not all(
        isinstance(item, str) and item for item in provisioned_devices
    ):
        raise VerificationError("provisioning profile has no valid ProvisionedDevices list")
    if len(provisioned_devices) != len(set(provisioned_devices)):
        raise VerificationError("provisioning profile device UDIDs must be unique")
    requested = set(device_udids)
    provisioned = set(provisioned_devices)
    if requested != provisioned:
        raise VerificationError(
            "provisioning profile device set differs from approved device UDIDs; "
            f"missing={sorted(requested - provisioned)} "
            f"unexpected={sorted(provisioned - requested)}"
        )

    validate_profile_authorization(
        profile.get("Entitlements"),
        policy,
    )
    certificates = profile.get("DeveloperCertificates")
    if not isinstance(certificates, list) or not certificates or not all(
        isinstance(item, bytes) and item for item in certificates
    ):
        raise VerificationError(
            "provisioning profile has no valid DeveloperCertificates"
        )


def signed_entitlements(app: Path) -> dict[str, Any]:
    result = run(["codesign", "-d", "--entitlements", ":-", str(app)])
    return read_plist_bytes(result.stdout, "signed entitlements")


def signature_details(app: Path) -> dict[str, str]:
    result = run(["codesign", "-dvvv", str(app)])
    payload = result.stderr or result.stdout
    return parse_signature_details(payload)


def signing_leaf_certificate(app: Path) -> bytes:
    with tempfile.TemporaryDirectory(prefix="tadawords-signing-certificate-") as temp:
        prefix = Path(temp) / "certificate"
        run(
            [
                "codesign",
                "-d",
                f"--extract-certificates={prefix}",
                str(app),
            ]
        )
        leaf = Path(f"{prefix}0")
        if not leaf.is_file():
            raise VerificationError(
                "codesign did not extract the app signing leaf certificate"
            )
        try:
            payload = leaf.read_bytes()
        except OSError as error:
            raise VerificationError(
                "could not read the app signing leaf certificate"
            ) from error
        if not payload:
            raise VerificationError("app signing leaf certificate is empty")
        return payload


def decode_profile(path: Path) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="tadawords-profile-cms-") as temp:
        directory = Path(temp)
        content = directory / "content.plist"
        signer_pem = directory / "signer.pem"
        signer_der = directory / "signer.der"

        # OpenSSL binds the decoded bytes to the CMS signature and extracts the
        # actual signer. Trust is evaluated separately on that exact signer.
        run(
            [
                "/usr/bin/openssl",
                "smime",
                "-verify",
                "-inform",
                "DER",
                "-noverify",
                "-in",
                str(path),
                "-out",
                str(content),
                "-signer",
                str(signer_pem),
            ]
        )
        run(
            [
                "/usr/bin/security",
                "verify-cert",
                "-c",
                str(signer_pem),
                "-p",
                "basic",
                "-L",
                "-q",
            ]
        )
        run(
            [
                "/usr/bin/openssl",
                "x509",
                "-in",
                str(signer_pem),
                "-outform",
                "DER",
                "-out",
                str(signer_der),
            ]
        )
        try:
            signer_payload = signer_der.read_bytes()
            payload = content.read_bytes()
        except OSError as error:
            raise VerificationError(
                "could not read trusted provisioning CMS output"
            ) from error
        validate_provisioning_signer_fingerprint(signer_payload)
        return read_plist_bytes(payload, "embedded provisioning profile")


def validate_provisioning_signer_fingerprint(signer_der: bytes) -> None:
    if not signer_der or (
        hashlib.sha256(signer_der).hexdigest()
        != APPLE_PROVISIONING_SIGNER_SHA256
    ):
        raise VerificationError(
            "embedded provisioning profile was not signed by the pinned "
            "Apple provisioning signer"
        )


def verify_app_snapshot(
    app: Path,
    expected_version: str,
    expected_build: str,
    expected_commit: str,
    device_udids: list[str],
    policy: dict[str, Any],
) -> None:
    info = read_plist(app / "Info.plist")
    validate_info(info, expected_version, expected_build, expected_commit, policy)
    validate_installable_bundle(app, info)
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    validate_signature_details(signature_details(app), policy)
    app_entitlements = signed_entitlements(app)
    validate_entitlements(app_entitlements, policy, label="signed app")

    profile_path = app / "embedded.mobileprovision"
    if not profile_path.is_file():
        raise VerificationError("signed app has no embedded.mobileprovision")
    profile = decode_profile(profile_path)
    validate_profile(profile, policy, device_udids)
    profile_entitlements = profile["Entitlements"]
    validate_app_authorized_by_profile(app_entitlements, profile_entitlements)
    validate_signing_certificate(signing_leaf_certificate(app), profile)


def verify_app(
    app: Path,
    expected_version: str,
    expected_build: str,
    expected_commit: str,
    device_udids: list[str],
    policy: dict[str, Any],
) -> str:
    validate_commit(expected_commit)
    if not expected_version or not expected_build:
        raise VerificationError("expected version and build must be non-empty")
    validate_requested_device_udids(device_udids)
    if not app.is_dir() or app.suffix != ".app":
        raise VerificationError(f"app bundle not found: {app}")

    with tempfile.TemporaryDirectory(prefix="tadawords-app-snapshot-") as temp:
        snapshot = Path(temp) / app.name
        artifact_digest = snapshot_app(app, snapshot)
        verify_app_snapshot(
            snapshot,
            expected_version,
            expected_build,
            expected_commit,
            device_udids,
            policy,
        )
        if tree_sha256(app) != artifact_digest:
            raise VerificationError("app artifact changed during verification")
        return artifact_digest


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Verify one signed normal-target PawGoo CloudKit Development app. "
            "The command only reads the artifact and never installs it."
        )
    )
    parser.add_argument("app", type=Path)
    parser.add_argument("version")
    parser.add_argument("build")
    parser.add_argument("commit")
    parser.add_argument(
        "--device-udid",
        action="append",
        required=True,
        help="Approved physical-device UDID that the embedded profile must cover; repeatable.",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        policy = load_policy(
            Path(__file__).resolve().parents[1]
            / "Config/release-candidate-policy.json"
        )
        artifact_digest = verify_app(
            arguments.app.resolve(),
            arguments.version,
            arguments.build,
            arguments.commit,
            arguments.device_udid,
            policy,
        )
    except VerificationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(
        "READY: PawGoo Development app matches the requested version/build/"
        "commit metadata, identity, iPhoneOS arm64, CloudKit, APNs, profile, "
        f"and device contract; app_tree_sha256={artifact_digest}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
