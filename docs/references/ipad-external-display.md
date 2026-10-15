# iPadの外部ディスプレイと端末制限

iPadの内蔵画面と外部ディスプレイの両方を展示先にする．内蔵画面では展示と管理を切り替える．外部画面はその画面の比率に合う独立した展示とし，ミラーリングを代案にしない．外部画面の展示にはマウス操作が必要で，ポインタをiPad側の画面へ移動させない方法を検討する．

運用条件として，外部画面での展示にはアクセスガイドを使わない．内蔵画面での展示にまでこの条件を広げない．Single App Mode／Autonomous Single App Modeが外部表示に適合するかは未確認．公開APIの仕様と実装時の観測値を分けて記録する．MDM設定は未実施である．

## Appleの仕様で確認できたこと

外部画面への専用表示と，対話可能なアプリウィンドウの移動は別の仕組みである．[UIKitの外部表示資料](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display) は，次のSceneを区別している．

| Sceneのrole | 表示と入力 | 設計上の扱い |
| --- | --- | --- |
| `windowExternalDisplayNonInteractive` | 接続した外部画面いっぱいに表示する．外部画面上の対話は受け付けない | 本体から外部Webへ操作を送る方式として採用済み |
| `windowApplication` | 対応するiPadでは外部画面に対話可能なウィンドウを表示する．複数のウィンドウが並び，全画面になるとは限らない | 対応端末でWebへネイティブ入力を渡す方式 |

通常のアプリウィンドウを外部画面へ移す操作には，対応するiPadと接続機器が必要である．[iPadユーザーガイド](https://support.apple.com/guide/ipad/move-an-app-to-an-external-display-ipad8baf19a7/ipados) は，ポインタによる移動やウィンドウメニューからの移動を説明している．これを展示専用の画面を占有するAPIとは扱わない．

### 現在のSDKで必要な実装

iOS 27以降，非対話の外部Sceneは `UISceneAccessory.externalNonInteractive(sceneConfiguration:)` をViewControllerへ登録した場合に提供される．登録の有効状態，ViewControllerの表示，外部画面の接続がSceneの接続・切断に関わる．以前のOSでは接続時のroleを判定して提供する経路だった．新規実装では実際の下限OSに合う経路を選ぶ．[UIKitの外部表示資料](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display)

インストール済みiPhoneOS27.0 SDKの `UIKit.framework/Headers/UISceneAccessory.h` と `UIViewController.h` に，登録・解除APIとiOS 27のavailabilityを確認した．SDKの配置は `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk`．実装後のビルドと実機・Simulatorの結果は [開発と検証](../development.md) を参照する．

Sceneの寿命はアプリ全体の寿命と分けて管理する．[TN3187](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle) はSceneによるライフサイクル管理と，iOS 26の次のメジャーリリースから最新SDKでのScene対応が必須になることを説明している．

### 解像度と画面倍率

UIKitの公開APIでは，Sceneの `screen` から次を取得できる．

| 情報 | API | 判断できること |
| --- | --- | --- |
| 推奨・現在・対応する出力モード | `preferredMode`・`currentMode`・`availableModes` | OSが提供する出力モードと選択候補 |
| ピクセル単位の画面サイズ | `nativeBounds` | OSがアプリへ報告するサイズ |
| 描画倍率 | `scale`・`nativeScale` | ポイントとピクセルの対応．パネルの物理解像度とは別に扱う |
| モードのサイズとピクセルの縦横比 | `UIScreenMode.size`・`pixelAspectRatio` | 出力バッファのサイズと1ピクセルの形 |

Appleは `nativeBounds` を物理画面のピクセル寸法と説明している．`scale` はポイントからピクセルへの変換倍率で，Retinaの例では2または3となる．[UIScreen](https://developer.apple.com/documentation/uikit/uiscreen)，[nativeBounds](https://developer.apple.com/documentation/uikit/uiscreen/nativebounds)，[scale](https://developer.apple.com/documentation/uikit/uiscreen/scale)，[UIScreenMode](https://developer.apple.com/documentation/uikit/uiscreenmode)

ただし，iPadOS 26.6.2の実機と試験に使った外部ディスプレイでは，UIKitの `preferredMode` と `nativeBounds` が1920×1200，開発用CoreDeviceツールの `nativeSize` が1920×1080だった．対応モードには両方の解像度が含まれていた．1080pへの切替時に黒帯が消えたが，その後の図形確認では円が歪んでいた．再描画を有効にした最小UIKitアプリでは，1920×1200で正円かつ黒帯なしになることを実パネルで確認した．黒帯の有無だけでモードの縦横比が適切とは判断しない．

この接続では，UIKitの値だけからパネルの物理解像度を特定できていない．EDIDそのものは取得・解析しておらず，ディスプレイ，接続機器，OSの解釈のどこに原因があるかは未確定である．CoreDeviceの値を配布アプリで使える公開APIとは扱わない．初期値はOSの選択を維持し，必要に応じて対応モードから選択・保存する方針とした．解像度を製品名や一律の1080pで決めない．

モード切替時には比較用Viewの古い描画画像の拡縮も除外する．取得画像と実パネルは異なる観測点として扱う．公開APIの契約と確認手順は [縦横比の調査](mobile-output-aspect-ratio.md) を参照する．

### ポインタを展示画面へ固定する候補

UIKitには `UIViewController.prefersPointerLocked` がある．ただし [UIPointerLockStateの仕様](https://developer.apple.com/documentation/uikit/uipointerlockstate) は，システムのポインタを非表示にし，全画面のアプリへロックする機能として説明している．通常の見えるポインタを外部画面の端で止める設定とは扱わない．

[prefersPointerLockedの仕様](https://developer.apple.com/documentation/uikit/uiviewcontroller/preferspointerlocked) による成立条件と確認方法は，次のとおり．

- Sceneが全画面を占め，Split View／Slide Overを使わず，他のSlide Overアプリも表示されていないこと．
- Sceneが `foregroundActive` であること．
- 要求が必ず認められるわけではないため，`pointerLockState.isLocked` と変更通知で結果を確認すること．条件を失うとロックは解除される．

[Appleの入力解説](https://developer.apple.com/videos/play/wwdc2020/10094/) は，ロック非対応のSceneでは `pointerLockState` が `nil` になることも説明している．外部画面のSceneで取得できるか，iPad画面への移動を止められるかは実機確認が必要．

iPadOS 26.6.2の実機では，本体Sceneが全画面と同じ寸法でも，「ウインドウ表示アプリ」の設定では `prefersPointerLocked` の要求が成立しなかった．「設定」の「マルチタスクとジェスチャ」で「フルスクリーンアプリ」へ変更すると，最小アプリで本体Sceneの `pointerLockState.isLocked` が真になった．この設定経路は [Appleの手順](https://support.apple.com/en-us/123635) とも一致する．OS設定を直接読み取る公開APIは確認できていないため，アプリではロックの取得結果を検出して案内する．

Plinthでもトラックパッドを接続したまま3回の再起動が成功し，外部のカーソル描画を取得画像で確認した．ロック拒否の案内から設定を変えて展示へ戻る試験も成功した．最小アプリで受け取った物理入力と，修正後のPlinthでのWeb操作・画面の端での制限は区別する．

#### 通常のWebクリックとの違い

通常のUIKit入力では，ポインタ位置に応じたhoverやクリックを既存のView・GestureRecognizerで扱う．[Appleの入力解説](https://developer.apple.com/videos/play/wwdc2020/10094/)

一方，[マウスを使うゲームの解説](https://developer.apple.com/videos/play/wwdc2020/10617/) は，ロック中に `GCMouse` から相対移動量を受け取り，アプリがポインタの位置・描画・加速度・端での動作を決める方式を説明している．`GCMouse` からシステムポインタの現在座標は取得できない．

したがって，ロック要求を通常の `WKWebView` に追加するだけで，見えるカーソルによるリンク・フォーム・スクロール操作を維持できるとは確認できない．ロック中のUIKitの位置入力やWebのhit testingへの受け渡しは，この資料だけでは確定しない．これは実装可否についての未確認事項であり，不可能という断定ではない．

#### WebのPointer Lock API

Webの `requestPointerLock()` はUIKitの設定とは別のAPIである．WebKitにはiOS向け実装が進んでいる．[マウス接続による制限の変更](https://bugs.webkit.org/show_bug.cgi?id=296923) はFIXEDとして記録され，公開ソースにも `GCMouse` を使う相対入力処理がある．[WKMouseInteraction.mm](https://github.com/WebKit/WebKit/blob/9325bd2ef733b14e75e8eea95d33e277f1a172ab/Source/WebKit/UIProcess/ios/WKMouseInteraction.mm)

ただし，同じcommitの [UnifiedWebPreferences.yaml](https://github.com/WebKit/WebKit/blob/9325bd2ef733b14e75e8eea95d33e277f1a172ab/Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml) は `PointerLockEnabled` をinternalとし，`PLATFORM(IOS_FAMILY)` の既定値を `false` にしている．ソース上の実装やテストの追加を，配布済みiPadOSの標準 `WKWebView` で有効な証拠としない．対象OSでの公開APIの利用可否と実際の成功は未確認であり，private APIや内部フラグを前提にしない．

### 端末を1アプリに制限する条件

| 方式 | 確認できた条件 | 外部表示との併用 |
| --- | --- | --- |
| Single App Mode | 監視対象の端末を管理ツールで1アプリに固定する．再起動後も対象アプリが開く | 参照資料は外部Sceneの動作を保証していない |
| Autonomous Single App Mode | 監視対象とMDMによるアプリの許可が必要．アプリが非同期APIで開始・終了を要求し，完了結果を確認する | 参照資料は外部Sceneの動作を保証していない |

Single App Modeの条件は [Apple Configuratorの資料](https://support.apple.com/guide/apple-configurator-mac/set-single-app-mode-cadbf9c172/mac)，Autonomous Single App Modeの条件と呼出し契約は [requestGuidedAccessSessionのAPI資料](https://developer.apple.com/documentation/uikit/uiaccessibility/requestguidedaccesssession(enabled:completionhandler:)) で確認した．[WWDC22の説明](https://developer.apple.com/videos/play/wwdc2022/10152/) は後者がアクセスガイドの基盤を使うと説明している．別の名前の制限方式であることだけを根拠に，外部表示の問題が解消すると判断しない．

iPadの許可設定は [Restrictionsの `autonomousSingleAppModePermittedAppIDs`](https://developer.apple.com/documentation/devicemanagement/restrictions) に記載されている．同名に近い [AutonomousSingleAppMode payload](https://developer.apple.com/documentation/devicemanagement/autonomoussingleappmode) の `com.apple.asam` はmacOS用であり，iPad用の設定として流用しない．

## プロジェクトで確定した条件と未決定の条件

- 内蔵画面でも展示し，展示と管理を切り替える．外部画面の接続をすべての展示の必須条件にしない．
- 外部展示は外部画面の比率に合わせる．本体の画面を複製して黒帯が出るミラーリングでは，展示の目的を満たさない．これは製品要件として確定した条件である．
- 外部画面ではマウスによる直接操作が必要．外部展示ではアクセスガイドを使わない．いずれも製品要件である．
- 表示専用SceneではUIKitのPointer LockとGameControllerの相対入力を使い，本体から外部Webへ操作を送る実装を採用した．実機でロック成立と外部のカーソル描画を確認した．物理入力によるWeb操作と，画面の端で本体へ移らないことの確認は残る．
- 設計案として，表示先・入力先・端末制限を別の契約にする．現在のMac向け「画面数が1」の条件はそのまま共用せず，OS別のAdapterがSceneの状態をFactとしてRootへ送る．Rootが展示の開始・停止を裁定する．

## 実機で残る確認

Appleの上記資料では，アクセスガイドと外部表示の互換性，Single App Mode／Autonomous Single App Mode中の外部Sceneや対話ウィンドウの維持を確認できなかった．制限方式を採用する前に，対象iPad・iPadOS・接続機器・管理設定をそろえ，次を確認する．

1. 内蔵画面で展示と管理を切り替えられ，外部画面では本体の比率に依存しない表示領域で展示できること．
2. 外部Sceneの `pointerLockState`，ロック要求の結果，ポインタの画面間移動を確認すること．
3. ロック中もWebのリンク・フォーム・スクロールが操作できること．相対入力と通常のUIKit入力を混同せず検証する．
4. OS制限の開始・解除，接続解除・再接続，復帰・再起動後の表示と資源解放．
5. 管理者画面を外部に誤表示せず，必要な解除操作を実行できること．

Simulator，SDKの静的確認，fake Portのテストでは，この実機互換性を証明しない．対応方針への反映先は [iPad対応の方針](../design-docs/ipad-support.md)．
