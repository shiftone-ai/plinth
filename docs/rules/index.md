# 実装規約

変更内容に一致する規約を読む．詳細な設計と受け入れ条件は [設計書v0.2](../design-docs/macos-kiosk-design-v0.2.md) を参照する．

| 変更対象 | 規約 |
| --- | --- |
| Nodeの所有，CoR，Mediator，Passive View，Presenter，Binding | [構造と責務](architecture.md) |
| UIの文言，String Catalog，言語ごとの検証 | [翻訳](localization.md) |
| isolation，Task，取消，世代照合，WebKitのreply，保存 | [Concurrency](concurrency.md) |
| Core・Policy・Presenter・CoR・Adapter契約テスト，UI・実機試験 | [Testing](testing.md) |
| Swift Skillの適用，toolchain，取得元の更新 | [Skillの適用条件](skills.md) |

現在の検証範囲と未実行の項目は [開発と検証](../development.md) を参照する．
