# App Store公開準備表

Issue #28の提出可否を判断する表．iPhone／iPad版とMac専用版はApp Store Connectの同じアプリ記録の別プラットフォームであり，製品ページの説明・画像・候補ビルドは別に照合する．ここには公開できる確認結果だけを記録する．審査提出と一般公開は別の作業．

| 項目 | 状態 | 確認元・完了条件 | 担当 |
| --- | --- | --- | --- |
| アプリ名・Bundle ID | 要作成 | App Store Connectの日本語名はPlinth Kiosk，Bundle IDは`ai.shiftone.plinth.mobile`で両プラットフォーム共通．`create-xcode-project.py --app-store`で作ったMacの未署名archiveも同じIDだった．署名済み候補と製品ページの表示を照合する | 実装担当 |
| カテゴリ・サブタイトル | 確認済み | App Store Connectで主カテゴリをUtilities，4言語のサブタイトルを[原稿](store-listing.md)どおりに保存した | 実装担当 |
| 説明・キーワード・サポートURL | 確認済み | App Store ConnectのiOS版とMac版で，4言語の説明・キーワード・サポートURLを[原稿](store-listing.md)どおりに保存した．選定ビルドとの最終照合は別項目 | 実装担当 |
| アイコン | 要作成 | `Resources/Assets.xcassets`のアイコンを目視し，Macの未署名archiveの`Assets.car`に16～1024pxのAppIconが入ることを確認した．署名済み候補と製品ページの表示を照合する | 実装担当 |
| iPhone・iPad・Macの画像 | 要作成 | [画像](screenshots/)に4言語それぞれのiPhone 17 Pro Max（1320×2868）・iPad Pro 13インチ（2064×2752）のSimulator実画像を2枚ずつ保存した．Mac画像とApp Store Connectへの登録・表示確認が残る | 実装担当 |
| 公開のプライバシーURL | 確認済み | [4言語のURL](public-pages.md)が未ログインで到達可能．App Store Connectにも言語別URLを保存した．アプリ内導線の残りの端末での確認は別項目 | 実装担当 |
| 公開のサポートURL | 確認済み | [4言語のURL](public-pages.md)が未ログインで到達可能．連絡先は利用者が承認した `contact@shiftone.ai` | 実装担当 |
| アプリ内のページとライセンス | 要作成 | iPhone SimulatorのiOS 27英語，iOS 26.4簡体字中国語でプライバシー・サポートの遷移が成功し，英語でライセンス表示が成功した．iPadの導線試験はSimulatorのテストrunnerが起動できず中断．Macと署名済み候補で確認する | 実装担当 |
| App Privacy | 要判断 | App Store Connectは未回答．管理者指定サイトのWebView通信をAppleの[申告範囲](https://developer.apple.com/app-store/app-privacy-details/)にどう含めるか確定し，両プラットフォーム共通の回答と[公開ポリシー](public-pages.md)を照合する | 公開担当 |
| Privacy Manifest | 要作成 | `systemUptime`の35F9.1と`UserDefaults`のCA92.1をソースと照合し，iOS SimulatorアプリとMacの未署名archiveでmanifestを検査した．署名済み候補でも検査する | 実装担当 |
| 年齢制限 | 確認済み | App Store Connectで任意のWebページへのアクセスを「あり」，同梱の成熟表現などを「なし」と回答し保存した．iOS 26以降の表示は原則16+，旧OSは17+ | 実装担当 |
| 第三者コンテンツの権利 | 要判断 | 審査用の[展示サンプル](public-pages.md)は自作．任意サイトを表示する製品の権利申告をApp Store Connectで確定する | 公開担当 |
| 暗号利用 | 要作成 | iOS SimulatorアプリとMacの未署名archiveのInfo.plistには`ITSAppUsesNonExemptEncryption=false`がある．署名済み候補の利用範囲とAppleの申告画面で再確認する | 実装担当 |
| 価格・税区分 | 確認済み | 利用者の指定に従い，App Store Connectで基本価格$0.00を保存した．税区分は「App Store software」 | 実装担当 |
| 提供地域・公開方法 | 確認済み | 利用者の指定に従い，全175地域を「App Release後に提供」で保存した．iOS版とMac版を手動公開に設定した | 実装担当 |
| 審査用サイト・手順 | 要作成 | [自作の展示サンプル](public-pages.md)は公開済み．iOS・Macの審査メモをApp Store Connectへ保存した．[原稿](review-notes.md)をMac候補と実機で再照合する | 実装担当 |
| 審査連絡先 | 要判断 | 氏名・電話番号・メールアドレスはApp Store Connectで担当者が入力する．公開文書に非公開の連絡先を置かない | 公開担当 |
| 署名済み候補と実機 | 要作成 | MacのApp Store設定でRelease archiveを作り，`check-artifact.py`は成功した．このMacには対象チームの配布用署名証明書がないため，archiveの署名と実機配布は未実施．iPhone・iPad・Macの署名済み候補で影響範囲を確認する | 実装担当 |

## 現在の判定

**審査提出不可**．App Privacy，コンテンツ権利，審査連絡先，画像登録，署名済み候補・実機の照合が残る．サポートメールの保管先が[運用手順](support-data.md)の期限を満たすかも未確認．対応機器やOSの表示方法は[掲載文](store-listing.md)に限定して記した．未完了のWeb管理は掲載しない．
