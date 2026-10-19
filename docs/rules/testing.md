# Testing

テストの追加・変更，検証環境や受け入れ条件を扱うときに読む．設計書の15節，17.5節を参照する．

[設計書v0.2](../design-docs/macos-kiosk-design-v0.2.md)

- 新規のCore／Policy／Presenter／CoR／Adapter契約テストはSwift Testing．UIテストはXCTest＋XCUIAutomationの別ターゲット．
- 前提にrequire，検証にexpectを使う．URLや入力条件は期待値付きケースでパラメーター化する．
- StateだけでなくReply，Effect列，拒否理由，伝播経路も検証する．

## 非同期処理とfixture

- 実時間sleepやyield回数で完了を推測しない．FakeClock，ScriptedWebPort，operation単位の完了契約を使う．
- confirmation内では対象処理の完了まで待つ．expectedCountが0でも，将来永久に発火しない証明とは扱わない．
- fixtureのRoot，時計，ディレクトリ，ストアはテストごとに分離する．serializedは他suiteとの排他を保証しない．
- NSApplication等の共有状態を使う実結合試験は専用target／planとする．OSのPresentationを変える試験は専用実機で明示的に実行する．
- 認証取消後の遅延成功，旧WebViewの完了，cancel後の結果，復帰中のdown/up，再描画によるEffectの再発行を回帰試験に含める．

## iPadの画面と入力

Keychainを使うSimulatorのUI試験は，署名した試験用アプリを別のBundle IDで実行し，資格情報serviceと保存先を既存アプリから分離する．起動時に `keychain(-34018)` が出たら署名を確認する．

[対応方針](../design-docs/ipad-support.md) と [Apple資料の調査](../references/ipad-external-display.md) に従い，本体展示・外部展示と管理への切替を検証する．外部画面の比率に合う独立した表示，通常のWeb操作，カーソルが本体へ移らないこと，ロック状態の変化，接続前後の管理情報の誤表示は実機で確認する．SDKの静的確認やMacのCoreテストを，iPadの入力制限の動作証明とは扱わない．

Dock／メニューバーやOSジェスチャの抑制は実機試験を省略しない．
