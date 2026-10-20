"""Check the localization command's exit status and output on small app fixtures."""

import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check-localizations.py"


class CheckLocalizationsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        resources = self.root / "Resources"
        resources.mkdir()
        info = plistlib.dumps(
            {"CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "ja"]}
        )
        for name in ("Info.plist", "Mobile-Info.plist"):
            (resources / name).write_bytes(info)
        (self.root / "Package.swift").write_text('defaultLocalization: "en"')
        self.catalog = self.root / "Sources/KioskLocalization/Localizable.xcstrings"
        self.catalog.parent.mkdir(parents=True)
        self.strings = {
            "sourceLanguage": "en",
            "strings": {
                "Save settings": {
                    "localizations": {
                        language: {"stringUnit": {"state": "translated", "value": value}}
                        for language, value in (("en", "Save settings"), ("ja", "設定を保存"))
                    }
                }
            },
        }
        self.catalog.write_text(json.dumps(self.strings))
        self.source = self.root / "Sources/KioskUI/SettingsView.swift"
        self.source.parent.mkdir(parents=True)
        self.source.write_text('L10n.string("Save settings")')

    def run_check(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_complete_catalog_passes(self) -> None:
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_translation_fails_with_key_and_language(self) -> None:
        del self.strings["strings"]["Save settings"]["localizations"]["ja"]
        self.catalog.write_text(json.dumps(self.strings))
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Save settings: missing ja translation", result.stdout)

    def test_unknown_source_key_fails_with_its_name(self) -> None:
        self.source.write_text('L10n.string("Unknown action")')
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Unknown localization key: Unknown action", result.stdout)

    def test_missing_face_id_description_fails(self) -> None:
        mobile = self.root / "Resources/Mobile-Info.plist"
        mobile.write_bytes(
            plistlib.dumps(
                {
                    "CFBundleDevelopmentRegion": "en",
                    "CFBundleLocalizations": ["en", "ja"],
                    "NSFaceIDUsageDescription": "English description",
                }
            )
        )
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("InfoPlist.strings: missing ja Face ID usage description", result.stdout)

    def test_shortcuts_catalog_checks_action_name_and_languages(self) -> None:
        action = self.root / "Sources/PlinthMobile/ResetExhibitionIntent.swift"
        action.parent.mkdir(parents=True)
        action.write_text(
            'static let title = LocalizedStringResource("Reset Exhibition", table: "AppIntents")'
        )
        shortcuts = self.root / "Resources/AppIntents.xcstrings"
        shortcuts.write_text(
            json.dumps(
                {
                    "sourceLanguage": "en",
                    "strings": {
                        "Reset Exhibition": {
                            "localizations": {
                                "en": {
                                    "stringUnit": {
                                        "state": "translated",
                                        "value": "Reset Exhibition",
                                    }
                                }
                            }
                        }
                    },
                }
            )
        )
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("AppIntents: Reset Exhibition: missing ja translation", result.stdout)

    def test_app_intent_using_another_table_fails(self) -> None:
        action = self.root / "Sources/PlinthMobile/ResetExhibitionIntent.swift"
        action.parent.mkdir(parents=True)
        action.write_text(
            "struct ResetExhibitionIntent: AppIntent {\n"
            '  static let title = LocalizedStringResource("Reset Exhibition", table: "Shortcuts")\n'
            "}\n"
        )
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Reset Exhibition: use AppIntents localization table", result.stdout)

    def test_app_intent_without_table_fails(self) -> None:
        action = self.root / "Sources/PlinthMobile/ResetExhibitionIntent.swift"
        action.parent.mkdir(parents=True)
        action.write_text(
            "struct ResetExhibitionIntent: AppIntent {\n"
            '  static let title = LocalizedStringResource("Reset Exhibition")\n'
            "}\n"
        )
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Reset Exhibition: use AppIntents localization table", result.stdout)

    def test_app_intent_after_another_protocol_with_module_name_fails(self) -> None:
        action = self.root / "Sources/PlinthMobile/ResetExhibitionIntent.swift"
        action.parent.mkdir(parents=True)
        action.write_text(
            "struct ResetExhibitionIntent: Sendable, AppIntents.AppIntent {\n"
            '  static let title = LocalizedStringResource("Reset Exhibition", table: "Shortcuts")\n'
            "}\n"
        )
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Reset Exhibition: use AppIntents localization table", result.stdout)


if __name__ == "__main__":
    unittest.main()
