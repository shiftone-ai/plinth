# Plinth — エージェント向けの入口

Mac版と，iPadの本体・外部ディスプレイでWebコンテンツを展示するキオスクランタイムを実装する．汎用ブラウザや配信CMSへの拡張は対象外．

## 変更に応じて読む資料

該当する行の資料と，Skillが案内する必要なreferenceだけを読む．

| 変更対象 | 参照先 |
| --- | --- |
| 機能・状態遷移・所有関係・モジュール境界 | [設計の入口](ARCHITECTURE.md)，[構造と責務](docs/rules/architecture.md) |
| SwiftUIの表示・入力・Presenter | [構造と責務](docs/rules/architecture.md)，[SwiftUI Pro](.agents/skills/swiftui-pro/SKILL.md) |
| UIの文言・翻訳 | [翻訳の規約](docs/rules/localization.md)，[SwiftUI ProのLocalization](.agents/skills/swiftui-pro/references/localization.md) |
| 非同期処理・Task・取消・WebKitのreply・保存 | [Concurrency](docs/rules/concurrency.md)，[Swift Concurrency Pro](.agents/skills/swift-concurrency-pro/SKILL.md) |
| テスト・検証環境 | [Testing](docs/rules/testing.md)，[Swift Testing Pro](.agents/skills/swift-testing-pro/SKILL.md) |
| 整形・静的検査・git hook・CI | [開発と検証](docs/development.md#実行する検査) |
| SDK・deployment target・Skillの導入や更新 | [Skillの適用条件](docs/rules/skills.md)，[取得元とcommit](.agents/skills/SOURCES.md) |
| iPad対応・OS別の入力と端末制限 | [iPad対応の方針](docs/design-docs/ipad-support.md) |

文書の配置・更新と長期作業の記録は [資料一覧](docs/index.md) を参照する．

## 実装の境界

Root所有ツリー，Passive View，純粋なPresenter，親方向のCoR，Mediatorによる裁定，AdapterによるEffect実行を維持する．設計の詳細は [設計書v0.2](docs/design-docs/macos-kiosk-design-v0.2.md) を参照する．

Skillの一般例より本プロジェクトの責務境界を優先し，コンパイラ・SDKとの不整合は設計として解決する．UIを作る・直すときは `stop-describing-ui` を適用する．

## 完了条件

依頼された範囲の実装・検証・検証で見つかった問題の修正まで進める．変更した責務境界，実行したビルド／テストと環境，未実行の項目を分けて報告する．設計レビューだけで動作確認済みとしない．

## Issueと用語の参照先

- Issueを扱うときは [Issue tracker](docs/agents/issue-tracker.md) を読む．
- triageラベルを扱うときは [Triage labels](docs/agents/triage-labels.md) を読む．
- 用語や設計判断を確認するときは [Domain docs](docs/agents/domain.md) を読む．
