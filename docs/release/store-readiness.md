# App Store公開準備表

Issue #28の提出可否を判断する表．iPhone／iPad版とMac専用版はApp Store Connectの同じアプリ記録の別プラットフォームであり，製品ページの説明・画像・候補ビルドは別に照合する．ここには公開できる確認結果だけを記録する．審査提出と一般公開は別の作業．Web管理と生体認証を含む現在の`main`から新しい画像とビルドを作成した．App Store Connectでの選択と画像更新は未完了．

| 項目 | 状態 | 確認元・完了条件 | 担当 |
| --- | --- | --- | --- |
| アプリ名・Bundle ID | 要確認 | App Store Connectの日本語名はPlinth Kiosk，Bundle IDは`ai.shiftone.plinth.mobile`で両プラットフォーム共通．署名済みのMacアプリとiOS IPAで同じIDを確認した．iOSの版数は製品ページと候補で1.0にそろえた．製品ページの最終表示を照合する | 実装担当 |
| カテゴリ・サブタイトル | 確認済み | App Store Connectで主カテゴリをUtilities，4言語のサブタイトルを[原稿](store-listing.md)どおりに保存した | 実装担当 |
| 著作権表示 | 確認済み | 利用者が正式な表記を確認した．iOS・Mac版のCopyright欄へ保存し，統合後のMac archiveと配布用パッケージ内の`NSHumanReadableCopyright`で同じ表記を確認した．公開リポジトリには個人名を記録せず，Macのarchive時に`PLINTH_COPYRIGHT`を指定する | 公開担当 |
| 説明・キーワード・サポートURL | 要確認 | App Store ConnectのiOS版とMac版に4言語の説明・キーワード・サポートURLを保存した．[原稿](store-listing.md)のWeb管理も両版に反映した．候補ビルドと最終照合する | 実装担当 |
| アイコン | 要確認 | `Resources/Assets.xcassets`のアイコンを目視し，統合後のMac archiveの`Assets.car`に16～1024pxのAppIconが入ることを確認した．製品ページの最終表示を照合する | 実装担当 |
| iPhone・iPad・Macの画像 | 要確認 | [画像](screenshots/)に統合後のiPhone 17 Pro Max（1320×2868）・iPad Pro 13インチ（2064×2752）の4言語のSimulator実画像を2枚ずつ保存した．Macは新しいarchiveを開発用に再署名して起動し，管理・展示画面を2560×1600の画像2枚に保存した．各画面を目視で確認した．App Store Connectには統合前の画像が残っているため，差し替えと登録結果の確認が必要 | 実装担当 |
| 公開のプライバシーURL | 確認済み | [4言語のURL](public-pages.md)が未ログインで到達可能．App Store Connectにも言語別URLを保存した．アプリ内導線の残りの端末での確認は別項目 | 実装担当 |
| 公開のサポートURL | 確認済み | [4言語のURL](public-pages.md)が未ログインで到達可能．連絡先は利用者が承認した `contact@shiftone.ai` | 実装担当 |
| アプリ内のページとライセンス | 要確認 | iPhone SimulatorのiOS 27英語・iOS 26.4簡体字中国語と，iPad Pro 13インチ SimulatorのiOS 26.4日本語でプライバシー・サポートの遷移が成功した．iPhoneとiPadでライセンス表示が成功した．開けないURLの試験用設定では，両Simulatorで設定保存・展示開始・管理者解除が成功した．統合後のMac archiveを開発用に再署名して起動し，Safariへのプライバシー・サポート遷移，ライセンス表示，展示ページ移動と管理者解除を手元のMacで確認した．同じ環境で開けないURLを保存して展示を始めると「Exhibition stopped」が表示され，管理者パスワードで設定へ戻れた．Web管理はローカルブラウザからログイン・設定保存・展示開始を操作し，無効化後の接続拒否も確認した．App Store配布署名の状態での照合は未確認 | 実装担当 |
| App Privacy | 要確認 | 利用者の承認を受け，App Store Connectで「アプリから収集するデータなし」を公開した．[データ取扱い](privacy-facts.md)にWeb管理を加え，WebViewのオープンWeb例外に関する推測・不確実性を記した．現在の候補と回答を再照合する | 公開担当 |
| Privacy Manifest | 確認済み | `systemUptime`の35F9.1と`UserDefaults`のCA92.1をソースと照合し，統合後のiOS archiveとMacの配布用パッケージ内アプリでmanifestを検査した．配布用IPAは`check-artifact.py`でmanifestの同梱を確認した | 実装担当 |
| 年齢制限 | 確認済み | App Store Connectで任意のWebページへのアクセスを「あり」，同梱の成熟表現などを「なし」と回答し保存した．iOS 26以降の表示は原則16+，旧OSは17+ | 実装担当 |
| 第三者コンテンツの権利 | 確認済み | 審査用の[展示サンプル](public-pages.md)は自作．管理者が展示サイトの表示権利・許可を確認する運用を利用者が承認し，4言語の[サポートページ](public-pages.md)に記した．App Store Connectで第三者コンテンツを扱い必要な権利がある旨を保存し，再読込で確認した | 公開担当 |
| 暗号利用 | 要確認 | iOSの配布用IPAとMacの配布用パッケージ内アプリで`ITSAppUsesNonExemptEncryption=false`を確認した．Appleの申告画面と利用範囲を再確認する | 実装担当 |
| 価格・税区分 | 確認済み | 利用者の指定に従い，App Store Connectで基本価格$0.00を保存した．税区分は「App Store software」 | 実装担当 |
| 提供地域・公開方法 | 確認済み | 利用者の指定に従い，全175地域を「App Release後に提供」で保存した．iOS版とMac版を手動公開に設定した | 実装担当 |
| 審査用サイト・手順 | 要作成 | [自作の展示サンプル](public-pages.md)は公開済み．iOS・Macの審査メモをApp Store Connectへ保存した．[原稿](review-notes.md)をMac候補と実機で再照合する | 実装担当 |
| 審査連絡先 | 確認済み | 利用者が提示した氏名・電話番号・メールアドレスをApp Store ConnectのiOS・Mac両版の審査情報へ保存し，再読込で確認した．公開文書に非公開の連絡先を置かない | 実装担当 |
| 署名済み候補と実機 | 要確認 | 統合後のiOS配布用IPAとMac配布用パッケージを書き出し，Apple Distribution署名と`check-artifact.py`を確認してApp Store Connectへアップロードした．Macパッケージは`pkgutil`でも署名と内容を検査した．現在は処理と各版への選択を確認待ち．iPhoneとiPadで先に完了した実機試験は[対応方針](../design-docs/ipad-support.md)に記録済み．統合後の候補はまだ実機では操作していない | 実装担当 |

## 現在の判定

**審査提出不可**．統合後の画像とビルドは作成・アップロードしたが，App Store Connectへの画像登録と新ビルドの選択が残る．統合後のMacアーカイブを開発用に再署名したアプリでは管理・展示画面，公開ページへの導線，Web管理，通信失敗時の解除を確認した．配布署名済み候補をTestFlightで起動した結果は未確認．App PrivacyのWebViewに関する解釈にも不確実性がある．サポートメールの保管先が[運用手順](support-data.md)の期限を満たすか未確認のため，公開ポリシーには期限を記載していない．
