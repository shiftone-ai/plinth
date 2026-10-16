# 開発資料

目的・仕様，実装規約，外部資料を分けて管理する．作業内容に応じて必要な資料へ進む．

| 確認すること | 入口 |
| --- | --- |
| iPhone・iPadの署名・配布，MacのDeveloper ID配布 | [実機への配布](distribution.md) |
| 閲覧先の入力・ワイルドカード・拒否時の動作 | [ドメインの入力](design-docs/navigation-input.md) |
| アプリの機能・状態遷移・受け入れ条件 | [設計書v0.2](design-docs/macos-kiosk-design-v0.2.md) |
| 所有関係・通信経路・モジュール境界 | [設計の入口](../ARCHITECTURE.md) |
| 実装・Concurrency・テストの規約 | [実装規約](rules/index.md) |
| 管理画面の表示言語・翻訳の判断 | [翻訳のADR](adr/0001-localization.md) |
| 生体認証で管理者解除を有効にする条件 | [生体認証のADR](adr/0002-biometric-administrator-unlock.md) |
| 文書と指示の整理方針・参考記事 | [文書の整理方針](references/agent-docs.md) |
| 外部画面の縦置き・回転APIと既存アプリの前例 | [回転の調査](references/external-display-rotation-precedents.md) |
| 外部出力の縦横比・モード切替・取得画像の限界 | [縦横比の調査](references/mobile-output-aspect-ratio.md) |
| 導入済みSwift Skillの取得元・commit | [Skillの取得元](../.agents/skills/SOURCES.md) |
| Issue・triageラベル・用語とADRの参照先 | [Skillの設定](agents/) |

## 文書を更新する判断

1. 機能や責務境界を変えるときは，設計書の該当節を更新する．
2. 実装・検証の規約を変えるときは，`rules/` の該当文書を更新する．一般的な手順はSkillに任せ，プロジェクト固有の条件を残す．
3. 資料を移動・追加するときは，この一覧と関連する参照元を同じ変更で更新する．
4. Skillを更新するときは，取得commitと本文・reference・ライセンスをそろえる．
5. このリポジトリは公開されている．検証の記録では，端末をOSのバージョンと方式（Touch ID・Face IDなど）で表す．開発機の機種名・ホスト名，`.build/` 配下の記録の場所，配布のbuild番号や状態は，文書・Issue・PRに書かない．

設計書は実装前の判断と確認範囲を記録した文書であり，ビルド済み・実機検証済みであることを示すものではない．元の設計本文と参照資料は保持している．

現在の実装と検証範囲は [開発と検証](development.md)，実機での操作と記録項目は [Mac実機の受け入れ試験](native-acceptance.md) を参照する．

iPad対応については [対応方針](design-docs/ipad-support.md) を参照する．本体・外部への展示と管理画面の切替を扱う．外部表示・入力・端末制限の仕様と未確認事項は [Apple資料の調査](references/ipad-external-display.md) に記録し，未実装の機能を対応済みとは扱わない．

## 複数ターンにまたがる作業

現在の状態と残作業は `exec-plans/active/` の計画に記録する．目的，現在の事実，制約，残作業，次に着手する内容，阻害要因，合格条件を含め，150行以内に収める．

終わった手順や経過を追記せず，残作業を更新する．完了時は計画を削除し，結果をPR説明へ記録する．

外部表示専用Sceneと本体操作は [外部表示](design-docs/mobile-external-output.md)，Macの画面選択・出力方式は [Macの出力](design-docs/mac-output.md) を参照する．
