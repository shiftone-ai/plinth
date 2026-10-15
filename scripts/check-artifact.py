#!/usr/bin/env python3
"""Check a built app before it leaves this Mac: .xcarchive, .ipa, .zip or .app.

Reports secrets and build-machine paths in the bundle's strings, files that should not ship, and
an iOS app without a privacy manifest. An exported artifact (anything but an .xcarchive) must
also be signed for distribution: no debugger attachment and no profile limited to devices, in
the app and in the code nested in it. Exit status: 0 when nothing is found, 1 when something is
found, 2 when the artifact cannot be checked.
"""

import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.parsers.expat import ExpatError

# Printable ASCII runs, the same unit as `strings -n 6`. Rules keyed on a token prefix (ghp_,
# AKIA, sk-) find literals in binaries; rules that need `key = value` context mostly do not.
PRINTABLE = re.compile(rb"[\x20-\x7e]{6,}")
# Absolute paths of the build machine: home folders, temporary folders and mounted volumes.
# A path must not continue a word, so URL paths such as https://example.com/home/ do not match.
LOCAL_PATH = re.compile(
    rb"(?<![\w.-])(?:/(?:Users|home|Volumes)/(?!Shared/)[^/\s]+/"
    rb"|/(?:private/)?(?:var/folders|tmp)/)"
)
# Sources, build settings, private keys, profiles and local state. Secrets inside any file are
# left to gitleaks. Only the profile that signing embeds may ship.
UNSHIPPABLE_NAMES = {".ds_store", ".git", ".envrc", ".netrc", ".npmrc"}
UNSHIPPABLE_SUFFIXES = {
    ".swift", ".h", ".m", ".mm", ".c", ".cpp", ".py", ".md", ".xcconfig", ".entitlements",
    ".p8", ".p12", ".pfx", ".key", ".jks", ".keystore",
    ".mobileprovision", ".provisionprofile", ".log", ".xcuserstate",
}  # fmt: skip
CODE_BUNDLE_SUFFIXES = {".app", ".appex", ".xpc", ".framework"}


class CheckError(Exception):
    """The artifact cannot be checked."""


def describe(error: Exception) -> str:
    """Say what failed without the local paths that commands and OS errors carry."""
    if isinstance(error, subprocess.CalledProcessError):
        return f"{Path(str(error.cmd[0])).name} が失敗した（status {error.returncode}）"
    if isinstance(error, OSError):
        return f"{type(error).__name__}: {error.strerror}"
    if isinstance(error, CheckError):
        return str(error)
    return type(error).__name__


def app_bundles(artifact: Path, work: Path) -> list[Path]:
    """Return the app bundles inside the artifact, unpacking archives into work."""
    suffix = artifact.suffix.lower()
    if suffix == ".xcarchive":
        return sorted((artifact / "Products/Applications").glob("*.app"))
    if suffix in (".ipa", ".zip"):
        unpacked = work / "unpacked"
        command = ["ditto", "-x", "-k", str(artifact), str(unpacked)]
        subprocess.run(command, check=True, capture_output=True)
        return sorted(unpacked.glob("Payload/*.app")) + sorted(unpacked.glob("*.app"))
    if suffix == ".app":
        return [artifact]
    raise CheckError(f"対応していない形式: {artifact.name}")


def bundle_files(app: Path) -> list[Path]:
    return sorted(path for path in app.rglob("*") if path.is_file() and not path.is_symlink())


def code_bundles(app: Path) -> list[Path]:
    """The app and the apps, extensions, XPC services and frameworks nested in it."""
    nested = (
        path
        for path in app.rglob("*")
        if path.suffix in CODE_BUNDLE_SUFFIXES and path.is_dir() and not path.is_symlink()
    )
    return [app, *sorted(nested)]


def embedded_profiles(bundle: Path) -> list[Path]:
    return [bundle / "embedded.mobileprovision", bundle / "Contents/embedded.provisionprofile"]


def label(app: Path, path: Path) -> str:
    return f"{app.name}/{path.relative_to(app)}" if path != app else app.name


def signing(app: Path) -> list[str]:
    findings = []
    for bundle in code_bundles(app):
        result = subprocess.run(
            ["codesign", "-d", "--entitlements", "-", "--xml", str(bundle)],
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            findings.append(f"署名を読めない: {label(app, bundle)}")
            continue
        if result.stdout.strip() and plistlib.loads(result.stdout).get("get-task-allow"):
            findings.append(f"デバッガの接続を許す署名（get-task-allow）: {label(app, bundle)}")
        for profile in filter(Path.is_file, embedded_profiles(bundle)):
            decoded = subprocess.run(
                ["security", "cms", "-D", "-i", str(profile)], capture_output=True, check=False
            )
            if decoded.returncode != 0:
                findings.append(f"provisioning profile を読めない: {label(app, profile)}")
            # Development and Ad Hoc profiles list devices; App Store and Developer ID ones do not.
            elif "ProvisionedDevices" in plistlib.loads(decoded.stdout):
                findings.append(f"端末を限った開発用・Ad Hocのprofile: {label(app, profile)}")
    return findings


def privacy_manifest(app: Path) -> list[str]:
    """iOS apps must declare required reason APIs; Apple does not require this of macOS apps."""
    if (app / "Contents/Info.plist").is_file():
        return []
    try:
        if isinstance(plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes()), dict):
            return []
    except (OSError, ValueError, ExpatError, plistlib.InvalidFileException):
        pass
    return [f"PrivacyInfo.xcprivacy が無いか読めない: {app.name}"]


def unshippable(app: Path) -> list[str]:
    allowed = {profile for bundle in code_bundles(app) for profile in embedded_profiles(bundle)}
    findings = []
    for path in app.rglob("*"):
        name, suffix = path.name.lower(), path.suffix.lower()
        in_framework = any(part.endswith(".framework") for part in path.relative_to(app).parts)
        if path in allowed or (suffix == ".h" and in_framework):
            continue
        if name in UNSHIPPABLE_NAMES or name.startswith(".env") or suffix in UNSHIPPABLE_SUFFIXES:
            findings.append(f"配らないファイル: {label(app, path)}")
    return findings


def local_paths(app: Path) -> list[str]:
    """Name the files that embed build-machine paths. The paths themselves are not printed."""
    return [
        f"手元のパス: {label(app, path)}"
        for path in bundle_files(app)
        if LOCAL_PATH.search(path.read_bytes())
    ]


def secrets(app: Path, work: Path) -> list[str]:
    """Scan the printable strings of every file with gitleaks. Values stay redacted."""
    # Neutral names keep gitleaks from skipping files by their name or extension.
    strings = work / "strings"
    shutil.rmtree(strings, ignore_errors=True)
    strings.mkdir()
    sources = {}
    for index, path in enumerate(bundle_files(app)):
        target = strings / f"{index}.txt"
        target.write_bytes(b"\n".join(PRINTABLE.findall(path.read_bytes())))
        sources[target.name] = label(app, path)
    report = work / "gitleaks.json"
    result = subprocess.run(
        ["gitleaks", "dir", str(strings), "--no-banner", "--redact", "--log-level", "error"]
        + ["--exit-code", "0", "--report-format", "json", "--report-path", str(report)],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise CheckError(f"gitleaks が失敗した（status {result.returncode}）")
    return [
        f"秘密情報 [{finding['RuleID']}]: {sources.get(Path(finding['File']).name, app.name)}"
        for finding in json.loads(report.read_text() or "[]")
    ]


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: check-artifact.py <.xcarchive|.ipa|.zip|.app>", file=sys.stderr)
        return 2
    artifact = Path(sys.argv[1]).resolve()
    if shutil.which("gitleaks") is None:
        print("check-artifact: gitleaks が見つからない", file=sys.stderr)
        return 2
    exported = artifact.suffix.lower() != ".xcarchive"
    if not exported:
        print("check-artifact: archive は書き出す前なので，署名は調べない", file=sys.stderr)
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        try:
            apps = app_bundles(artifact, work)
            if not apps:
                raise CheckError(f"アプリが見つからない: {artifact.name}")
            findings = [
                finding
                for app in apps
                for finding in (signing(app) if exported else [])
                + privacy_manifest(app)
                + unshippable(app)
                + local_paths(app)
                + secrets(app, work)
            ]
        except (
            CheckError,
            OSError,
            ValueError,
            ExpatError,
            plistlib.InvalidFileException,
            subprocess.SubprocessError,
        ) as error:
            print(
                f"check-artifact: 調べられない（{artifact.name}）: {describe(error)}",
                file=sys.stderr,
            )
            return 2
    for finding in findings:
        print(f"check-artifact: {finding}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
