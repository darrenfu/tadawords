#!/usr/bin/env python3
"""Verify one immutable App Store release candidate without building or uploading it."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import io
import json
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


class PreflightError(RuntimeError):
    pass


def run(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        detail = result.stderr.decode(errors="replace").strip()
        raise PreflightError(f"command failed ({' '.join(command)}): {detail}")
    return result


def read_plist(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise PreflightError(f"invalid or missing property list: {path}: {error}") from error
    if not isinstance(value, dict):
        raise PreflightError(f"property list root must be a dictionary: {path}")
    return value


def assert_clean_repository(root: Path) -> str:
    head = run(["git", "rev-parse", "HEAD"], root).stdout.decode().strip()
    if len(head) != 40:
        raise PreflightError("git HEAD is not a full 40-character commit")
    status = run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all"], root
    ).stdout.decode()
    if status:
        raise PreflightError(f"release source is dirty:\n{status.rstrip()}")
    return head


def ensure_ignored_output(root: Path, output: Path) -> None:
    try:
        relative = output.resolve().relative_to(root.resolve())
    except ValueError:
        return
    result = subprocess.run(
        ["git", "check-ignore", "-q", "--", str(relative)], cwd=root
    )
    if result.returncode:
        raise PreflightError(
            "manifest path inside the repository must be git-ignored: " + str(output)
        )


def extract_yaml_scalar(text: str, key: str) -> set[str]:
    values: set[str] = set()
    prefix = key + ":"
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix):
            value = stripped[len(prefix) :].strip().strip('"\'')
            values.add(value)
    return values


def extract_pbx_values(text: str, key: str) -> set[str]:
    values: set[str] = set()
    prefix = key + " = "
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(prefix) and stripped.endswith(";"):
            values.add(stripped[len(prefix) : -1].strip('"'))
    return values


def validate_source_identity(root: Path, policy: dict[str, Any]) -> tuple[str, str, str]:
    info = read_plist(root / "Apps/TadaWordsApp/Info.plist")
    local_info = read_plist(root / "Apps/TadaWordsApp/InfoLocalQA.plist")
    version = str(info.get("CFBundleShortVersionString", ""))
    build = str(info.get("CFBundleVersion", ""))
    bundle_id = str(policy["bundle_id"])
    if not version or not build:
        raise PreflightError("production Info.plist has no version/build")
    for label, plist in (("production", info), ("LocalQA", local_info)):
        if str(plist.get("CFBundleShortVersionString", "")) != version:
            raise PreflightError(f"{label} source version does not match {version}")
        if str(plist.get("CFBundleVersion", "")) != build:
            raise PreflightError(f"{label} source build does not match {build}")
        if plist.get("TadaWordsGitCommit") != "$(TADA_GIT_COMMIT)":
            raise PreflightError(f"{label} source commit is not bound to TADA_GIT_COMMIT")

    project_text = (root / "project.yml").read_text()
    if extract_yaml_scalar(project_text, "MARKETING_VERSION") != {version}:
        raise PreflightError("project.yml marketing version is missing or mismatched")
    if extract_yaml_scalar(project_text, "CURRENT_PROJECT_VERSION") != {build}:
        raise PreflightError("project.yml build number is missing or mismatched")
    declared_bundles = extract_yaml_scalar(project_text, "PRODUCT_BUNDLE_IDENTIFIER")
    if bundle_id not in declared_bundles or f"{bundle_id}.localqa" not in declared_bundles:
        raise PreflightError("project.yml does not contain the expected production/LocalQA bundles")

    pbx_text = (root / "TadaWords.xcodeproj/project.pbxproj").read_text()
    if extract_pbx_values(pbx_text, "MARKETING_VERSION") != {version}:
        raise PreflightError("generated project marketing version is stale or mismatched")
    if extract_pbx_values(pbx_text, "CURRENT_PROJECT_VERSION") != {build}:
        raise PreflightError("generated project build number is stale or mismatched")
    pbx_bundles = extract_pbx_values(pbx_text, "PRODUCT_BUNDLE_IDENTIFIER")
    if bundle_id not in pbx_bundles or f"{bundle_id}.localqa" not in pbx_bundles:
        raise PreflightError("generated project has the wrong app bundle identity")
    return version, build, bundle_id


def safe_extract_tar(payload: bytes, destination: Path) -> None:
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
        for member in archive.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts:
                raise PreflightError(f"unsafe git archive member: {member.name}")
        archive.extractall(destination, filter="data")


def file_map(root: Path) -> dict[str, bytes]:
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in root.rglob("*")
        if path.is_file()
    }


def validate_generated_project(root: Path) -> None:
    archive = run(["git", "archive", "--format=tar", "HEAD"], root).stdout
    with tempfile.TemporaryDirectory(prefix="tadawords-generated-project-") as temporary:
        clean_root = Path(temporary) / "source"
        clean_root.mkdir()
        safe_extract_tar(archive, clean_root)
        shutil.rmtree(clean_root / "TadaWords.xcodeproj")
        run([str(clean_root / "Scripts/generate-xcode-project.sh")], clean_root)
        expected = file_map(clean_root / "TadaWords.xcodeproj")
        actual = file_map(root / "TadaWords.xcodeproj")
        if expected != actual:
            missing = sorted(set(expected) - set(actual))
            extra = sorted(set(actual) - set(expected))
            changed = sorted(
                path for path in set(expected) & set(actual) if expected[path] != actual[path]
            )
            raise PreflightError(
                "generated project differs from project.yml; "
                f"missing={missing} extra={extra} changed={changed}"
            )


def png_properties(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()[:33]
    if len(data) < 26 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise PreflightError(f"app icon is not a valid PNG: {path}")
    width, height = struct.unpack(">II", data[16:24])
    return width, height, data[25]


def validate_source_files(root: Path, policy: dict[str, Any]) -> str:
    for relative in policy["required_source_files"]:
        if not (root / relative).is_file():
            raise PreflightError(f"required source resource is missing: {relative}")
    icon = root / "Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    width, height, color_type = png_properties(icon)
    if (width, height) != (1024, 1024):
        raise PreflightError(f"app icon is {width}x{height}; expected 1024x1024")
    if color_type in {4, 6}:
        raise PreflightError("app icon has an alpha channel")
    if color_type == 3 and b"tRNS" in icon.read_bytes():
        raise PreflightError("palette app icon contains transparency")
    privacy = root / "Apps/TadaWordsApp/PrivacyInfo.xcprivacy"
    read_plist(privacy)
    source_entitlements = read_plist(root / "Apps/TadaWordsApp/TadaWords.entitlements")
    if source_entitlements != policy["source_entitlements"]:
        raise PreflightError("production source entitlements differ from release policy")
    return sha256_file(privacy)


def safe_extract_ipa(ipa: Path, destination: Path) -> Path:
    with zipfile.ZipFile(ipa) as archive:
        for info in archive.infolist():
            path = PurePosixPath(info.filename)
            mode = info.external_attr >> 16
            if path.is_absolute() or ".." in path.parts or (mode & 0o170000) == 0o120000:
                raise PreflightError(f"unsafe IPA member: {info.filename}")
        archive.extractall(destination)
    apps = list((destination / "Payload").glob("*.app"))
    if len(apps) != 1:
        raise PreflightError(f"IPA must contain exactly one Payload app; found {len(apps)}")
    return apps[0]


def resolve_archive_app(archive: Path, expected_team: str) -> tuple[Path, dict[str, Any]]:
    if not archive.is_dir() or archive.suffix != ".xcarchive":
        raise PreflightError(f"archive is not an .xcarchive directory: {archive}")
    metadata = read_plist(archive / "Info.plist")
    properties = metadata.get("ApplicationProperties")
    if not isinstance(properties, dict):
        raise PreflightError("archive has no ApplicationProperties")
    application_path = properties.get("ApplicationPath")
    if not isinstance(application_path, str) or not application_path.endswith(".app"):
        raise PreflightError("archive ApplicationPath is invalid")
    app = archive / "Products" / application_path
    if not app.is_dir():
        raise PreflightError(f"archived app is missing: {app}")
    if properties.get("Team") != expected_team:
        raise PreflightError(
            f"archive team mismatch; expected={expected_team} actual={properties.get('Team')}"
        )
    if not properties.get("SigningIdentity"):
        raise PreflightError("archive does not record a signing identity")
    return app, properties


def resolve_exported_app(exported: Path, temporary: Path) -> Path:
    if exported.is_dir() and exported.suffix == ".app":
        return exported
    if exported.is_file() and exported.suffix == ".ipa":
        return safe_extract_ipa(exported, temporary)
    raise PreflightError("--exported-app must be a signed .app directory or .ipa file")


def verify_signed_identity(
    verifier: Path,
    app: Path,
    version: str,
    build: str,
    commit: str,
    bundle_id: str,
    team_id: str,
) -> None:
    result = subprocess.run(
        [str(verifier), str(app), version, build, commit, bundle_id, team_id],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).decode(errors="replace").strip()
        raise PreflightError(f"signed app identity verification failed: {detail}")


def expand_tokens(value: Any, team_id: str) -> Any:
    if isinstance(value, str):
        return value.replace("${TEAM_ID}", team_id)
    if isinstance(value, list):
        return [expand_tokens(item, team_id) for item in value]
    if isinstance(value, dict):
        return {key: expand_tokens(item, team_id) for key, item in value.items()}
    return value


def signed_entitlements(app: Path) -> dict[str, Any]:
    result = run(["codesign", "-d", "--entitlements", ":-", str(app)])
    try:
        value = plistlib.loads(result.stdout)
    except plistlib.InvalidFileException as error:
        raise PreflightError(f"codesign returned invalid entitlements for {app}") from error
    if not isinstance(value, dict):
        raise PreflightError(f"signed entitlements are not a dictionary: {app}")
    return value


def validate_signed_entitlements(
    entitlements: dict[str, Any],
    policy: dict[str, Any],
    team_id: str,
    artifact_kind: str = "export",
) -> None:
    signed_policy = policy["signed_entitlements"]
    allowed = set(signed_policy["allowed_keys"])
    unexpected = sorted(set(entitlements) - allowed)
    if unexpected:
        raise PreflightError(f"unexpected signed entitlements: {unexpected}")
    allowed_values = expand_tokens(
        signed_policy.get("artifact_allowed_values", {}).get(artifact_kind, {}),
        team_id,
    )
    required = expand_tokens(signed_policy["required_exact"], team_id)
    for key, expected in required.items():
        if key in allowed_values:
            if entitlements.get(key) not in allowed_values[key]:
                raise PreflightError(
                    f"signed entitlement mismatch for {key}; "
                    f"allowed={allowed_values[key]!r} actual={entitlements.get(key)!r}"
                )
            continue
        if entitlements.get(key) != expected:
            raise PreflightError(
                f"signed entitlement mismatch for {key}; "
                f"expected={expected!r} actual={entitlements.get(key)!r}"
            )
    optional = expand_tokens(signed_policy.get("optional_exact", {}), team_id)
    for key, expected in optional.items():
        if key in allowed_values:
            if key in entitlements and entitlements[key] not in allowed_values[key]:
                raise PreflightError(
                    f"signed entitlement mismatch for {key}; "
                    f"allowed={allowed_values[key]!r} actual={entitlements[key]!r}"
                )
            continue
        if key in entitlements and entitlements[key] != expected:
            raise PreflightError(
                f"signed entitlement mismatch for {key}; "
                f"expected={expected!r} actual={entitlements[key]!r}"
            )


def matching_files(root: Path, pattern: str) -> list[Path]:
    return [
        path
        for path in root.rglob("*")
        if path.is_file()
        and (
            fnmatch.fnmatch(path.relative_to(root).as_posix(), pattern)
            or fnmatch.fnmatch(path.name, pattern)
        )
    ]


def validate_app_resources(
    app: Path, root: Path, policy: dict[str, Any], expected_privacy: dict[str, Any]
) -> None:
    info = read_plist(app / "Info.plist")
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not (app / executable).is_file():
        raise PreflightError(f"app main executable is missing: {app}")
    for pattern in policy["required_app_resources"]:
        if not matching_files(app, pattern):
            raise PreflightError(f"required app resource pattern is missing: {pattern}")
    bundled_privacy = read_plist(app / "PrivacyInfo.xcprivacy")
    if bundled_privacy != expected_privacy:
        raise PreflightError("bundled privacy manifest differs from source")
    icon_names = info.get("CFBundleIcons") or info.get("CFBundleIcons~ipad")
    if not icon_names:
        raise PreflightError("compiled app Info.plist contains no app icon declaration")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode()
        if path.is_symlink():
            digest.update(b"L\0" + relative + b"\0" + os.readlink(path).encode() + b"\0")
        elif path.is_file():
            digest.update(b"F\0" + relative + b"\0")
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            digest.update(b"\0")
    return digest.hexdigest()


def artifact_manifest(app: Path, entitlements: dict[str, Any]) -> dict[str, Any]:
    info = read_plist(app / "Info.plist")
    executable = app / str(info["CFBundleExecutable"])
    return {
        "path": str(app.resolve()),
        "app_tree_sha256": tree_sha256(app),
        "executable_sha256": sha256_file(executable),
        "info_plist_sha256": sha256_file(app / "Info.plist"),
        "privacy_manifest_sha256": sha256_file(app / "PrivacyInfo.xcprivacy"),
        "entitlements": entitlements,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify an existing archive and exported signed app; never builds, signs, installs, or uploads."
    )
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--exported-app", required=True, type=Path)
    parser.add_argument("--expected-team", required=True)
    parser.add_argument("--manifest", type=Path, default=Path(".build/release-candidate-manifest.json"))
    parser.add_argument("--root", type=Path, help=argparse.SUPPRESS)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    root = (arguments.root or Path(__file__).resolve().parents[1]).resolve()
    manifest_path = arguments.manifest
    if not manifest_path.is_absolute():
        manifest_path = root / manifest_path
    try:
        ensure_ignored_output(root, manifest_path)
        commit = assert_clean_repository(root)
        policy = json.loads((root / "Config/release-candidate-policy.json").read_text())
        version, build, bundle_id = validate_source_identity(root, policy)
        source_privacy_hash = validate_source_files(root, policy)
        validate_generated_project(root)
        expected_privacy = read_plist(root / "Apps/TadaWordsApp/PrivacyInfo.xcprivacy")
        archive = arguments.archive.resolve()
        archived_app, archive_properties = resolve_archive_app(
            archive, arguments.expected_team
        )
        with tempfile.TemporaryDirectory(prefix="tadawords-exported-app-") as temporary:
            exported_app = resolve_exported_app(
                arguments.exported_app.resolve(), Path(temporary)
            )
            verifier = root / "Scripts/verify-signed-app-identity.sh"
            artifacts: dict[str, Any] = {}
            for label, app in (("archive", archived_app), ("export", exported_app)):
                verify_signed_identity(
                    verifier,
                    app,
                    version,
                    build,
                    commit,
                    bundle_id,
                    arguments.expected_team,
                )
                entitlements = signed_entitlements(app)
                validate_signed_entitlements(
                    entitlements, policy, arguments.expected_team, label
                )
                validate_app_resources(app, root, policy, expected_privacy)
                artifacts[label] = artifact_manifest(app, entitlements)

            manifest = {
                "schema_version": 1,
                "candidate": {
                    "commit": commit,
                    "version": version,
                    "build": build,
                    "bundle_id": bundle_id,
                    "team_id": arguments.expected_team,
                    "source_privacy_manifest_sha256": source_privacy_hash,
                },
                "archive": {
                    "path": str(archive),
                    "metadata": archive_properties,
                    "app": artifacts["archive"],
                },
                "export": {
                    "input_path": str(arguments.exported_app.resolve()),
                    "app": artifacts["export"],
                },
                "gates": {
                    "clean_source": "passed",
                    "generated_project": "passed",
                    "archive": "passed",
                    "exported_signed_app_identity": "passed",
                    "entitlements_privacy_icons_resources": "passed",
                    "simulator": "separate_not_run",
                    "physical_install": "separate_not_run",
                    "physical_launch_smoke": "separate_not_run",
                    "automated_device_tests": "separate_not_run",
                    "human_acceptance": "separate_human_gate_not_run",
                    "testflight_upload": "prohibited_not_run",
                },
            }
            manifest_path.parent.mkdir(parents=True, exist_ok=True)
            temporary_manifest = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
            temporary_manifest.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
            temporary_manifest.replace(manifest_path)
    except (KeyError, OSError, json.JSONDecodeError, PreflightError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(f"READY: release candidate verified; manifest={manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
