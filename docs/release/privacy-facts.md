# 公開候補のデータ取扱い

Issue #28 の公開文書と App Privacy を照合するための根拠．現在の `main` を基にしたソースと，iOSの配布用IPA・Macの配布用パッケージ内アプリを調べた．App Store ConnectのApp Privacy回答は残る．

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

App Store Connect の App Privacy には「アプリから収集するデータなし」の回答案を保存したが，公開は未実行．4言語のプライバシーポリシーURLは保存済み．[Appleの説明](https://developer.apple.com/app-store/app-privacy-details/)では，WebViewの通信で収集されるデータは原則申告対象で，利用者がオープンWebを閲覧できる場合は例外としている．Plinthの管理者は任意の開始URLを設定でき，拒否リスト方式ならサイト間の移動もできる．許可リスト方式では展示中の移動を制限する．任意の展示先を一括して申告する方法は取らず，アプリ自身と組み込みコードの収集を調べる．

申告案は「アプリが収集するデータなし」．ソースで確認した端末内保存とOSLogはAppleの定義する収集には当たらず，アプリに組み込んだ分析・広告・外部送信のコードもない．管理者が任意のサイトを選べるため，WebView通信にはオープンWebの例外が当たると推測する．ただしAppleは，管理者だけがURLを変更できるキオスクや，許可リスト方式で表示先を制限する場合の扱いを明示していない．[Appleの別の説明](https://developer.apple.com/app-store/user-privacy-and-data-use/)は，アプリの機能として使うWebViewを原則ネイティブ機能と同様に扱うとしている．この解釈が確定するまで申告案は公開しない．

候補に #2 のWeb管理が入る場合は，ローカルネットワークへの通信とセッションをこの表に追加する．
