# Swift Skillsの取得元

3つのSkillをcommit固定でこのプロジェクトに導入している．Skill本文とreferenceは取得元の内容を保持し，各ディレクトリにMITライセンスを同梱する．

| Skill | 取得元のパス | commit |
| --- | --- | --- |
| [SwiftUI Pro](swiftui-pro/SKILL.md) | [twostraws/swiftui-agent-skill / swiftui-pro](https://github.com/twostraws/swiftui-agent-skill/tree/f9800713b24580bc444931949aad4519128605e8/swiftui-pro) | `f9800713b24580bc444931949aad4519128605e8` |
| [Swift Concurrency Pro](swift-concurrency-pro/SKILL.md) | [twostraws/Swift-Concurrency-Agent-Skill / swift-concurrency-pro](https://github.com/twostraws/Swift-Concurrency-Agent-Skill/tree/bee3f69ba17142da148d3c5406f148ed62592b69/swift-concurrency-pro) | `bee3f69ba17142da148d3c5406f148ed62592b69` |
| [Swift Testing Pro](swift-testing-pro/SKILL.md) | [twostraws/Swift-Testing-Agent-Skill / swift-testing-pro](https://github.com/twostraws/Swift-Testing-Agent-Skill/tree/2d6bba14a3c8bf3694f218b92fffe617c41ae43e/swift-testing-pro) | `2d6bba14a3c8bf3694f218b92fffe617c41ae43e` |

Codexは `.agents/skills/` を参照する．Claude Code用の `.claude/skills/` は同じディレクトリへの相対リンクである．

導入には `skill-installer` の `install-skill-from-github.py` を使用した．Plugin配布用の `.claude-plugin/` と `skills/` は，Codexでの重複検出を避けるため配置対象から外している．本文・reference・`agents/`・`assets/` は取得元の内容を保持する．APM 0.33.0はPlugin配布用の参照ディレクトリへのリンクを拒否したため，APMによる依存管理は導入していない．
