# 公開候補のデータ取扱い

Issue #28 の公開文書と App Privacy を照合するための根拠．Web管理と生体認証を含む候補のソースを調べ，配布用IPAとMacの配布用パッケージを検査した．App Store ConnectのApp Privacy回答は利用者の承認を受けて公開した．

| 対象 | コードで確認できる扱い | 根拠 |
| --- | --- | --- |
| 展示設定 | 開始URL，閲覧先，操作，無操作復帰，画面設定を `profile.json` に端末内保存 | `ProfileRepository`，`KioskProfile`，Mac・iOSのApplication組み立て |
| 設定集とiCloud | 管理者が同期を有効にし，個別に共有した項目の名前と設定内容をApple AccountのCloudKit非公開データベースへ送る．設定内容には開始URLなどを含み，`encryptedValues`に保存する．管理者パスワード，生体認証の情報，閲覧履歴は含めない．同期の無効化やアプリの削除だけでは共有項目は消えず，設定集から取り除いた項目の削除を同期する | `CatalogCloudPayload`，`CatalogSnapshot`，`CatalogCloudSync`，`RootMediator+CatalogLocal` |
| 管理者パスワード | 端末内Keychainにsalt付きPBKDF2検証値を保存．設定JSONと診断ログに平文を入れない | `CredentialStore`，`PasscodeVerifier`，`DiagnosticRecord` |
| 生体認証 | OSの認証APIを使用．Keychainに認証で保護された有効フラグを保存し，生体情報そのものは扱わない | `BiometricCredentialAdapter` |
| 表示言語 | 選択した言語を端末内のUserDefaultsに保存 | `LanguagePreference` |
| 診断 | OSLogに状態遷移・拒否理由・識別子・revisionなどを記録．入力文字列，パスワード，URL全体，マウス座標は記録しない | `DiagnosticLogAdapter`，`DiagnosticRecord` |
| 展示ページのサイトデータ | WebKitの非永続データストアを使用．「新しい閲覧セッション」は表示面を作るたびに新規ストア．「Cookieなどを保持」はアプリの稼働中に同じストアを再利用．Runtime停止時に破棄 | `WebKitAdapter.create`，`WebKitAdapter.stop` |
| 展示ページへの通信 | 管理者が指定したURLをWebKitで読み込む．許可・拒否するドメイン規則は主画面の移動に適用し，埋め込み先には適用しない．埋め込み先にもURL形式とHTTP許可の条件は適用する．閲覧先サイトや埋め込み先のデータ取扱いは各サイトに従う | `WebKitAdapter.load`，`ExhibitionMediator`，`NavigationPolicy` |
| Web管理の待ち受け | 初期状態は無効．管理者が端末で有効にすると，固定ポート47623で同じローカルネットワークのブラウザからHTTP接続を受ける．HTTPSによる暗号化はない | `WebAdministrationServer`，`WebAdministrationHTTPHandler`，`KioskProfile` |
| Web管理の認証とセッション | 管理者パスワードと設定の変更内容はブラウザから端末へ送る．ブラウザは一時的なトークンをページのメモリに保持し，端末のセッションは無効化時に破棄する．Shift Oneへは送らない | `WebAdministrationPage`，`WebAdministrationHTTPHandler`，`RootMediator+WebAdministration` |

ソース内に分析SDK，広告SDK，Shift Oneへ設定や診断を送る通信処理は見つからない．設定集の共有項目はAppleのCloudKitへ送る．アプリから公開のプライバシー・サポートページを開く場合，そのページのホストには通常のWebリクエストが届く．管理者が指定する展示サイトとアプリ自身の扱いは，公開文書でも分けて記載する．

App Store Connect の App Privacy には「アプリから収集するデータなし」を公開した．4言語のプライバシーポリシーURLは保存済み．[Appleの説明](https://developer.apple.com/app-store/app-privacy-details/)では，WebViewの通信で収集されるデータは原則申告対象で，利用者がオープンWebを閲覧できる場合は例外としている．Plinthの管理者は任意の開始URLを設定でき，拒否リスト方式ならサイト間の移動もできる．許可リスト方式では展示中の移動を制限する．任意の展示先を一括して申告する方法は取らず，アプリ自身と組み込みコードの収集を調べる．

先に公開したApp Privacyの回答は「アプリが収集するデータなし」．この回答は設定集を含まない版を前提とする．端末内保存とOSLogはAppleの定義する収集には当たらない．管理者が任意のサイトを選べるため，WebView通信にはオープンWebの例外が当たると推測する．ただしAppleは，管理者だけがURLを変更できるキオスクや，許可リスト方式で表示先を制限する場合の扱いを明示していない．[Appleの別の説明](https://developer.apple.com/app-store/user-privacy-and-data-use/)は，アプリの機能として使うWebViewを原則ネイティブ機能と同様に扱うとしている．利用者はAppleへの個別照会を省き，この推測を明記したまま審査で判断を受ける方針を示した．審査結果は申告の正確さを代わりに保証するものではない．

設定集を含む版について，App Privacyの回答を再点検した．[Appleの定義](https://developer.apple.com/app-store/app-privacy-details/)は，開発者または組み込んだ第三者が，リクエストの処理時間を超えてアクセスできる形で端末外へ送るデータを「収集」とする．Appleの同じ説明は，CloudKitなどのAppleのサービスが集めるデータは開発者に申告を求めないとしている．[CloudKit非公開データベースの説明](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)では，データは利用者の所有で，標準では開発者ポータルから見えない．実装は利用者の非公開データベースだけを使い，開発者が共有項目を取得する処理を持たない．この範囲なら，現在の「アプリが収集するデータなし」という回答と整合すると判断した．WebViewの表示先に関する前段の不確実性は残る．

Web管理は同じネットワーク上の第三者にパスワードと設定が読まれるおそれがある．端末内の管理画面から有効にした場合だけ使えること，隔離したネットワークで運用することを公開ポリシーに記した．これはアプリが開発者へデータを収集する経路ではない．
