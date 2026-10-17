# 公開ページ

GitHub Pages は `gh-pages` ブランチのルートを配信する．元ファイルはこのリポジトリの `site/` に置く．

| 用途 | 英語 | 日本語 | 韓国語 | 簡体字中国語 |
| --- | --- | --- | --- | --- |
| プライバシー | [en](https://shiftone-ai.github.io/plinth/en/privacy.html) | [ja](https://shiftone-ai.github.io/plinth/ja/privacy.html) | [ko](https://shiftone-ai.github.io/plinth/ko/privacy.html) | [zh-Hans](https://shiftone-ai.github.io/plinth/zh-Hans/privacy.html) |
| サポート | [en](https://shiftone-ai.github.io/plinth/en/support.html) | [ja](https://shiftone-ai.github.io/plinth/ja/support.html) | [ko](https://shiftone-ai.github.io/plinth/ko/support.html) | [zh-Hans](https://shiftone-ai.github.io/plinth/zh-Hans/support.html) |

[審査用の展示サンプル](https://shiftone-ai.github.io/plinth/demo/index.html)は，このリポジトリで作成したHTMLとCSSだけで構成する．外部の画像・動画・フォントは使わない．

公開URLは，未ログインのHTTPSリクエストでプライバシー・サポート・展示サンプルが200を返すことと，モバイル幅のブラウザで本文・リンクが読めることを確認した．アプリ内の導線と審査手順は，このURLを使う．

更新時は `site/` の原稿，4言語の表示，リンクと公開内容を確認してから，`site/` のtreeを `gh-pages` へ反映する．ポリシーを変える場合は [データ取扱い](privacy-facts.md) と App Store Connect の申告も照合する．サポートメールの期限は [運用手順](support-data.md) に記す．
