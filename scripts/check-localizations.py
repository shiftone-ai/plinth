#!/usr/bin/env python3
"""Check the declared languages and the keys used by Plinth's localization wrapper."""

import argparse
import json
import plistlib
import re
from pathlib import Path


def referenced_keys(root: Path) -> set[str]:
    keys: set[str] = set()
    for source in (root / "Sources").rglob("*.swift"):
        text = source.read_text()
        keys.update(re.findall(r'L10n\.string\(\s*"([^"\n]+)"', text))

    # These two pure projections return keys; the View resolves them with L10n.
    presenter = root / "Sources/KioskPresentation/Presenters.swift"
    if presenter.exists():
        text = presenter.read_text()
        start = text.find("private static func validationMessage(")
        end = text.find("private static func settingsValidation(", start)
        if start != -1 and end != -1:
            keys.update(re.findall(r'"([^"\n]+)"', text[start:end]))
        keys.update(re.findall(r'textKey:\s*"([^"\n]+)"', text))
        for name in ("biometricLabel", "biometricUnavailable"):
            start = text.find(f"private static func {name}(")
            end = text.find("private static func ", start + 1)
            if start != -1:
                keys.update(re.findall(r'"([^"\n]+)"', text[start : end if end != -1 else None]))

    guidance = root / "Sources/KioskMobileApp/MobilePointerSetupGuidance.swift"
    if guidance.exists():
        keys.update(re.findall(r'return\s+"([^"\n]+)"', guidance.read_text()))
    comparison = root / "Sources/KioskPresentation/CatalogComparison.swift"
    if comparison.exists():
        keys.update(
            value
            for value in re.findall(r'"([^"\n]+)"', comparison.read_text())
            if value not in {", ", "180°"} and "\\(" not in value
        )
    remote_page = root / "Sources/KioskRuntime/RemoteAdministration/WebAdministrationPage.swift"
    if remote_page.exists():
        keys.update(re.findall(r'label\("([^"\n]+)"\)', remote_page.read_text()))
    return keys


def shortcut_keys(root: Path) -> tuple[set[str], list[str]]:
    keys: set[str] = set()
    errors: list[str] = []
    for source in (root / "Sources").rglob("*.swift"):
        text = source.read_text()
        is_app_intent = bool(re.search(r":\s*AppIntent\b", text))
        for key, table in re.findall(
            r'LocalizedStringResource\(\s*"([^"\n]+)"\s*,\s*table:\s*"([^"\n]+)"\s*\)',
            text,
        ):
            if table == "AppIntents":
                keys.add(key)
            elif is_app_intent:
                errors.append(
                    f"{source.relative_to(root)}: {key}: use AppIntents localization table"
                )
    return keys, errors


def check(root: Path) -> list[str]:
    errors: list[str] = []
    catalog = json.loads((root / "Sources/KioskLocalization/Localizable.xcstrings").read_text())
    if catalog.get("sourceLanguage") != "en":
        errors.append("String Catalog sourceLanguage must be en")

    declared: set[str] | None = None
    for path in (root / "Resources/Info.plist", root / "Resources/Mobile-Info.plist"):
        with path.open("rb") as file:
            info = plistlib.load(file)
        languages = set(info.get("CFBundleLocalizations", []))
        if info.get("CFBundleDevelopmentRegion") != "en":
            errors.append(f"{path.name}: CFBundleDevelopmentRegion must be en")
        if not {"en", "ja"} <= languages:
            errors.append(f"{path.name}: en and ja must be declared")
        if declared is not None and languages != declared:
            errors.append(f"{path.name}: declared languages differ between apps")
        declared = languages

    package = (root / "Package.swift").read_text()
    if not re.search(r'defaultLocalization:\s*"en"', package):
        errors.append("Package.swift: defaultLocalization must be en")

    languages = declared or set()
    with (root / "Resources/Mobile-Info.plist").open("rb") as file:
        mobile_info = plistlib.load(file)
    if "NSFaceIDUsageDescription" in mobile_info:
        for language in sorted(languages):
            path = root / "Resources" / f"{language}.lproj" / "InfoPlist.strings"
            if not path.exists() or not re.search(
                r'"NSFaceIDUsageDescription"\s*=\s*"[^"\n]+"\s*;',
                path.read_text(),
            ):
                errors.append(f"InfoPlist.strings: missing {language} Face ID usage description")
    strings = catalog.get("strings", {})
    for key, entry in strings.items():
        for language in sorted(languages):
            unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value", "").strip():
                errors.append(f"{key}: missing {language} translation")
    for key in sorted(referenced_keys(root) - strings.keys()):
        errors.append(f"Unknown localization key: {key}")

    shortcut_catalog_path = root / "Resources/AppIntents.xcstrings"
    used_shortcut_keys, shortcut_errors = shortcut_keys(root)
    errors.extend(shortcut_errors)
    if shortcut_catalog_path.exists():
        shortcut_catalog = json.loads(shortcut_catalog_path.read_text())
        if shortcut_catalog.get("sourceLanguage") != "en":
            errors.append("AppIntents catalog sourceLanguage must be en")
        shortcut_strings = shortcut_catalog.get("strings", {})
        for key, entry in shortcut_strings.items():
            for language in sorted(languages):
                unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
                if unit.get("state") != "translated" or not unit.get("value", "").strip():
                    errors.append(f"AppIntents: {key}: missing {language} translation")
        for key in sorted(used_shortcut_keys - shortcut_strings.keys()):
            errors.append(f"Unknown AppIntents localization key: {key}")
    elif used_shortcut_keys:
        errors.append("Missing AppIntents localization catalog")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    errors = check(args.root)
    if errors:
        for error in errors:
            print(error)
        return 1
    print("Localization catalog and source keys are complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
