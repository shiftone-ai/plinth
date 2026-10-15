# Plinthの整形・検査・テスト．devenvのシェル（direnvか `devenv shell`）で実行する．

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

swift_paths := "Sources Tests scripts Package.swift"
swiftlint_baseline := ".swiftlint-baseline.json"

default:
    @just --list

# Swift・Python・shell・Nixを整形する
fmt:
    xcrun swift-format format --in-place --recursive --parallel {{ swift_paths }}
    ruff check --fix --quiet scripts
    ruff format scripts
    shfmt -w -s scripts
    nixfmt devenv.nix

# 整形の差分と静的検査の違反を報告する．SwiftLintはbaselineにない違反だけを失敗にする
lint:
    xcrun swift-format lint --strict --recursive --parallel {{ swift_paths }}
    swiftlint lint --quiet --baseline {{ swiftlint_baseline }}
    ruff check scripts
    ruff format --check scripts
    shfmt -d -s scripts
    nixfmt --check devenv.nix

# SwiftLintの既存違反をbaselineへ記録し直す．違反を直したときと，意図して残すときに使う
lint-baseline:
    swiftlint lint --quiet --write-baseline {{ swiftlint_baseline }} > /dev/null || test $? -eq 2

# commit済みの履歴全体から秘密情報を探す．commit前hookはstageした変更だけを見る
secrets:
    gitleaks git --redact --no-banner

# 警告をエラーとしてビルドし，Native結合試験を除くテストと，scriptsのテストを実行する
test:
    swift build -Xswiftc -warnings-as-errors
    swift test -Xswiftc -warnings-as-errors
    python3 -m unittest discover -s scripts -p 'test_*.py'

# 配る前の成果物（.xcarchive・.ipa・.zip・.app）に，秘密情報・手元のパス・配らないファイルが無いか，
# iOS版にPrivacy Manifestがあるか，書き出した版が配布用に署名されているかを調べる
check-artifact path:
    python3 scripts/check-artifact.py {{ quote(path) }}

# macOSの `swift build` はiOS専用のコードを含まない．生成済みのXcode projectがあれば作り直さずに使う．
# iOSアプリを署名せずにDebugとReleaseでビルドする
build-ios:
    test -d Plinth.xcodeproj || python3 scripts/create-xcode-project.py
    for configuration in Debug Release; do \
        xcodebuild -quiet -project Plinth.xcodeproj -scheme PlinthMobile \
            -destination 'generic/platform=iOS' -configuration "$configuration" \
            -derivedDataPath .build/ios-check CODE_SIGNING_ALLOWED=NO \
            SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build; \
    done

# 実WebKit・Keychain・保存・時計を結合するNative試験も含めて実行する
test-native:
    PLINTH_NATIVE_TESTS=1 swift test -Xswiftc -warnings-as-errors

# テストを実行し，ファイル別の行カバレッジを表示する（テストコードと依存を除く）
coverage:
    #!/usr/bin/env bash
    set -euo pipefail
    swift test --enable-code-coverage -Xswiftc -warnings-as-errors
    bin="$(swift build --show-bin-path)"
    # test bundleはtargetごとに分かれるため，すべてを集計の対象に渡す．
    objects=()
    for bundle in "$bin"/*.xctest/Contents/MacOS/*; do objects+=(-object "$bundle"); done
    xcrun llvm-cov report "${objects[@]}" -instr-profile "$bin/codecov/default.profdata" \
        -ignore-filename-regex '(\.build|Tests)/'

# 全ファイルの整形・静的検査，履歴の秘密情報の検出，テストをまとめて実行する
check: lint secrets test
