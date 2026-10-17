# AppKit版を既存アプリのTestFlightへ配布する条件

2026-10-16のApp Store Connect確認では，既存アプリ記録にiOS版とmacOS版の両方があり，登録Bundle IDは共通の`ai.shiftone.plinth.mobile`だった．通常のMac開発・Developer ID版で使う`ai.shiftone.plinth`とは異なる．以下は配布前の調査時点の記録であり，現在の提出状況は[公開準備表](../release/store-readiness.md)で確認する．

既存のiOSアプリにmacOSプラットフォームを追加し，別targetで作ったAppKit版を同じApp Store Connectレコードへ配布できる．ただしBundle IDを共通にする必要がある．内部テストへの配布を進める経路はあるが，署名，アップロード検証，Apple側の処理，テスターの利用条件が未解決なら，当日中の完了は保証できない．[Appleのプラットフォーム追加資料](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/)

この調査は公開資料とプロジェクト設定の読み取りのみ．App Store Connectの設定変更，署名資産の作成，アップロード，テスター招待は行っていない．

## 今回の識別子と必要な整理

配布先は既存のApp Store Connectアプリで，Bundle IDは `ai.shiftone.plinth.mobile`．調査開始時の [Mac向けInfo.plist](../../Resources/Info.plist) は `ai.shiftone.plinth` で，[ローカルビルド用スクリプト](../../scripts/build-app.sh) も同じ識別子を使っていた．App Store Connect側の現在の値と権限は，本調査では読み取っていない．

同じアプリレコードへ入れるなら，Mac targetと配布成果物のBundle IDを `ai.shiftone.plinth.mobile` に合わせる．iOSアプリをMac上で実行する方式をAppKit版として扱わず，macOS用targetを別にビルドする．プラットフォームごとのバージョンとbuild番号は異なってよい．[プラットフォーム追加の仕様](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/)

初回アップロード後にApp Store ConnectアプリのBundle IDは変更できないため，既存のmobileレコードを変更する前提にはしない．[Xcodeの配布準備資料](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)

## 署名・Sandbox・Mac target

1. Apple Developer ProgramのteamへMac targetを割り当て，App Store Connect配布用としてArchive／exportする．Apple Distribution証明書はmacOSにも使える．手動でMac Installer Packageを署名する場合はMac Installer Distribution証明書を使う．Developer IDはMac App Store外の配布用である．[証明書の用途](https://developer.apple.com/help/account/create-certificates/certificates-overview)
2. Native MacのTestFlightにはprovisioning profileが必須．自動署名ならXcodeが用意し，手動署名なら明示的に含める．macOSでの配置先は `Contents/embedded.provisionprofile`．[WWDC21のMac TestFlight解説](https://developer.apple.com/videos/play/wwdc2021/10170/)，[TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
3. 手動でprofileを作る場合，AppKit版のprofileTypeは `MAC_APP_STORE` を使う．`IOS_APP_STORE` や `MAC_CATALYST_APP_STORE` と区別し，対象Bundle IDと配布証明書を対応させる．[Profile作成API](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-profiles)，[profileTypeの公式schema](https://developer.apple.com/documentation/appstoreconnectapi/profilecreaterequest/data-data.dictionary/attributes-data.dictionary)
4. App Store Connect配布用のApp Sandboxを有効にし，その署名・entitlementsの成果物でWeb読み込み，入力，展示開始／解除，保存を確認する．ローカルのad-hoc署名だけで配布条件を満たしたとは扱わない．[Xcodeの配布準備資料](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)，[TestFlight配布に関するApple DTSの回答](https://developer.apple.com/forums/thread/702678)
5. Macのカテゴリ，アイコン，バージョン／build番号，copyright，必要な輸出コンプライアンス情報を設定する．Macのbuild番号はバージョンをまたいで増加させる．[Xcodeの配布準備資料](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)

登録済みのBundle ID resourceと利用可能なprofileは実際に確認する．Bundle IDのplatformには `IOS`，`MAC_OS`，`UNIVERSAL` があり，`UNIVERSAL` は全プラットフォームを表す．識別子の文字列が一致しただけでprofile作成可能と決めない．[BundleIdPlatform](https://developer.apple.com/documentation/appstoreconnectapi/bundleidplatform)，[Bundle ID一覧API](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-bundleids)

## 使用するApp Store Connect API

以下はAPI契約の確認であり，実行済みの操作ではない．グループ・build・Bundle ID resourceのIDは，配布先から読み取った値を使う．

| 目的 | Endpoint | 設定・確認する内容 |
| --- | --- | --- |
| macOSプラットフォームを追加 | `POST /v1/appStoreVersions` | `data.type = appStoreVersions`，`attributes.platform = MAC_OS`，Mac成果物に対応する `versionString`，`relationships.app.data.id` に対象アプリのID |
| Mac用profileを作成 | `POST /v1/profiles` | `profileType = MAC_APP_STORE`，対象Bundle ID resourceと配布証明書へのrelationships |
| iOS-on-MacのTestFlight配布を停止 | `PATCH /v1/betaGroups/{id}` | `data.type = betaGroups`，対象グループのID，`attributes.iosBuildsAvailableForAppleSiliconMac = false` |
| Native Mac buildをグループへ追加 | `POST /v1/betaGroups/{id}/relationships/builds` | 処理済みNative Mac buildへのrelationshipを追加 |
| アップロードを確認 | `GET /v1/apps/{id}/buildUploads` | `filter[platform] = MAC_OS` と状態を確認し，iOS buildと区別する |

追加APIは [App Store version作成](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-appstoreversions)，[Profile作成](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-profiles)，[Beta group更新](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-betagroups-_id_) とその [属性schema](https://developer.apple.com/documentation/appstoreconnectapi/betagroupupdaterequest/data-data.dictionary/attributes-data.dictionary)，[buildのグループ追加](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-betagroups-_id_-relationships-builds)，[アップロード一覧](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-builduploads) で確認した．

## 内部テスターとiOS-on-Macの区別

内部テスターは対象アプリへアクセスできるApp Store Connectユーザーで，上限100人．グループへbuildを自動配布するか手動追加する．`TestFlight Internal Only` でアップロードしたbuildは内部グループだけが対象で，外部テストや顧客への提出に転用できない．[内部テスターの資料](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)

Mac TestFlight用buildにはXcode 13以降が必要．buildの処理と輸出コンプライアンスを解決し，内部グループから利用可能になったことを確認する．外部テスターへ出す初回buildにはレビューが必要であり，内部テストの条件と混同しない．[TestFlight概要](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

iOS buildをApple Silicon Macへ配るTestFlight設定はグループ単位で，そのグループの全iOS buildに適用される．誤配布を止めるなら，関係するグループの `iosBuildsAvailableForAppleSiliconMac` を確認する．この変更はNative Mac buildの配布と別に扱う．[iOS-on-Macのテスト設定](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-iphone-and-ipad-apps-on-macs-with-apple-silicon)，[BetaGroup属性](https://developer.apple.com/documentation/appstoreconnectapi/betagroup/attributes-data.dictionary)

Mac App Store上のiOSアプリの利用可否はPricing and Availabilityの別設定である．Appleの資料が説明する「native macOS版の公開によるiOS-on-Mac版の置き換え」はストア公開の動作であり，TestFlightで既にインストールしたiOS buildの自動置換を保証する記載ではない．[Apple Silicon Macのストア配布設定](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon)

## 完了確認として残ること

1. 既存ASCレコード，Bundle ID resource，macOSプラットフォームと署名資産の対応を確認する．
2. Sandboxを有効にしたAppKit版で，iPad版をMacで使ったときの展示開始不可が解消したことをMac実機で確認する．
3. Native Mac buildをアップロードし，処理完了と内部グループへの配布状態を確認する．
4. MacのTestFlightからmacOS buildをインストールし，OSとbuildを識別したうえで展示を操作する．

Apple側の処理時間，実アカウントの権限・署名資産，Native Mac版のSandbox下での動作は，本調査では未確認．この資料は配布可能な手順の根拠であり，配布済みの証明ではない．
