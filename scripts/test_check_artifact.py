"""Run check-artifact.py on small bundles and check its exit status and report."""

import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check-artifact.py"
# Split so that secret scanners do not flag this file itself.
FAKE_TOKEN = "ghp_" + "9fK2LmQ8xZ7vR4tY1uW6sN3bC5dE0aH2jP8q"
MANIFEST = plistlib.dumps({"NSPrivacyTracking": False, "NSPrivacyAccessedAPITypes": []})


def make_app(path: Path, files: dict[str, bytes] | None = None) -> Path:
    """Create an iOS-style app bundle with an executable, Info.plist and privacy manifest."""
    path.mkdir(parents=True)
    (path / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "App"}))
    (path / "App").write_bytes(b"\x00binary\x00KioskApp/App.swift\x00")
    (path / "PrivacyInfo.xcprivacy").write_bytes(MANIFEST)
    for name, content in (files or {}).items():
        (path / name).parent.mkdir(parents=True, exist_ok=True)
        (path / name).write_bytes(content)
    return path


@unittest.skipUnless(shutil.which("gitleaks"), "gitleaks is not available")
class CheckArtifactTests(unittest.TestCase):
    def setUp(self) -> None:
        self.work = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.work)

    def archive(self, files: dict[str, bytes] | None = None) -> Path:
        archive = self.work / "App.xcarchive"
        make_app(archive / "Products/Applications/App.app", files)
        return archive

    def run_check(self, path: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path)], capture_output=True, text=True, check=False
        )

    def test_clean_archive_passes(self) -> None:
        result = self.run_check(self.archive())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_secret_in_bundle_fails_without_printing_it(self) -> None:
        result = self.run_check(self.archive({"config.txt": f"token={FAKE_TOKEN}\n".encode()}))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("github-pat", result.stdout)
        self.assertIn("config.txt", result.stdout)
        self.assertNotIn(FAKE_TOKEN, result.stdout + result.stderr)

    def test_utf16_secret_fails(self) -> None:
        result = self.run_check(self.archive({"Data.bin": FAKE_TOKEN.encode("utf-16-le")}))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("github-pat", result.stdout)

    def test_secret_in_a_file_gitleaks_skips_by_name_fails(self) -> None:
        result = self.run_check(self.archive({"Resources/data.pdf": FAKE_TOKEN.encode()}))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("App.app/Resources/data.pdf", result.stdout)

    def test_build_machine_path_fails_without_printing_it(self) -> None:
        for path in (
            b"/Users/builder/src/App.swift",
            b"/Users/Shared/build/App.swift",
            b"/Volumes/Shared/src/App.swift",
            b"/private/var/folders/x1/T/build.log",
        ):
            with self.subTest(path=path):
                shutil.rmtree(self.work / "App.xcarchive", ignore_errors=True)
                result = self.run_check(self.archive({"App": b"\x00" + path + b"\x00"}))
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("App.app/App", result.stdout)
                self.assertNotIn(path.decode(), result.stdout)

    def test_url_paths_are_not_build_machine_paths(self) -> None:
        result = self.run_check(self.archive({"App": b"https://example.com/home/user/tmp/x\x00"}))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_broken_privacy_manifest_is_reported(self) -> None:
        result = self.run_check(self.archive({"PrivacyInfo.xcprivacy": b"<plist><dict>"}))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("PrivacyInfo.xcprivacy", result.stdout)
        self.assertNotIn("Traceback", result.stderr)

    def test_ios_app_without_privacy_manifest_fails(self) -> None:
        stray = {"Contents/Info.plist": plistlib.dumps({})}
        for files in (None, stray):
            with self.subTest(files=files):
                shutil.rmtree(self.work / "App.xcarchive", ignore_errors=True)
                archive = self.archive(files)
                (archive / "Products/Applications/App.app/PrivacyInfo.xcprivacy").unlink()
                result = self.run_check(archive)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("PrivacyInfo.xcprivacy", result.stdout)

    def test_mac_app_without_privacy_manifest_passes(self) -> None:
        app = self.work / "App.xcarchive/Products/Applications/App.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "App"}))
        (app / "Contents/MacOS/App").write_bytes(b"\x00binary\x00")
        result = self.run_check(self.work / "App.xcarchive")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def signed_mac_bundle(
        self, path: Path, entitlements: dict[str, bool | list[str]] | None
    ) -> Path:
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/Info.plist").write_bytes(
            plistlib.dumps({"CFBundleExecutable": "App", "CFBundleIdentifier": f"test.{path.stem}"})
        )
        shutil.copy("/usr/bin/true", path / "Contents/MacOS/App")
        command = ["codesign", "--force", "--sign", "-"]
        if entitlements is not None:
            (self.work / "app.entitlements").write_bytes(plistlib.dumps(entitlements))
            command += ["--entitlements", str(self.work / "app.entitlements")]
        subprocess.run(command + [str(path)], check=True, capture_output=True)
        return path

    def signed_mac_app(self, entitlements: dict[str, bool | list[str]] | None) -> Path:
        return self.signed_mac_bundle(self.work / "Exported/App.app", entitlements)

    def test_exported_app_must_not_allow_debugging(self) -> None:
        for key in ("get-task-allow", "com.apple.security.get-task-allow"):
            with self.subTest(key=key):
                shutil.rmtree(self.work / "Exported", ignore_errors=True)
                result = self.run_check(self.signed_mac_app({key: True}))
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("デバッガ", result.stdout)

    def test_ad_hoc_signature_is_not_for_distribution(self) -> None:
        result = self.run_check(self.signed_mac_app(None))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ad hoc", result.stdout)

    def test_mac_biometric_keychain_requires_embedded_profile(self) -> None:
        result = self.run_check(
            self.signed_mac_app({"keychain-access-groups": ["TEAMID.test.App"]})
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("生体認証用Keychain", result.stdout)

    def test_app_changed_after_signing_fails(self) -> None:
        app = self.signed_mac_app(None)
        (app / "Contents/Resources").mkdir()
        (app / "Contents/Resources/added.txt").write_text("added after signing\n")
        result = self.run_check(app)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("署名が検証できない", result.stdout)

    def test_nested_code_must_not_allow_debugging(self) -> None:
        app = self.work / "Exported/App.app"
        self.signed_mac_bundle(app / "Contents/PlugIns/Helper.appex", {"get-task-allow": True})
        self.signed_mac_bundle(app, None)
        result = self.run_check(app)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Helper.appex", result.stdout)

    def zip_of(self, source: Path) -> Path:
        archive = self.work / "App.zip"
        subprocess.run(
            ["zip", "-qry", str(archive), "."], cwd=source, check=True, capture_output=True
        )
        return archive

    def test_zip_whose_app_is_a_symlink_fails(self) -> None:
        app = self.signed_mac_app(None)
        (self.work / "zip").mkdir()
        (self.work / "zip/App.app").symlink_to(app)
        result = self.run_check(self.zip_of(self.work / "zip"))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_files_beside_the_app_in_a_zip_are_checked(self) -> None:
        app = self.signed_mac_app(None)
        (app.parent / "config").mkdir()
        (app.parent / "config/private.key").write_bytes(b"x")
        (app.parent / "notes.txt").write_text(f"token={FAKE_TOKEN}\n")
        result = self.run_check(self.zip_of(app.parent))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("config/private.key", result.stdout)
        self.assertIn("notes.txt", result.stdout)

    def test_build_machine_path_beside_the_app_in_a_zip_fails(self) -> None:
        app = self.signed_mac_app(None)
        (app.parent / "notes.txt").write_bytes(b"built in /Users/builder/src\n")
        result = self.run_check(self.zip_of(app.parent))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("notes.txt", result.stdout)

    def test_symbols_folder_is_exempt_only_in_an_ipa(self) -> None:
        app = self.signed_mac_app(None)
        (app.parent / "Symbols").mkdir()
        (app.parent / "Symbols/build.txt").write_bytes(b"built in /Users/builder/src\n")
        result = self.run_check(self.zip_of(app.parent))
        self.assertIn("手元のパス: App.zip/Symbols/build.txt", result.stdout)

    def test_profile_beside_the_app_in_a_zip_fails(self) -> None:
        app = self.signed_mac_app(None)
        (app.parent / "embedded.mobileprovision").write_bytes(b"x")
        result = self.run_check(self.zip_of(app.parent))
        self.assertIn("配らないファイル: App.zip/embedded.mobileprovision", result.stdout)

    def test_input_that_is_a_symlink_fails(self) -> None:
        app = self.signed_mac_app(None)
        (self.work / "Link.app").symlink_to(app)
        result = self.run_check(self.work / "Link.app")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_unsigned_exported_app_fails(self) -> None:
        app = self.signed_mac_app(None)
        subprocess.run(["codesign", "--remove-signature", str(app)], check=True)
        result = self.run_check(app)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_files_that_should_not_ship_fail(self) -> None:
        for name in (".DS_Store", "Sources/App.swift", "Config/Release.xcconfig", "signing.p12"):
            with self.subTest(name=name):
                shutil.rmtree(self.work / "App.xcarchive", ignore_errors=True)
                result = self.run_check(self.archive({name: b"x"}))
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(f"App.app/{name}", result.stdout)


if __name__ == "__main__":
    unittest.main()
