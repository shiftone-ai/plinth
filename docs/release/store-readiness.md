# App Store公開準備表

Issue #28の提出可否を判断する表．iPhone／iPad版とMac専用版はApp Store Connectの同じアプリ記録の別プラットフォームであり，製品ページの説明・画像・候補ビルドは別に照合する．ここには公開できる確認結果だけを記録する．審査提出と一般公開は別の作業．

| 項目 | 状態 | 確認元・完了条件 | 担当 |
| --- | --- | --- | --- |
| アプリ名・Bundle ID | 要確認 | App Store Connectの日本語名はPlinth Kiosk，Bundle IDは`ai.shiftone.plinth.mobile`で両プラットフォーム共通．署名済みのMacアプリとiOS IPAで同じIDを確認した．iOSの版数は製品ページと候補で1.0にそろえた．製品ページの最終表示を照合する | 実装担当 |
| カテゴリ・サブタイトル | 確認済み | App Store Connectで主カテゴリをUtilities，4言語のサブタイトルを[原稿](store-listing.md)どおりに保存した | 実装担当 |
| 著作権表示 | 要判断 | iOS・Mac版のCopyright欄は空欄．権利者の正式な表記を公開担当が決め，両版へ保存する | 公開担当 |
| 説明・キーワード・サポートURL | 確認済み | App Store ConnectのiOS版とMac版で，4言語の説明・キーワード・サポートURLを[原稿](store-listing.md)どおりに保存した．選定ビルドとの最終照合は別項目 | 実装担当 |
| アイコン | 要確認 | `Resources/Assets.xcassets`のアイコンを目視し，Macのarchiveの`Assets.car`に16～1024pxのAppIconが入ることを確認した．製品ページの最終表示を照合する | 実装担当 |
| iPhone・iPad・Macの画像 | 要確認 | [画像](screenshots/)に4言語それぞれのiPhone 17 Pro Max（1320×2868）・iPad Pro 13インチ（2064×2752）のSimulator実画像を2枚ずつ保存した．App Store Connectの言語別Media Managerで各2枚の登録を確認した．Macは提出候補のアーカイブを開発用に再署名して起動し，管理・展示画面を2560×1600の画像2枚に保存した．画像は未登録で，App Store配布署名の状態での画面は未確認 | 実装担当 |
| 公開のプライバシーURL | 確認済み | [4言語のURL](public-pages.md)が未ログインで到達可能．App Store Connectにも言語別URLを保存した．アプリ内導線の残りの端末での確認は別項目 | 実装担当 |
| 公開のサポートURL | 確認済み | [4言語のURL](public-pages.md)が未ログインで到達可能．連絡先は利用者が承認した `contact@shiftone.ai` | 実装担当 |
| アプリ内のページとライセンス | 要確認 | iPhone SimulatorのiOS 27英語・iOS 26.4簡体字中国語と，iPad Pro 13インチ SimulatorのiOS 26.4日本語でプライバシー・サポートの遷移が成功した．iPhoneとiPadでライセンス表示が成功した．開けないURLの試験用設定では，両Simulatorで設定保存・展示開始・管理者解除が成功した．MacのReleaseプレビュー版でも実機UIテスト1件が成功した．提出候補のアーカイブを開発用に再署名して起動し，Safariへのプライバシー・サポート遷移，ライセンス表示，展示画面の描画を手元のMacで確認した．同じ環境で開けないURLを保存して展示を始めると「Exhibition stopped」が表示され，管理者パスワードで設定へ戻れた．App Store配布署名の状態での照合は未確認 | 実装担当 |
| App Privacy | 公開済み | 利用者の承認を受け，App Store Connectで「アプリから収集するデータなし」を公開した．公開済みの表示を確認した．[データ取扱い](privacy-facts.md)にWebViewのオープンWeb例外に関する推測・不確実性を記した | 公開担当 |
| Privacy Manifest | 確認済み | `systemUptime`の35F9.1と`UserDefaults`のCA92.1をソースと照合し，iOSの配布用IPAとMacの配布用パッケージ内アプリでmanifestを検査した | 実装担当 |
| 年齢制限 | 確認済み | App Store Connectで任意のWebページへのアクセスを「あり」，同梱の成熟表現などを「なし」と回答し保存した．iOS 26以降の表示は原則16+，旧OSは17+ | 実装担当 |
| 第三者コンテンツの権利 | 確認済み | 審査用の[展示サンプル](public-pages.md)は自作．管理者が展示サイトの表示権利・許可を確認する運用を利用者が承認し，4言語の[サポートページ](public-pages.md)に記した．App Store Connectで第三者コンテンツを扱い必要な権利がある旨を保存し，再読込で確認した | 公開担当 |
| 暗号利用 | 要確認 | iOSの配布用IPAとMacの配布用パッケージ内アプリで`ITSAppUsesNonExemptEncryption=false`を確認した．Appleの申告画面と利用範囲を再確認する | 実装担当 |
| 価格・税区分 | 確認済み | 利用者の指定に従い，App Store Connectで基本価格$0.00を保存した．税区分は「App Store software」 | 実装担当 |
| 提供地域・公開方法 | 確認済み | 利用者の指定に従い，全175地域を「App Release後に提供」で保存した．iOS版とMac版を手動公開に設定した | 実装担当 |
| 審査用サイト・手順 | 要作成 | [自作の展示サンプル](public-pages.md)は公開済み．iOS・Macの審査メモをApp Store Connectへ保存した．[原稿](review-notes.md)をMac候補と実機で再照合する | 実装担当 |
| 審査連絡先 | 確認済み | 利用者が提示した氏名・電話番号・メールアドレスをApp Store ConnectのiOS・Mac両版の審査情報へ保存し，再読込で確認した．公開文書に非公開の連絡先を置かない | 実装担当 |
| 署名済み候補と実機 | 要確認 | iOSの配布用IPAとMacの配布用パッケージはXcodeのローカル書き出しが成功した．両アプリのApple Distribution署名と`check-artifact.py`を確認し，Macパッケージは`productutil`でも署名と内容を検査した．両ビルドはApp Store Connectで処理済みとなり，各プラットフォームの版へ選択・保存した．Mac候補は本人だけが参加する既存のTestFlight内部グループへ追加し，Testingの表示を確認した．iPhoneとiPadで先に完了した実機試験は[対応方針](../design-docs/ipad-support.md)に記録済み．候補との差分である公開ページとライセンスはSimulatorで操作した．Mac候補のアーカイブは開発用に再署名した状態で画面を確認し，App Store配布署名の状態では未確認 | 実装担当 |

## 現在の判定

**審査提出不可**．Mac用画像の登録と著作権の正式な表記が残る．提出候補のアーカイブを開発用に再署名し，手元のMacで管理・展示画面，公開ページへの導線，通信失敗時の解除を確認した．配布署名済み候補をTestFlightで起動した結果は未確認．App PrivacyのWebViewに関する解釈にも不確実性がある．サポートメールの保管先が[運用手順](support-data.md)の期限を満たすか未確認のため，公開ポリシーには期限を記載していない．対応機器やOSの表示方法は[掲載文](store-listing.md)に限定して記した．未完了のWeb管理は掲載しない．
