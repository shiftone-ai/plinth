#!/usr/bin/env python3
"""Check a built app before it leaves this Mac: .xcarchive, .ipa, .zip or .app.

Reports secrets and build-machine paths in the bundle's strings, files that should not ship, and
an iOS app without a privacy manifest. An exported artifact (anything but an .xcarchive) must
also be validly signed with an Apple-issued certificate, with no debugger attachment and no
profile limited to devices, in the app and in the code nested in it. Exit status: 0 when nothing is found, 1 when something is
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

# Printable ASCII runs, the same unit as `strings -n 6`, and the same text stored as UTF-16LE.
# Rules keyed on a token prefix (ghp_, AKIA, sk-) find literals in binaries; rules that need
# `key = value` context mostly do not.
PRINTABLE = re.compile(rb"[\x20-\x7e]{6,}")
PRINTABLE_UTF16 = re.compile(rb"(?:[\x20-\x7e]\x00){6,}")
# Absolute paths of the build machine: home folders, temporary folders and mounted volumes.
# A path must not continue a word, so URL paths such as https://example.com/home/ do not match.
LOCAL_PATH = re.compile(
    rb"(?<![\w.-])(?:/(?:Users|home|Volumes)/[^/\s]+/"
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
# iOS and macOS spell the entitlement that lets a debugger attach differently.
DEBUGGABLE = ("get-task-allow", "com.apple.security.get-task-allow")


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


def unpack(artifact: Path, work: Path) -> tuple[list[Path], list[Path]]:
    """Return the trees to check file by file, and the app bundles in them.

    An .ipa or .zip is checked whole, so files beside the app count too. An app that is a
    symlink is never followed.
    """
    suffix = artifact.suffix.lower()
    if suffix == ".xcarchive":
        apps = sorted((artifact / "Products/Applications").glob("*.app"))
        trees = apps
    elif suffix in (".ipa", ".zip"):
        unpacked = work / "unpacked" / artifact.name
        command = ["ditto", "-x", "-k", str(artifact), str(unpacked)]
        subprocess.run(command, check=True, capture_output=True)
        apps = sorted(unpacked.glob("Payload/*.app")) + sorted(unpacked.glob("*.app"))
        trees = [unpacked]
    elif suffix == ".app":
        apps = trees = [artifact]
    else:
        raise CheckError(f"対応していない形式: {artifact.name}")
    return [tree for tree in trees if not tree.is_symlink()], [
        app for app in apps if not app.is_symlink()
    ]


def text_of(path: Path) -> bytes:
    """The printable strings of a file, one per line, with UTF-16LE runs converted to ASCII."""
    data = path.read_bytes()
    runs = PRINTABLE.findall(data)
    runs += [run.decode("utf-16-le").encode() for run in PRINTABLE_UTF16.findall(data)]
    return b"\n".join(runs)


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
        verify = ["codesign", "--verify", "--deep", "--strict", str(bundle)]
        if subprocess.run(verify, capture_output=True, check=False).returncode != 0:
            findings.append(f"署名が検証できない（署名後の変更など）: {label(app, bundle)}")
        # Developer ID and App Store certificates chain to Apple; ad hoc and self-signed do not.
        issuer = ["codesign", "--verify", "-R=anchor apple generic", str(bundle)]
        if subprocess.run(issuer, capture_output=True, check=False).returncode != 0:
            findings.append(
                f"Appleの証明書による署名でない（ad hoc・自己署名など）: {label(app, bundle)}"
            )
        entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
        if any(entitlements.get(key) for key in DEBUGGABLE):
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
    if not (app / "Info.plist").is_file() and (app / "Contents/Info.plist").is_file():
        return []
    try:
        if isinstance(plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes()), dict):
            return []
    except (OSError, ValueError, ExpatError, plistlib.InvalidFileException):
        pass
    return [f"PrivacyInfo.xcprivacy が無いか読めない: {app.name}"]


def unshippable(tree: Path) -> list[str]:
    allowed = {profile for bundle in code_bundles(tree) for profile in embedded_profiles(bundle)}
    findings = []
    for path in tree.rglob("*"):
        name, suffix = path.name.lower(), path.suffix.lower()
        in_framework = any(part.endswith(".framework") for part in path.relative_to(tree).parts)
        if path.is_symlink() and not path.resolve().is_relative_to(tree.resolve()):
            findings.append(f"外を指すsymlink: {label(tree, path)}")
        elif path in allowed or (suffix == ".h" and in_framework):
            continue
        elif name in UNSHIPPABLE_NAMES or name.startswith(".env") or suffix in UNSHIPPABLE_SUFFIXES:
            findings.append(f"配らないファイル: {label(tree, path)}")
    return findings


def local_paths(root: Path, files: list[Path]) -> list[str]:
    """Name the files that embed build-machine paths. The paths themselves are not printed."""
    return [
        f"手元のパス: {label(root, path)}" for path in files if LOCAL_PATH.search(text_of(path))
    ]


def beside_apps(tree: Path, apps: list[Path]) -> list[Path]:
    """Files of an unpacked archive outside its apps. An .ipa's Symbols/ only goes to Apple."""
    return [
        path
        for path in bundle_files(tree)
        if not any(path.is_relative_to(app) for app in apps)
        and path.relative_to(tree).parts[0] != "Symbols"
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
        target.write_bytes(text_of(path))
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
    given = Path(sys.argv[1])
    if given.is_symlink():
        print(f"check-artifact: 調べられない（{given.name}）: symlinkはたどらない", file=sys.stderr)
        return 2
    artifact = given.resolve()
    if shutil.which("gitleaks") is None:
        print("check-artifact: gitleaks が見つからない", file=sys.stderr)
        return 2
    exported = artifact.suffix.lower() != ".xcarchive"
    if not exported:
        print("check-artifact: archive は書き出す前なので，署名は調べない", file=sys.stderr)
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        try:
            trees, apps = unpack(artifact, work)
            findings = [
                finding
                for tree in trees
                for finding in unshippable(tree)
                + local_paths(tree, beside_apps(tree, apps))
                + secrets(tree, work)
            ]
            if not apps:
                raise CheckError(f"アプリが見つからない: {artifact.name}")
            findings += [
                finding
                for app in apps
                for finding in (signing(app) if exported else [])
                + privacy_manifest(app)
                + local_paths(app, bundle_files(app))
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
