# 文書の整理方針

常時読む入口を短くし，作業の論点に応じて詳細資料を読む構成とする．参考記事は [npakaの記事](https://note.com/npaka/n/naadacc239bc8) と，そこで紹介された [OpenAIの公式記事](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)．

## このプロジェクトでの適用

- `AGENTS.md` は製品の範囲，責務境界，変更内容別の参照先，完了条件を持つ．
- 設計書は `docs/design-docs/`，実装規約は `docs/rules/` に置く．各規約に読む条件と設計書の参照範囲を付ける．
- Swift Skillは取得元の内容を保持し，プロジェクト固有の適用条件を規約へ置く．
- 複数ターンの計画には現在の事実と次の作業を残し，完了結果はPRまたはcommitへ記録する．

これは資料整理の方針であり，特定のモデルに限定した要件ではない．プロジェクト固有の不変条件と実機試験は維持する．

## Claude Codeからの入口

`.claude/CLAUDE.md` は `AGENTS.md` だけをimportする．詳細な設計・規約は，入口が示す条件に一致したときに読む．相対importの解決方法は [Claude Codeの公式資料](https://code.claude.com/docs/en/memory#import-additional-files) を参照する．
