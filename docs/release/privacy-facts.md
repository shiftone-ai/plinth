# 公開候補のデータ取扱い

Issue #28 の公開文書と App Privacy を照合するための根拠．現在の `main` を基にしたソースの調査結果であり，署名済み候補と App Store Connect の確認は残る．

| 対象 | コードで確認できる扱い | 根拠 |
| --- | --- | --- |
| 展示設定 | 開始URL，閲覧先，操作，無操作復帰，画面設定を `profile.json` に端末内保存 | `ProfileRepository`，`KioskProfile`，Mac・iOSのApplication組み立て |
| 管理者パスワード | 端末内Keychainにsalt付きPBKDF2検証値を保存．設定JSONと診断ログに平文を入れない | `CredentialStore`，`PasscodeVerifier`，`DiagnosticRecord` |
| 生体認証 | OSの認証APIを使用．Keychainに認証で保護された有効フラグを保存し，生体情報そのものは扱わない | `BiometricCredentialAdapter` |
| 表示言語 | 選択した言語を端末内のUserDefaultsに保存 | `LanguagePreference` |
| 診断 | OSLogに状態遷移・拒否理由・識別子・revisionなどを記録．入力文字列，パスワード，URL全体，マウス座標は記録しない | `DiagnosticLogAdapter`，`DiagnosticRecord` |
| 展示ページのサイトデータ | WebKitの非永続データストアを使用．「新しい閲覧セッション」は表示面を作るたびに新規ストア．「Cookieなどを保持」はアプリの稼働中に同じストアを再利用．Runtime停止時に破棄 | `WebKitAdapter.create`，`WebKitAdapter.stop` |
| 展示ページへの通信 | 管理者が指定したURLをWebKitで読み込む．閲覧先サイトや，そのページの埋め込み先への通信は各サイトの扱いに従う | `WebKitAdapter.load`，`NavigationPolicy` |

ソース内に分析SDK，広告SDK，Shift Oneへ設定や診断を送る通信処理は見つからない．アプリから公開のプライバシー・サポートページを開く場合，そのページのホストには通常のWebリクエストが届く．管理者が指定する展示サイトとアプリ自身の扱いは，公開文書でも分けて記載する．

App Store Connect の回答は現物を確認するまで未確定．候補に #2 のWeb管理が入る場合は，ローカルネットワークへの通信とセッションをこの表に追加する．
