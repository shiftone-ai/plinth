# 開発と検証

Core・Presenter・RuntimeとPassive SwiftUI Viewを共用し，Mac・UIKitの起動処理とNative Adapterを結合している．実装した機能と受け入れ試験の完了は区別する．

## 管理画面の言語

管理画面，展示停止，管理者解除，入力エラー，アクセシビリティ名は英語・日本語・韓国語・中国語の簡体字に対応する．文言は `KioskLocalization` のString Catalogで管理する．原文は英語とし，追加手順は [翻訳の規約](rules/localization.md) に記録した．

初期値はOSが選んだ言語で，管理画面の「表示言語」からその場で変更できる．選択は端末に保存され，次の起動にも適用される．「システムに従う」を選ぶとOSの言語に戻る．

対応外の言語と未翻訳の文言は英語で表示する．端末が配信するWeb管理画面も同じString Catalogの訳を使う．展示するWebページの文言はアプリでは翻訳しない．

管理画面に日付表示はない．無操作時間は秒で入力し，解像度はピクセル数で表示する．対応言語の数値入力は小数点に `.` を使う．表示言語は展示設定・管理者パスワードと別に保存するため，言語を変えても設定と認証状態は変更しない．

英語原文のcatalogと英語へのフォールバックは単体試験で確認した．iPad Air 11インチ（M4）のiPadOS 26.4 Simulatorでは，ja・en・ko・zh-Hansそれぞれで入力・保存・実WebKitでの展示・誤入力と取消を含む管理者解除を通した．画面内で言語を切り替えた後の再起動でも，保存済みの設定と管理者パスワードを使えた．frでは英語に戻り，倍長の擬似翻訳でも縦・横の設定画面を操作できた．韓国語と簡体字中国語の取得画像では，文言の重なりや切れを確認しなかった．

同じSimulatorの設定アプリには英語・日本語・韓国語・簡体字中国語が表示された．日本語を選んでPlinthを通常起動し，日本語の管理画面を確認した．iPadOS 26.4 Simulatorの外部画面を720×480で接続し，4言語それぞれで展示を開始して，本体の操作面と展示中のアイコンのaccessibility名をUI試験で確認した（1件成功，失敗・skip 0件）．iPadOS 27.0 Simulatorでも外部Sceneを接続し，同じ4言語のUI試験が成功した．このSceneの接続方法はiPadOS 27以降で変わり，Plinthは新しいScene accessory登録を使う（[Appleの外部表示資料](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display)）．Xcode 27の`XCUIVoiceOverService`を使うと，iPadOS 27.0 Simulatorで外部展示の操作面・展示状態・管理者解除ボタンの発話文字列を4言語とも取得できた．実機のスピーカーからの音声とジェスチャー操作は，この試験には含まない．

macOS 27.0.1の専用Macでは，スクリプト生成とXcodeの両.appをビルドし，4言語のresource bundleを確認した．両.appのpreviewで4言語の設定入力・保存・WebKit展示・誤入力・取消・管理者解除・再起動のGUI試験がそれぞれ1件成功し，失敗は0件だった．編集・終了メニューの4言語の項目も両.appで操作し，それぞれ1件成功した．`-NSShowNonLocalizedStrings YES` と `-NSDoubleLocalizedStrings YES` の起動と画面操作は両.appで成功した．倍長の擬似翻訳の上部・下部の画像では，項目とボタンに重なりや切れは見られなかった．Xcodeの.appでは通常モードも試し，設定・展示・アイドル復帰・終了操作の抑止・誤入力と取消を含む管理者解除・再起動が1件成功し，失敗とskipは0件だった．

iPadOS 26.4 SimulatorのTouch IDでは，有効化・無効化・再起動後の保持と，OSの認証画面での取消を操作した．iOS 26.4のiPhone SimulatorではFace IDの認証画面を確認し，登録解除で設定がオフになり，再登録後もオフのままであることを確認した．

管理者解除画面の生体認証ボタンは，iOS 26.4のiPhone SimulatorとiPadOS 27.0のiPad Simulatorで，結果を差し替えたPortによる成功・失敗・取消・登録変更のUI試験が各4件成功した．方式名と管理者パスワードへの切替も画面から操作した．macOS 26.6.2のMacでは，結果を差し替えたPortによる成功・失敗・取消のUI試験が各1件成功し，パスワード欄の横にTouch IDのアイコンが出る位置と読み上げ名も検査した．これらの試験は実際のFace ID・Touch IDや外部ディスプレイを検証しない．

iOS 27.0.1のiPhone実機（Face ID）では，隔離したbundle IDと資格情報serviceを使うApple Development署名版のDebugビルドで，管理者パスワードを保存してFace IDを有効にした．本体で `https://example.com/` を展示し，Face IDで管理者設定へ戻れた．認証要求の受理とKeychain照会の成功，設定画面への遷移を確認した．このビルドでの認証失敗・取消・遅延完了は実機では未確認である．

iPadOS 26.6.2のiPad実機（Touch ID）では，同じ隔離したDebugビルドでTouch IDを有効にし，本体展示と外部ディスプレイ展示の両方で指紋による管理者解除が成功した．外部ディスプレイ展示では，解除画面はiPad本体に表示され，外部画面は黒画面になった．認証後は本体の設定画面に戻った．誤った指紋・取消・遅延完了は実機では未確認である．

macOS 26.6.2のMac実機（Touch ID）では，隔離したbundle IDと資格情報serviceを使うApple Development署名版のpreviewで，管理者パスワード保存，Touch IDの有効化，展示中のTouch IDによる管理者解除が成功した．解除時は管理者パスワードを入力せず，認証後に設定画面へ移った．認証中の取消でパスワード欄へ戻ることと，Plinthを前面にして20秒待った後のTouch ID解除も確認した．通常モードとDeveloper ID配布版での解除は未確認である．

Macでは，生体認証の設定を実装した際のソースをDeveloper IDで署名して書き出し，`keychain-access-groups` とそれを認めるprovisioning profileを確認した．同じ署名設定の診断用ビルドで，隔離したserviceに `.biometryCurrentSet` のData Protection Keychain項目を作成・削除した（`SecItemAdd = 0`，`SecItemDelete = 0`，削除後 `errSecItemNotFound`）．認証を許さない値の照会は `errSecInteractionNotAllowed` だった．配布用UIでのTouch ID操作と失敗時の表示，実機で登録済みの顔・指紋を別の登録に入れ替えたときの失効は未確認である．

## Webからの管理

端末の管理画面で管理者パスワードを設定し，「Webからの管理」を有効にして保存すると，端末がHTTPの47623番ポートで待ち受ける．管理画面に表示されるURLとQRコードは接続先だけを示し，ログインには管理者パスワードを入力する．この設定は既定で無効であり，ブラウザから有効化・無効化できない．待ち受けに失敗した場合は管理画面に理由を表示する．

通信は暗号化されない．運用では展示用ネットワークを他の用途から分け，ルーターのDHCP予約などで端末のアドレスを固定する．アドレスが変わった場合は端末の管理画面に出る新しいQRコードを使う．iPad・iPhoneの背景移行とMacのスリープ復帰ではlistenerを作り直し，期限内のセッションを保つ．保存要求中に通信が切れた場合，ブラウザは保存結果が不明と表示するため，再接続後に最新の保存済み設定を確認する．通信と権限の条件は [ADR 0003](adr/0003-web-administration.md) に記録した．

Swift Testingでは同じdraft・認証・保存・出力選択・展示中のやり直し・停止・再開・listenerの同一ポートでの作り直しを確認した．実HTTPへの未認証要求，Host・Originの不一致，セッションの置き換えと期限切れも通した．実WebKitでは，別の設定変更への応答が入力中の値を消さないことを確認した．

Mac用のDeveloper ID版は署名・公証・stapleと成果物検査を通した．Sandbox付きの`--app-store`版も配布署名で書き出し，成果物を検査して内部TestFlightに配布した．macOS 26.6.2でTestFlightから更新したアプリの署名には，Sandboxと`com.apple.security.network.server`が含まれていた．

ヘッドレスChromiumから試験用Runtimeの実HTTPへ接続し，ログイン，管理中からの展示開始，展示中のURL変更と保存，やり直し，停止，再開を操作した．保存中に通信を切った場合も，保存結果が不明という表示を確認した．Mac向けの試験用Runtimeでは，ブラウザで出力方式と画面を選び，保存結果と画面の表示を確認した．

iPadOS 27.0 Simulatorの管理画面でWeb管理を有効にし，URLとQRコード，アプリ再起動後の設定保持をUI試験で確認した．同じSimulatorで動くアプリのHTTPサーバーへヘッドレスChromiumでログインし，展示中のURL変更・保存・やり直し・停止・再開を操作した．停止中の本体画面には展示停止の表示だけがあり，管理・認証画面は出なかった．アプリを背景に移したときは接続が拒否され，前景へ戻すと同じURLとセッションで接続できた．

外部画面を接続したiPadOS 27.0 Simulatorでは，ブラウザから開始URL・展示先・回転・解像度を保存し，展示をやり直した．外部画面は `/home` から `/allowed` に変わり，本体には鍵と画面のアイコンだけが表示された．実ネットワーク上のスマートフォンからの接続と物理ディスプレイでの表示は，この試験には含まない．

Issue #23では，iPadOS 26.6.2の実機に内部TestFlight版を更新し，管理画面でWeb管理を有効にしてURLとQRコードを表示した．同じネットワークのMacからiPadのHTTP画面へ接続できた．iOS 27.0.1のiPhoneのSafariでもiPadのQRコードからWeb管理画面にログインし，無操作復帰を120秒から121秒へ保存した．iPad本体の管理画面にも121秒が表示され，iPhoneのSafariから120秒へ戻すと本体表示も120秒になった．iPadを設定アプリへ切り替えるとHTTP接続は拒否され，Plinthへ戻すと同じURLで200が返った．待ち受けを有効にした時点とMacから接続した時点では，iPadにローカルネットワーク許可の表示は出なかった．

macOS 26.6.2ではDeveloper ID版と，内部TestFlightから更新したSandbox付きApp Store版を隔離した設定で起動した．両方とも実HTTPにヘッドレスChromiumでログインでき，設定の保存・展示のやり直し・停止・再開が成功した．Sandbox版の保存結果はアプリの保存ファイルでも確認した．このMacのファイアウォールは無効だったため，確認ダイアログは出ない条件だった．

その後，iPad実機に外部ディスプレイを接続し，内部TestFlight版を入れた．iPadOS 26.6.2で，展示中は外部にWebページ，本体には展示用の操作だけが表示された．本体で管理画面を開くと外部は黒くなり，管理画面は出なかった．旧版ではWebからの停止→再開と展示のやり直しで「マウスを固定できません」と表示され，外部画面が黒くなった．Rootに古いマウス固定状態が残る経路を修正し，両操作で解放してから再開時に取得し直すCore試験が成功した．また，展示中のiPad本体からQRコードを読めなかったため，外部展示中の本体に表示するよう変更した．

修正版の内部TestFlight版をiPadへ更新し，本体のQRコードをiPhoneのSafariで読んでiPadのWeb管理画面へログインした．Webから展示を開始し，停止・再開・やり直しを1回ずつ操作した．開始・再開・やり直しの後は外部にWebページ，本体にQRコードと展示用の操作が表示され，マウス固定エラーは出なかった．停止中は両画面に停止表示が出た．各状態の本体・外部画面を取得し，管理画面と認証画面が出ないことを確認した．Webからの展示開始は実HTTPとヘッドレスChromiumでも，やり直し・停止・再開と外部への表示はiPadOS 27.0 Simulatorでも確認した．共通の認証待ち時間は，実機の管理者アカウントを一時的に待ち時間へ入れるため未実行である．

iPad実機で展示中に画面を消すとWeb接続は拒否され，起こしてPlinthへ戻すと同じURLがHTTP 200で応答した．Wi-Fiをオフにすると接続はタイムアウトし，オンへ戻すと同じURLでHTTP 200に復帰した．Wi-Fi切り替え後の展示は停止表示になったが，iPhoneのSafariからWebで再開でき，外部画面にページが戻った．Macのスリープ復帰とアドレス変更は，作業中のMacの接続を切るため未実行である．iOS 27.0.1のiPhone実機では内部TestFlight版への更新と展示の表示を確認した．管理画面でWeb管理を有効にした後，同じネットワークのMacとiPadのSafariから接続でき，iPadのSafariではログインして設定画面を表示した．未認証の設定取得は401，異なるHostと`Origin: null`では403だった．iPhoneを背景へ移すと接続は拒否され，前景へ戻すと同じURLで再接続できた．更新版ではiPadのSafariにiPhoneの設定・編集画面が表示された．ユーザーから展示操作のボタンはすべて効いたと報告を受け，終了時のiPhone本体に展示ページが出ていることを取得画像で確認した．各操作の遷移は個別に取得していない．iPhoneをサーバーとする設定の編集・保存は，iPadと同じモバイルのWeb管理経路を使うため実機では繰り返していない．

PRレビュー後，管理者パスワード変更時のWebセッション失効と検証中のログイン取消，背景中に完了した保存・起動処理からの待ち受け再開防止，Web編集中の下書き保持，待ち受け異常終了後のURL消去を追加した．取消待ちの起動が取り消された場合も，新しいlistenerを作らない．Core・Runtimeの回帰試験と実TCPを使ったlistener試験が成功した．実HTTPとヘッドレスChromiumでは，ログイン中のブラウザからパスワード変更後に再ログイン画面へ戻ることを確認した．通信エラーの誤表示も直し，実ブラウザの取得画像とWebKit試験で確かめた．MacのNative試験とiOSのDebug・Releaseビルドが成功した．この修正を含む配布版での実機操作はまだ確認していない．

続いてiPadOS 27.0 Simulatorの実アプリにヘッドレスChromiumで接続し，設定保存・展示開始・停止・再開・やり直しを操作した．アプリを背景へ移すと接続が止まり，前景で復帰した．Webの未保存下書きを残したまま端末の管理画面を開いても，下書きは残った．パスワード変更後，ブラウザの編集欄にフォーカスがあると定期的な状態確認自体が止まり，古い画面が残る不具合を見つけた．編集中は表示値を更新せずに認証状態だけを確認するよう修正した．同じSimulatorとブラウザで，旧セッションが通信エラーを出さずログイン画面へ戻ることを確認した．WebKitの回帰試験も成功した．

PRレビューでは，編集中に接続が戻ってもエラー表示が残ることと，旧セッションへの遅い応答が新しいログインを消すことを確認した．WebKit試験2件を先に失敗させ，応答時のセッション確認と接続復帰時の表示更新を修正して成功を確認した．旧セッションの通信エラーも，新しいログインには表示しないことを同じ試験で確認した．

## 環境とtarget

確認した環境はmacOS 26.6.2（arm64），Xcode 27.0，Swift 6.4，macOS SDK 27.0．deployment target，Swift language mode，target別のdefault isolationは [Package.swift](../Package.swift) で管理する．upcoming featureの個別指定は追加していない．

| target | 実行境界 |
| --- | --- |
| KioskCore | FoundationのURL解釈と，actorに依存しない値モデル・Policy・遷移関数 |
| KioskPresentation | Coreの状態から不変Propsへの純粋な投影 |
| KioskRuntime | MainActorの所有・配送・WebKit・Task管理と，独立actorでの保存・資格情報I/O |
| KioskUI | MainActorの共通Passive SwiftUI View |
| KioskMacApp | AppKitの入力・通知・PresentationとRuntimeの組み立て |
| KioskMobileApp | UIKitのScene・入力・PresentationとRuntimeの組み立て |
| Plinth | MainActorでのNSApplicationの起動，CLIオプション |

`zsh scripts/build-app.sh` はReleaseビルドから `.build/Plinth.app` を生成し，ローカル用の署名を付ける．App Storeを通さずに渡す版は `scripts/build-notarized-app.sh` でDeveloper ID署名と公証を行う．配る前の成果物は `just check-artifact <path>` で調べる．手順は [Developer ID配布](distribution.md#macのdeveloper-id配布) を参照する．配布用installerは作っていない．

iPadの本体・外部への展示とマウス入力は [対応方針](design-docs/ipad-support.md) を参照する．iPad・iPhone targetは実装済みで，iOS／iPadOS 18.4以降を対象とする．iOS 27のiPad・iPhone Simulatorで設定から解除までの通し試験が成功した．iOS 27.0.1のiPhone実機への直接インストール・起動と同じ通しUI試験も成功した．外部のマウス入力は接続とロック成立・カーソル描画を実機で確認した．物理入力によるWeb操作・画面の端での制限・端末制限との併用は確認が残る．18.4系のruntimeは現在のXcodeでダウンロードできず，古いOSでの実行は未確認．[実機への配布](distribution.md) に署名とTestFlightの状態をまとめる．

## 実行する検査

プロジェクトのルートで，devenvの開発シェルから実行する．direnvを使う場合は初回に `direnv allow` を実行する．シェルに入らずに実行するときは `devenv shell -- just check` とする．

```sh
just fmt     # Swift・Python・shell・Nixを整形する
just lint    # swift-format・SwiftLint・ruff・shfmt・nixfmtで検査する
just secrets # commit済みの履歴全体をgitleaksで調べる
just test    # 警告をエラーとしてビルドし，テストを実行する
just check   # lint・secrets・testを続けて実行する
```

`just test` は `swift build` と `swift test` を `-Xswiftc -warnings-as-errors` 付きで実行し，`scripts/test_*.py` も実行する．`just test-native` はNative結合試験を含め，`just coverage` はファイル別の行カバレッジを表示する．iOS専用のコードは `#if os(iOS)` で囲まれ，macOSの `swift build` では検査されないため，`just build-ios` でDebugとReleaseを署名せずにビルドする．

SwiftのtoolchainとSDK，swift-formatはXcodeのものを使う．nixpkgsのapple-sdkとC compilerは開発シェルに入れない．SwiftLint・ruff・shfmt・nixfmt・gitleaks・justの版は `devenv.nix` と `devenv.lock` で固定する．

開発シェルに入るとgit hookが入る．commit前は変更したファイルを整形・検査し，stageした変更から秘密情報を探す．push前は `just test` を実行する．push前の検査は作業ツリーをビルドするため，commitしていない変更も結果に含まれる．GitHub Actionsは `xcode-27` runnerで `devenv test`，Web管理画面のWebKit試験，`just secrets` を実行し，Nixを使わない `just build-ios` を別のjobで並べて実行する．

git hookは全worktreeで共有され，最後に開発シェルへ入ったworktreeの設定を指す．そのworktreeを削除するとcommitとpushが失敗するため，残っているworktreeで開発シェルに入り直す．

SwiftLintの既存の違反は `.swiftlint-baseline.json` に記録し，記録にない違反だけを失敗にする．照合には関数の行数や複雑さの値も含まれるため，記録済みの関数でも値が変わると失敗する．違反を直したときや値が変わったときは `just lint-baseline` で記録し直し，違反が増えていないか差分を確かめてからcommitする．

## テストの範囲

- `Tests/KioskCoreTests/` はURL・入力Policy，Root／Exhibition／Administrationの遷移，Reply，Effectの順序，拒否理由を検証する．
- `Tests/KioskPresentationTests/` は未完成のdraft，開始・保存の有効状態，解除中のWeb入力停止を表示用の値として検証する．
- `Tests/KioskRuntimeTests/` は所有ツリーとCoRの経路，状態確定後のEffect実行，再入，取消・遅延結果，replyの一度だけの完了を検証する．
- `Tests/KioskAdapterTests/` は実ファイルへの保存，破損・古いrevisionの拒否，管理者パスワード検証値の生成と照合を検証する．Keychainへの実際の読み書きはこのtargetに含まない．
- `Tests/KioskNativeTests/` は実WebKit・隔離したKeychain・原子的保存・時計を結合する専用target．リンク・リダイレクト・新規ウィンドウ・拒否先・ダイアログ，無操作復帰，認証失敗・取消・成功，通信失敗時の再試行上限を検証する．通常はskipする．
- `Tests/KioskUITests/` はXCTest＋XCUIAutomationで設定から管理者解除までを操作する別target．生成したXcode projectでビルドし，明示的に有効にした専用Macだけで実行する．

時計とPortはテストごとに生成する．非同期処理は対象operationの完了契約まで待ち，実時間sleepやyield回数に依存させない．Projectionの再実行は検証するが，実SwiftUI Viewの再描画試験は別に行う．

## Native結合と実機試験

次のコマンドはNative結合試験を含める．ウィンドウを前面に出さず，OSのPresentation設定も変更しない．リンクはDOMの操作で発火させるため，物理マウスの配送やUI操作の通し試験を代替しない．NativeRuntimeの表示情報は「1画面」のfixtureを注入しており，実際のディスプレイ構成や全画面表示の合格を意味しない．

```sh
PLINTH_NATIVE_TESTS=1 swift test -Xswiftc -warnings-as-errors
```

GUI試験の実行ファイルまでを，アプリを起動せずにビルドできる．生成projectはGit管理対象外であり，Swift package・Info.plist・試験sourceが構成の元になる．

```sh
python3 scripts/create-xcode-project.py
xcodebuild -project Plinth.xcodeproj -scheme Plinth \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode build-for-testing
```

確認した環境では，外部表示対応後のNativeを含む106件のSwift Testing，Mac Releaseアプリの生成，Mac GUI targetの `build-for-testing` が成功した．format lintも成功した．XcodeのAppIntents metadata処理は，依存がないため抽出を省略する旨の通知を出す．macOS 27.0.1の専用Macで，試験用Bundle ID・Sandbox有効のアプリの通常モードGUI試験が通し成功した．全画面，5秒復帰，終了・切り替えの抑制，誤認証，取消，正しい解除，画面復元と保存後の再起動を確認した．通常Bundle IDの開発版は自動試験で前面に移せず，通し試験が完了していない．具体的な試験方法と記録項目は [Mac実機の受け入れ試験](native-acceptance.md) を参照する．macOS 14での実行とIntel Macは未確認．

設定は `~/Library/Application Support/Plinth/profile.json` にrevision付きで原子的に保存する．破損・未知のschemaは展示開始を拒否する．資格情報の検証値はKeychainのservice `ai.shiftone.plinth` に置き，OSの認証UIを呼び出さない設定でアクセスする．HTTPのWeb表示はInfo.plistの `NSAllowsArbitraryLoadsInWebContent` と，Profileの明示許可を併用する．

実Keychainへの保存・照合と通信失敗時の復帰はNative targetで確認した．Macで未確認の項目は，TestFlight版の更新と既存設定の引き継ぎ，複数の実ディスプレイでの入力・遮蔽，Webプロセス終了後の復帰．認証画面は60秒で取消となり，初回読み込み中もPresentation取得後に解除を要求できる．

Dock／メニューバー，OSジェスチャ，ディスプレイ変更，スリープ復帰の受け入れ試験は専用実機で行い，macOS・機種・入力機器と復元経路を記録する．UIテストはXCTest＋XCUIAutomationの別targetに置く．

## MobileのUI試験

`KioskMobileUITests` はXCTest＋XCUIAutomationと端末上のHTTP fixtureを使う．設定保存・実WebKitの許可／拒否リンク・到着後の無操作復帰・誤った管理者パスワード・取消・正しい管理者パスワードでの解除を操作する．Keychainと保存先は試験ごとに分ける．`testCurrentSiteCancelledUnlockAndShortIdle` は展示を設定済みの端末で動かし，開始URLとリンク名を `TEST_RUNNER_PLINTH_TEST_SITE_URL` と `TEST_RUNNER_PLINTH_TEST_SITE_LINK` で渡す．渡さない場合はskipする．

```sh
python3 scripts/create-xcode-project.py
xcodebuild -project Plinth.xcodeproj -scheme PlinthMobile \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath .build/mobile-release CODE_SIGNING_ALLOWED=NO build
```

これは署名しないビルドであり，実機インストールや配布の証明にはならない．署名はXcodeのアカウントと対象チームを確認してから行う．本体での試験は外部Sceneの全画面表示や物理マウスの制限を代替しない．

外部表示専用SceneについてはiPad／iPhoneのiOS 27 Simulatorで，独立した表示，本体からのクリック，禁止URL，解除取消，再開始のUI試験が成功した．外部Webの座標操作と遅延入力拒否はCoreと実WebKitの回帰試験で確認した．実装と制約は [外部表示](design-docs/mobile-external-output.md) を参照する．


外部表示の動画・切断試験は `scripts/test-mobile-external-display.py` で実行する．
専用Simulatorを起動し，外部画面を1920×1080へ設定するため，普段使うSimulatorでは実行しない．
試験はWebKitの再生位置の進行を確認してから切断し，本体の停止を確認してから再接続する．
固定時間で成功を推測せず，ログの通知と画面の状態で進める．

```sh
python3 scripts/test-mobile-external-display.py <iPad SimulatorのUDID>
```

実機のUSB-C・AirPlay接続，音声再生，物理マウスの制限を代替する試験ではない．
試験DriverとNative GUI試験は同じMac上で同時に実行しない．

## 外部入力と復帰の追加検証

専用Macで `PLINTH_NATIVE_TESTS=1 PLINTH_SOAK_TESTS=1 swift test --no-parallel -Xswiftc -warnings-as-errors` を実行し，119件が成功した．実WebKitのhover，Pointer Capture，HTMLドラッグ＆ドロップ，取消とクリック時のユーザー操作状態を含む．5,040回の復帰ではNative Effect Executorを使い，120秒ずつ時計を進めた．表示用Viewが1つであること，旧Viewの取り外し，Taskと記録数の上限を確認した．実時間の1週間運転とは区別する．

旧OS側はiOS 26.4のiPad Simulator，720×480の外部表示で操作・再生・解除・切断・再接続まで成功した．iOS 27のiPhone Simulatorの1920×1080でも同じ操作が通り，動画の再開を画像で確認した．Macのカーソル補正・解除，ウィンドウ表示，署名付きSandboxでの旧Keychain移行・管理者パスワード変更・再起動と，1920×1080全画面の通し試験も実機で成功した．

iPadOS 26.6.2のiPad実機では，外部ディスプレイへの独立表示，リンク・スクロール・解除取消・解除と再開，ドラッグ・無音の再生許可，動画再生が成功した．外部画面の取得画像は四隅まで描画されていた．推奨モードへの明示切替を外し，overscan補正を無効にした版で `testExternalSurfaceFillsDisplay` が成功した．1080pへの切替時に黒帯が消えたが，後の円の確認では縦横比が崩れていた．黒帯の有無だけでモードを適切と判断しない．物理入力によるWeb操作とケーブルの抜き差しは別に確認する．

同じ実機の本体表示でも，設定・許可／禁止リンク・5秒復帰・誤認証・取消・解除・設定アプリへの切替と，戻った後の自動再開が成功した．試験の入力は全桁の反映を待ってから確定する．外部Sceneがある場合にプロセス全体のbackground状態を待つ方法は使わず，設定アプリへの切替を実際に確認する．接続済みの外部画面がある場合は「展示ウィンドウを開く」を表示しない．

## 外部画面の解像度

解像度の選択はPassive ViewからIntentとして送り，Profileへ保存する．初期値はOSの選択で，表示専用Sceneの対応モードから変更できる．起動時のSceneの到着と，モード変更によるSceneの入れ替えはRuntimeが所有する期限付きoperationで待つ．表示情報の取得とモード適用は `MobileDisplayModeAdapter`，開始・停止の裁定は共通Root Mediatorが担う．

iPadOS 26.6.2の実機で，1200pから1080pへの変更・保存と3回の再起動が成功した．外部操作・認証・ドラッグ・動画を含む4ケースも成功した．iOS 26.4と27のSimulatorでも，720×480の保存と各3回の再起動が成功した．

共通の検査は `swift test -Xswiftc -warnings-as-errors`，swift-format，SwiftLintが成功した．SwiftLintの既存の違反件数は40件で，対象関数の分割と行数の変化を反映してbaselineを生成し直した．新しい違反は増えていない．Sources・Tests・Resourcesをそれぞれ指定したgitleaksも成功した．物理入力によるWeb操作と実時間での1週間運転は，これらの試験に含めない．

CoreDeviceの `nativeSize` が1920×1080でも，それだけで適切な出力モードとは判断できなかった．再描画を有効にした最小UIKitアプリで，1080pと720pは実パネル上の円が歪み，1920×1200では正円かつ黒帯なしになった．比較用Viewにはモード切替前の画像の引き伸ばしもあり，`.redraw`で除外した．UIKitが提供するboundsと表示バッファ，取得画像と実パネルを区別する．[公開APIと確認手順](references/mobile-output-aspect-ratio.md)

Plinthでも1920×1200で全4方向の表示・入力・保存後の再起動・解除取消が成功した．ユーザーはテスト中の実パネルでも正円と黒帯なしを確認した．普段の設定を「解像度：自動・右90度」で保存し，通常起動中の出力が1920×1200であることと，実際の展示サイトの表示を取得画像で確認した．ユーザーも文字の潰れと黒帯がないことを確認した．OSのミラーリングとアプリの展示中では出力モードが変わるため，アプリ終了後の値を展示中の値とは扱わない．

## 外部画面の回転

表示専用Sceneの向き変更を最小アプリで試したところ，iPadOS 26.4と27のSimulatorではエラー101で拒否された．Viewの寸法交換とSwiftUIの標準の回転APIでは，縦長のWeb表示と四隅までの描画が成立したため，Plinthへ反映した．保存・開始の裁定は共通Core，Propsへの投影はPresenter，論理寸法の提供はMobileのPresentation Adapter，描画はPassive Viewが担う．

iPadOS 26.4と27のSimulatorで，設定画面から全4方向を選び，クリック・ドラッグ・hover・スクロール，保存後の再起動と解除取消を確認した．90度のインライン動画再生も成功した．iPadOS 27で回転時に発生した端のぼけは，WebKit Adapterでスクロール端効果を非表示にして修正した．修正前に失敗する画素検査を追加し，修正後は両OSで成功した．全4方向の画像も目視した．iPadOS 26.6.2の実機では1920×1200の外部モードで同じ回転・操作・再起動・解除取消を確認した．本体ではURL制限・5秒復帰・認証・停止後の再開も再確認した．物理入力によるWeb操作と縦置きでの動画の全画面表示は未確認．方式と条件は [回転の調査](references/external-display-rotation-precedents.md) を参照する．

## マウス接続と設定案内

iPadOS 26.6.2の実機では，USBハブ経由のトラックパッドを接続し，「ウインドウ表示アプリ」でのロック拒否と本体の設定案内を確認した．「フルスクリーンアプリ」へ変更後，通常設定のPlinthを3回再起動し，展示開始と外部カーソルの描画が成功した．停止中の外部画面には管理者向けの案内を出さないことも取得画像で確認した．

起動直後の外部Sceneの入れ替わりには，既存の期限付き準備operationで描画領域の安定を待つ．Timerの所有と取消はMobileのAdapter，ロック失敗の記録と停止はRoot Mediator，案内の表示はPresenterとPassive Viewが担う．OSのマルチタスク設定を画面寸法から推測しない．設計は [外部表示](design-docs/mobile-external-output.md#マウス固定の設定案内)，導入時の操作は [実機への配布](distribution.md#testflightと展示開始) を参照する．

Coreのロック失敗・喪失・再開始と，Presenterの案内表示条件を回帰試験に加えた．警告をエラーとしたSwift Testingの134件，swift-format，SwiftLint，署名付きRelease archiveが成功した．既存のSwiftLint違反は40件で，新しい違反は増えていない．最小アプリでは実際のトラックパッドの移動・スクロールを記録したが，修正後のPlinthでの物理入力によるWeb操作と画面の端での制限は未確認である．

## 開始URLの自動許可と設定後の復帰

許可リストでは，開始URLのoriginを編集・削除できない行として表示する．追加ルールが空でも保存・展示開始できる．Profileの共通の評価を保存時の検証，遷移と復帰に使い，HTTPの許可やoriginの境界を維持する．UIはPresenterの値を描画し，自動許可のルールをViewから書き込まない．

iPadOS 26.6.2の実機で，開始URLを変更したときの表示への追従，自動行を編集できないこと，追加ルールなしの保存・展示・同じoriginのリンク移動を確認した．マウス固定の失敗から設定を変えて戻るだけでの復帰と，設定アプリへ切り替えた後に管理者解除して展示を再開する操作も成功した．再開時の表示専用Sceneは `foregroundInactive` になり得るため，本体の入力Sceneと同じ準備条件にはしない．この不具合は修正前の実機試験で再現し，修正後に同じ操作を通過した．

専用Macの実WebKitを使うGUI試験でも，追加ルールなしの開始URLを保存し，展示・リンク移動・無操作復帰・管理者解除と再開が成功した．iPadでは自動許可行の配置も取得画像で確認した．

iPadOS 26.6.2の実機で，外部展示から別アプリへの切替と復帰を3回繰り返し，展示の自動再開を確認した．通常の保存済み設定でも同じ操作が成功し，管理中は自動再開しないことも確認した．外部Sceneが先にbackgroundへ移る通知順序で再開待ちが失われていたため，選択した展示Sceneの一時離脱を表示状態の更新前に通知するよう修正した．

警告をエラーとしたSwift Testingの146件が成功した．復帰後を含む物理トラックパッドのカーソル固定とWeb操作，ケーブルの抜き差し，実時間の1週間運転は，この確認と区別する．

## 外部展示のスクロール量

iPadOS 26.6.2の実機で，マウス固定中の同じトラックパッド操作がGameControllerとUIKitの両方へ届くことを記録した．スクロールの受信をUIKitへ統一し，入力値を画面の高さで増幅する変換を取り除いた．マウス移動とボタンは引き続きGameControllerで受け取る．

実WebKitの回帰試験では，720×480と480×720の両表示領域で，120 CSSピクセルの入力によるページの移動量が120ピクセルになることを確認した．ページ内のスクロール領域と逆方向の移動も確認した．Coreと入力キューの試験では，有限のピクセル値の受付，無効値の拒否と，連続入力をまとめても移動量が失われないことを確認する．

iPadOS 26.6.2の実機で，本体の操作面から外部ページの下部までスクロールし，許可／禁止リンク，解除取消，管理者パスワード解除と展示再開が成功した．

Pan Gestureの差分だけを送る最小アプリでは，指を離した後の移動が0になることを同じ実機で再現した．操作面をUIScrollViewへ置き換えた最小アプリとPlinthでは，指を離した後も移動が続くことを確認した．減速率はUIKitの標準の `.normal` とし，独自の慣性計算は加えていない．Plinthの実機UI試験はUIKitの減速中に届いた入力とWebページの移動を検証する．ユーザーも物理トラックパッドで滑らかな減速を確認した．

復帰時に外部Sceneの準備が本体より遅れる場合は，Rootが準備完了を待つ．再びアプリを離れた場合と物理切断では，その待機から勝手に開始しないことをCoreの回帰試験で確認した．通常の保存済み設定での復帰と，外部展示から設定アプリへの切替・復帰を3回繰り返す実機UI試験も成功した．ユーザーも自動復帰を確認した．一括実行では復帰確認の間欠的なタイムアウトを記録しており，原因は未確定である．
