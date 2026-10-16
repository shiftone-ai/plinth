#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release -Xswiftc -warnings-as-errors
plinth_products=$(swift build -c release --show-bin-path)
plinth_bundle="$PWD/.build/Plinth.app"
mkdir -p "$plinth_bundle/Contents/MacOS" "$plinth_bundle/Contents/Resources"
cp "$plinth_products/Plinth" "$plinth_bundle/Contents/MacOS/Plinth"
swift package dump-package | python3 scripts/copy-app-resources.py "$plinth_products" "$plinth_bundle/Contents/Resources"
cp Resources/Info.plist "$plinth_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier ai.shiftone.plinth' "$plinth_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.0' "$plinth_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$plinth_bundle/Contents/Info.plist"
codesign --force --sign - --identifier ai.shiftone.plinth "$plinth_bundle"
print -r -- "$plinth_bundle"
