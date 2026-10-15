# Skillの適用条件

Swift Skillを適用・更新する場合，SDKやtargetの設定を変更する場合に読む．設計書の17.1節を参照する．

[設計書v0.2](../design-docs/macos-kiosk-design-v0.2.md)

変更対象に応じて，プロジェクトに導入済みの次のSkill本文と関連referenceを読む．

- SwiftUIの変更: [SwiftUI Pro](../../.agents/skills/swiftui-pro/SKILL.md)
- 非同期処理の変更: [Swift Concurrency Pro](../../.agents/skills/swift-concurrency-pro/SKILL.md)
- テストの変更: [Swift Testing Pro](../../.agents/skills/swift-testing-pro/SKILL.md)

取得元とcommitは [.agents/skills/SOURCES.md](../../.agents/skills/SOURCES.md) に記録する．更新時は本文・reference・ライセンスと取得commitをそろえる．Claude Codeでは `.claude/skills/` のリンクから同じSkillを参照する．

一般例より本プロジェクトの責務境界を優先する．ただしコンパイラ／SDK契約との不整合を警告抑制で隠さない．iOSのAPIや新しいtoolchainの前提をMacへ機械的に適用せず，実際のmacOS deployment target，Xcode，SDK，Swift language mode，targetごとのisolation設定を確認する．不要な依存追加や無関係なモダナイズは行わない．
