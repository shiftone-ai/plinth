# App Store公開準備表

Issue #28の提出可否を判断する表．iPhone／iPad版とMac専用版はApp Store Connectの同じアプリ記録の別プラットフォームであり，製品ページの説明・画像・候補ビルドは別に照合する．ここには公開できる確認結果だけを記録する．審査提出と一般公開は別の作業．Web管理と生体認証を含む現在の`main`から新しい画像とビルドを作成し，App Store Connectの下書きへ登録した．

| 項目 | 状態 | 確認元・完了条件 | 担当 |
| --- | --- | --- | --- |
| アプリ名・Bundle ID | 確認済み | App Store Connectの日本語名はPlinth Kiosk，Bundle IDは`ai.shiftone.plinth.mobile`で両プラットフォーム共通．署名済みのMacアプリとiOS IPAで同じIDを確認した．iOSの版数は製品ページと候補で1.0にそろえた | 実装担当 |
| カテゴリ・サブタイトル | 確認済み | App Store Connectで主カテゴリをUtilities，4言語のサブタイトルを[原稿](store-listing.md)どおりに保存した | 実装担当 |
| 著作権表示 | 確認済み | 利用者が正式な表記を確認した．iOS・Mac版のCopyright欄へ保存し，統合後のMac archiveと配布用パッケージ内の`NSHumanReadableCopyright`で同じ表記を確認した．公開リポジトリには個人名を記録せず，Macのarchive時に`PLINTH_COPYRIGHT`を指定する | 公開担当 |
| 説明・キーワード・サポートURL | 確認済み | App Store ConnectのiOS版とMac版に4言語の説明・キーワード・サポートURLを保存した．[原稿](store-listing.md)のWeb管理も統合後の両候補に含まれることを確認した | 実装担当 |
| アイコン | 確認済み | `Resources/Assets.xcassets`のアイコンを目視し，Mac archiveの`Assets.car`に16～1024pxのAppIconが入ることを確認した．App Store ConnectのiOS・Mac両版で，選択中のビルドにApp Iconが含まれ，画像プレビューに同じ図柄が表示されることを目視した | 実装担当 |
| iPhone・iPad・Macの画像 | 確認済み | [画像](screenshots/)にiPhone 17 Pro Max（1320×2868）・iPad Pro 13インチ（2064×2752）の4言語のSimulator実画像を各2枚，Macの実画面（2560×1600）を4言語で各2枚保存した．App Store Connectの両版の言語別枠へ計24枚を登録し，Macの各枠に該当言語の2枚が表示されることを再読込後に確認した．簡体字中国語のMac管理画面は開始URLを入力する前の状態．画面に重なったキーチェーン確認を含む撮影分は採用していない | 実装担当 |
| 公開のプライバシーURL | 確認済み | [4言語のURL](public-pages.md)が未ログインで到達可能．App Store Connectにも言語別URLを保存した．アプリ内導線の残りの端末での確認は別項目 | 実装担当 |
| 公開のサポートURL | 確認済み | [4言語のURL](public-pages.md)が未ログインで到達可能．連絡先は利用者が承認した `contact@shiftone.ai` | 実装担当 |
| アプリ内のページとライセンス | 確認済み | iPhone SimulatorのiOS 27英語・iOS 26.4簡体字中国語と，iPad Pro 13インチ SimulatorのiOS 26.4日本語でプライバシー・サポートの遷移が成功した．iPhoneとiPadでライセンス表示が成功した．開けないURLの試験用設定では，両Simulatorで設定保存・展示開始・管理者解除が成功した．統合後のMac archiveを開発用に再署名して起動し，Safariへのプライバシー・サポート遷移，ライセンス表示，展示ページ移動と管理者解除を手元のMacで確認した．同じ環境で開けないURLを保存して展示を始めると「Exhibition stopped」が表示され，管理者パスワードで設定へ戻れた．Web管理はローカルブラウザからログイン・設定保存・展示開始を操作し，無効化後の接続拒否も確認した．基本操作の検証にはSimulatorの結果を採用する．App Store配布署名の状態での照合は別項目 | 実装担当 |
| App Privacy | 申告済み・審査待ち | 利用者の承認を受け，App Store Connectで「アプリから収集するデータなし」を公開した．[データ取扱い](privacy-facts.md)にWeb管理とWebViewのオープンWeb例外に関する推測を記録した．利用者はAppleへの個別照会を省き，審査結果を受けて必要なら修正する方針 | 公開担当 |
| Privacy Manifest | 確認済み | `systemUptime`の35F9.1と`UserDefaults`のCA92.1をソースと照合し，統合後のiOS archiveとMacの配布用パッケージ内アプリでmanifestを検査した．配布用IPAは`check-artifact.py`でmanifestの同梱を確認した | 実装担当 |
| 年齢制限 | 確認済み | App Store Connectで任意のWebページへのアクセスを「あり」，同梱の成熟表現などを「なし」と回答し保存した．iOS 26以降の表示は原則16+，旧OSは17+ | 実装担当 |
| 第三者コンテンツの権利 | 確認済み | 審査用の[展示サンプル](public-pages.md)は自作．管理者が展示サイトの表示権利・許可を確認する運用を利用者が承認し，4言語の[サポートページ](public-pages.md)に記した．App Store Connectで第三者コンテンツを扱い必要な権利がある旨を保存し，再読込で確認した | 公開担当 |
| 暗号利用 | 確認済み | iOSの配布用IPAとMacの配布用パッケージ内アプリで`ITSAppUsesNonExemptEncryption=false`を確認した．App Store Connectの両候補のBuild Metadataにも`App Uses Non-Exempt Encryption: No`と表示された．独自の暗号処理を持たず，OSのKeychain，HTTPS，PBKDF2を使用する範囲をソースと照合した | 実装担当 |
| 価格・税区分 | 確認済み | 利用者の指定に従い，App Store Connectで基本価格$0.00を保存した．税区分は「App Store software」 | 実装担当 |
| 提供地域・公開方法 | 確認済み | 利用者の指定に従い，全175地域を「App Release後に提供」で保存した．iOS版とMac版を手動公開に設定した | 実装担当 |
| 審査用サイト・手順 | 端末単体を確認済み | [自作の展示サンプル](public-pages.md)は公開済み．iOS・Macの審査メモをApp Store Connectへ保存した．[原稿](review-notes.md)の端末単体の操作はiPhone・iPad Simulatorと開発用署名のMac候補で確認した．配布署名のiOS候補と外部ディスプレイの操作は未確認 | 実装担当 |
| 審査連絡先 | 確認済み | 利用者が提示した氏名・電話番号・メールアドレスをApp Store ConnectのiOS・Mac両版の審査情報へ保存し，再読込で確認した．公開文書に非公開の連絡先を置かない | 実装担当 |
| 署名済み候補と実機 | 修正版を審査へ送信・実機操作は一部未実施 | 最初の審査候補はiOS`20261017024237`，Mac`20261017024541`．PRレビュー後にライセンス画面の状態管理，管理終了時の遅延ページ起動，直接ビルドの著作権欄を修正した．修正版のiOS`20261018160254`とMac`20261018160517`はApple Distribution署名と`check-artifact.py`を通過し，App Store Connectで「Ready to Submit」と表示された．両版の旧申請を取り下げ，修正版を選択して審査へ再提出した．両修正版を本人だけのTestFlight内部グループに割り当てた．MacのTestFlight版は修正版へ更新し，`/Applications/Plinth.app`のビルド番号とTestFlight Beta Distribution署名を確認した．起動時に保存済みの管理画面が表示された．管理画面・解除などは開発用署名の候補とSimulatorで確認済み．iPhoneとiPadで先に完了した実機試験は[対応方針](../design-docs/ipad-support.md)に記録済み．接続中のiPhone 15 Pro Maxには旧iOS候補ビルドが入っているが操作していない．接続中のiPad miniも旧ビルドのまま | 実装担当 |

## 現在の判定

**修正版のiOS 1.0とmacOS 0.1.0を審査へ送信済み**．PRレビューで見つかった不具合3件を修正し，旧申請を両方取り下げてから修正版を再提出した．App Store ConnectでiOS`20261018160254`とMac`20261018160517`の「1 Item Submitted」と「Waiting for Review」を確認し，旧申請は両方「Removed」と表示された．承認後の公開は手動に設定している．24枚の言語別画像は登録済み．開発用署名のMac候補では管理・展示画面，公開ページへの導線，Web管理，通信失敗時の解除を確認した．TestFlight配布版の修正後Mac候補は更新して起動し，保存済みの管理画面が表示された．利用者は端末単体の基本操作にSimulatorの結果を採用する．今回のiOS配布候補の実機操作と，外部ディスプレイ・物理入力を使う経路は未確認．App PrivacyのWebView通信に対する例外の適用は推測であり，利用者は個別照会を省いて審査を受ける方針を示した．サポート窓口はGoogle Workspaceの問い合わせグループの別名で，過去の配信実績を確認した．受信者のメールや複製の削除条件は未確認のため，公開ポリシーには保存期限を約束していない．

## 残る確認

1. `contact@shiftone.ai` はGoogle Workspaceの問い合わせグループの別名．会話履歴とGmailの自動削除はオフ，Vaultの保持ルールと保留は未設定．外部投稿は許可され，2人のオーナーのうち1人が投稿ごとのメールを受け取る設定で，もう1人は配信エラーが表示される．受信者のGmailには別名宛ての既存メールがあり，過去の配信実績は確認できた．保留中のメッセージが1件ある．新たな受信試験と受信・保留メールの削除範囲を調べ，[運用手順](support-data.md)の削除を実行できる状態にする．公開ポリシーの期限はその後に決める．
2. 管理者が任意の展示先を設定できる点を根拠に，WebViewの通信をAppleの「オープンWeb閲覧」の例外として扱う推測を[調査記録](privacy-facts.md)に記した．Appleへの個別照会は行わない．審査で変更を求められた場合は，App Privacyの回答と公開ポリシーを照合して修正する．
3. 今回のiOS配布候補で実機操作を行う場合は，保存済みの設定を確認してから初回設定・展示・解除・再起動・通信失敗を試す．外部ディスプレイと物理入力を使う経路には対応機器が必要．基本操作はSimulatorで検証済みであり，実機での未確認範囲を区別して記録する．
