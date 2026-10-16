# Mac実機の受け入れ試験

通常モードの通し試験には専用Macを用意し，接続ディスプレイを1台にしてから実行する．GUI試験はアプリを前面に出してマウスを動かす．通常モードはDock・メニューバー・アプリ切替の設定を変更する．普段の作業中の端末では実行しない．複数画面の試験も端末の操作者が許可したときに行う．[Testing規約](rules/testing.md) に従い，OSのPresentationを変える試験は実機で明示的に行う．

Mac版は全画面固定とウィンドウ表示に対応する．全画面固定では自動または指定した画面へ出力し，他の画面を黒く覆う．ウィンドウ表示では操作者が位置と大きさを決める．指定画面がなくなった場合は停止する．`--preview` はOS制限を変更しない．Native結合試験の表示fixtureで，複数の実ディスプレイの試験を代替しない．[Macの出力](design-docs/mac-output.md) を参照する．

## 展示中の通知

専用Macの展示用アカウントで，macOSの「システム設定」から集中モードを作る．許可する人・アプリ・通話・時間指定通知，Intelligent Breakthrough & Silencing，ほかのAppleデバイスとの共有を確認する．展示の通知を止める場合は，許可対象を設けず，例外を有効にしない．「スケジュールを設定」からアプリにPlinthのMac専用版を指定すると，開いたときに集中モードが有効になり，閉じるか別のアプリに切り替えると解除される．[Appleの手順](https://support.apple.com/en-ie/guide/mac-help/mchl613dc43f/mac)

1. Plinthを開き，集中モードの有効状態を確認する．管理画面と展示中の両方を確かめる．
2. 外部画面へ展示している間に，別のアプリから試験用通知を送る．展示画面と内蔵画面にバナーと内容が出ないことを確認する．内蔵画面には「管理者解除」と `⌘ ⌥ ⇧ K` が表示されることも確認する．
3. 管理者解除後とPlinth終了後の集中モードを確認し，OSの確認画面が展示を遮る場合は記録する．

集中モードの設定だけで，すべてのOS画面を抑えられるとは扱わない．この項目の実機試験は未実施．

## 自動GUI試験

プロジェクトのルートで実行する．次はarm64 Mac向けのコマンド．GUI試験を有効にする指定がなければ，試験はアプリ起動前にskipする．

```sh
python3 scripts/create-xcode-project.py --enable-ui-tests
xcodebuild -project Plinth.xcodeproj -scheme Plinth \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode \
  -resultBundlePath .build/plinth-ui-acceptance.xcresult test
```

結果bundleの出力先は未使用のディレクトリを指定する．既存の結果を消して再実行しない．

試験は `--preview` で起動し，専用の一時設定と `ai.shiftone.plinth.tests.` 配下のKeychain serviceを使う．製品の設定や管理者パスワードは使わない．設定入力・保存・展示開始・リンク操作・無操作復帰・認証失敗・取消・成功を確認し，管理画面と展示画面のスクリーンショットを結果bundleに残す．製品の資格情報を消さず，試験DriverからKeychainを削除しない．

この試験はOS制限の合格を証明しない．画面内の操作・見た目が設計に合うことを確認し，次の手動試験を行う．実行後は `python3 scripts/create-xcode-project.py` でGUI試験の既定値を無効へ戻す．

## 通常モードの自動試験

previewの通し試験後，同じ専用MacでOS制限を明示的に有効にする．次は通常モードのケースだけを実行する．Debugアプリの専用fixtureを使うため，製品の設定とKeychainは変更しない．Releaseアプリでは通常モードのfixture指定を受け付けない．

```sh
python3 scripts/create-xcode-project.py --enable-ui-tests --enable-os-tests
xcodebuild -project Plinth.xcodeproj -scheme Plinth \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/xcode \
  -only-testing:KioskUITests/KioskWorkflowUITests/testNormalPresentationRestoresAfterAdministratorUnlock \
  -resultBundlePath .build/plinth-normal-acceptance.xcresult test
```

1画面の全領域への展示，アプリ切替・終了要求の抑制，管理者解除後のウィンドウ復元を確認する．Dock・メニューバーの端での操作やOSジェスチャなどは，自動試験だけで確認済みとは扱わず，次の手動試験で確認する．終了後はprojectを既定値で生成し直す．

内蔵画面と外部画面があるMacでは，同じproject設定で `testBuiltInDisplayShowsAdministratorShortcut` を実行する．外部画面に試験用Webページを出し，内蔵画面の遮蔽に解除案内と `⌘ ⌥ ⇧ K` が見えること，ショートカットで認証画面へ進み，解除後に遮蔽が消えることを確かめる．XCTestの画像を結果bundleに保存する．この試験は画面間のカーソル制限や通知の抑制を検証しない．

## 通常モードの手動試験

1. `zsh scripts/build-app.sh` でアプリを生成し，専用Macで `.build/Plinth.app/Contents/MacOS/Plinth` を起動する．通常モードは専用端末上の製品用設定とKeychainを使う．初回は管理画面で開始URL・許可origin・管理者パスワードを保存する．
2. 展示を開始し，次の表を操作する．解除は `⌘ ⌥ ⇧ K`．解除画面の取消・認証失敗では管理画面が出ず，成功したときだけ展示資源とOS制限を解放して管理画面に戻ることを確認する．
3. 管理画面から終了し，ウィンドウとDock・メニューバー・アプリ切替が元の状態へ戻ったことを確認する．アプリを再起動し，保存済みの有効な設定と資格情報があれば展示が始まることを確認する．

| 操作 | 確認する結果 |
| --- | --- |
| 画面端へのマウス移動，Dock・メニューバー，アプリ切替 | 展示中の制限が意図どおり働き，解除後に復元される |
| クリック，hover，フォーム，スクロール，drag | 許可したWeb操作ができ，禁止した入力がWebに届かない |
| 右クリック，Control-click，戻る操作，多指ジェスチャ，終了操作 | メニューや別アプリへの経路が展示を中断しない．OSで抑制できない経路は記録する |
| 許可・禁止リンク，リダイレクト，新規ウィンドウ，ダウンロード | URL裁定を通り，許可GETの新規ウィンドウは既存surfaceへ移る．初回読み込みの拒否はSafeHoldへ移る |
| ファイル選択，カメラ・マイク・位置情報，JavaScriptダイアログ，HTTP認証 | 不許可の機能が展示を中断する外部UIを開かない．位置情報はOS別に確認する |

| 操作 | 確認する結果 |
| --- | --- |
| 操作後の無操作，設定したデータ保持方式 | 期限到達後にsurfaceを作り直して開始URLへ戻り，選択したサイトデータの保持方式に従う |
| 通信切断，Webコンテンツプロセス終了，証明書エラー | 再試行対象だけを設定上限まで試し，それ以外や上限到達時はSafeHoldへ移る |
| 初回読み込み中の解除，認証失敗・取消・連続失敗・60秒経過 | 管理画面を認証前に出さず，取消や期限後は元の展示／SafeHoldへ戻る |
| 認証・復帰中のディスプレイ追加，非アクティブ化，スリープ復帰 | SafeHoldへ移り，古い認証成功やWeb結果で展示・管理へ誤復帰しない |
| 復帰中のmouse down/up，終了・再起動 | 旧入力と旧operationを無効化し，資源解放と保存済み設定からの起動を確認できる |

完全なOSロックダウンは初版の対象外．Presentationと端末設定で成立する範囲を実機で記録する．macOS 14やIntel Macでの動作は，その環境で実行するまで未確認として扱う．

## 試験結果の記録

| 項目 | 記録内容 |
| --- | --- |
| 環境 | macOS，機種，CPU，ディスプレイ台数・解像度，マウス・キーボード・トラックパッド |
| 対象 | source revisionまたはsourceの識別情報，ビルド方法，通常／previewモード，設定した制限 |
| 証拠 | 操作した経路，期待結果と実際の結果，スクリーンショット，xcresult |
| 復元 | 管理者解除・終了後のOS設定とウィンドウ，残った資源や入力の有無 |
| 未確認 | 未実施の操作，その理由，次に確認する環境 |

管理者パスワード，入力した個人情報，URLの認証情報を記録へ含めない．テストやビルドの成功だけで実機の合格を宣言しない．

## 実機での確認結果

macOS 27.0.1の専用Mac（1920×1080の1画面）で署名付きSandboxアプリを試験した．カーソル制限・解除，ウィンドウ表示，旧Keychainからの引き継ぎ・管理者パスワード変更・再起動が成功した．通常の全画面固定でも，展示・5秒復帰・Cmd-Tab／Cmd-Q／Cmd-Wの抑制・誤認証・取消・解除・ウィンドウ復元・再起動が成功した．

内蔵画面と外部画面を持つMacでは，通常モードの `testBuiltInDisplayShowsAdministratorShortcut` が1件成功した．外部画面への試験用Webページ表示と，内蔵画面に保存した解除案内の画像を確認した．ショートカットからの解除後，遮蔽は消えた．

カーソル境界は専用Macの画面内に150ptの余白を置いた実表示領域で確認した．複数画面間のカーソル制限，TestFlightからの更新，macOS 14とIntel Macの実行は未確認．
