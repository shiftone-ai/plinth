#!/bin/zsh
# Developer IDで署名し，公証チケットをstapleしたMac版をzipにする．
# XcodeのApple Accountsで配布チームにサインインし，PLINTH_TEAM_IDにteam IDを渡す．
set -eu
cd "${0:A:h:h}"
if [[ $# -ne 2 ]]; then
	print -u2 -r -- "Usage: PLINTH_TEAM_ID=<team ID> zsh scripts/build-notarized-app.sh <version> <build>"
	exit 64
fi
plinth_team=${PLINTH_TEAM_ID:?Set PLINTH_TEAM_ID to the distribution team ID.}
plinth_version=$1
plinth_build=$2
plinth_work="$PWD/.build/developer-id/$plinth_version-$plinth_build"
plinth_archive="$plinth_work/Plinth.xcarchive"
plinth_app="$plinth_work/notarized/Plinth.app"
plinth_zip="$plinth_work/Plinth-$plinth_version-$plinth_build.zip"
if [[ -e $plinth_work ]]; then
	print -u2 -r -- "$plinth_work already exists. Use a new build number."
	exit 1
fi

# 作業ツリーの生成projectを書き換えないよう，複製したsourceから組み立て，複製元を記録する．
mkdir -p "$plinth_work/source"
cp -R Package.swift Resources Sources Tests scripts "$plinth_work/source/"
rm -rf "$plinth_work/source/scripts/__pycache__"
(cd "$plinth_work/source" && find . -type f -exec shasum -a 256 {} + | sort -k 2) >"$plinth_work/source.sha256"
python3 "$plinth_work/source/scripts/create-xcode-project.py" --developer-id >/dev/null
xcodebuild -quiet -project "$plinth_work/source/Plinth.xcodeproj" -scheme Plinth \
	-configuration Release -destination 'generic/platform=macOS' \
	-derivedDataPath "$plinth_work/derived" -archivePath "$plinth_archive" \
	-allowProvisioningUpdates DEVELOPMENT_TEAM="$plinth_team" \
	MARKETING_VERSION="$plinth_version" CURRENT_PROJECT_VERSION="$plinth_build" archive
# Appleへ送る前に，秘密情報・手元のパス・配らないファイルが入っていないか調べる．
python3 "$plinth_work/source/scripts/check-artifact.py" "$plinth_archive"

# uploadはクラウド管理のDeveloper ID証明書で署名し，公証の受付までを行う．完了は待たない．
plinth_options="$plinth_work/ExportOptions.plist"
plutil -create xml1 "$plinth_options"
plutil -insert method -string developer-id "$plinth_options"
plutil -insert destination -string upload "$plinth_options"
plutil -insert signingStyle -string automatic "$plinth_options"
plutil -insert teamID -string "$plinth_team" "$plinth_options"
xcodebuild -quiet -exportArchive -archivePath "$plinth_archive" \
	-exportOptionsPlist "$plinth_options" -exportPath "$plinth_work/upload" -allowProvisioningUpdates

# 公証の処理中は書き出しが失敗するため，ほかの失敗が出るか上限に達するまで繰り返す．
plinth_log="$plinth_work/notarization.log"
for plinth_attempt in {1..90}; do
	if xcodebuild -exportNotarizedApp -archivePath "$plinth_archive" \
		-exportPath "$plinth_work/notarized" >"$plinth_log" 2>&1; then
		break
	fi
	if ! grep -q "is processing and not ready" "$plinth_log" || ((plinth_attempt == 90)); then
		cat "$plinth_log" >&2
		exit 1
	fi
	sleep 20
done

codesign --verify --deep --strict "$plinth_app"
xcrun stapler validate "$plinth_app"
spctl --assess --type execute "$plinth_app"
ditto -c -k --sequesterRsrc --keepParent "$plinth_app" "$plinth_zip"
# 配るzipの中身と配布用の署名を調べる．
python3 "$plinth_work/source/scripts/check-artifact.py" "$plinth_zip"
print -r -- "$plinth_zip"
