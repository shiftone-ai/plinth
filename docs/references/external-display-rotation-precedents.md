# 外部ディスプレイの縦置き：前例の調査

調査日：2026-10-15．公式資料，既存アプリの前例と，最小アプリでの実験を記録する．

## 調査で確認できたこと

iPhone・iPadから外部ディスプレイへ縦向きの内容を出す前例はある．特にshiftscreen 4Xは，外部画面の回転，内蔵Webブラウザ，マウス操作を開発元が案内しており，Plinthの用途に近い．ただし，これらの資料は現在のiPadOS上でPlinthが動作する証拠ではない．[shiftscreen 4Xの開発元説明](https://apps.apple.com/us/app/shiftscreen-4x/id1573652748)

調査では，`windowExternalDisplayNonInteractive` に対する `requestGeometryUpdate(.iOS(interfaceOrientations:))` の成功を，現行OS・実コード・実行結果まで示す前例は確認できなかった．検索で見つからないことを，APIが利用できない根拠にはしない．

## Appleの公開APIと資料

macOSは，対応する外部ディスプレイの画像を「ディスプレイ」設定から回転する手順を公開している．PlinthのMac版はOSが報告する画面領域を使うため，OSで回転を設定してから展示を開始する方針とする．縦向きでの実機試験は未実施．[AppleのMac向け手順](https://support.apple.com/ja-jp/guide/mac-help/mh11534/mac)，[Macの出力](../design-docs/mac-output.md#縦置き)

iOS／iPadOSには次の公開APIがある．インストール済みiOS 27 SDKの公開ヘッダーも確認した．資料が示す契約と，後述する最小アプリの実行結果を区別する．

| API・資料 | 確認できた契約 | この資料だけでは確定しないこと |
| --- | --- | --- |
| [`requestGeometryUpdate(_:errorHandler:)`](https://developer.apple.com/documentation/uikit/uiwindowscene/requestgeometryupdate(_:errorhandler:)) | iOS 16以降．Sceneの向きの変更を要求できる．拒否時のエラー通知は非同期の場合がある． | 表示専用の外部Sceneで縦向きの要求が認められるか． |
| [`GeometryPreferences.iOS.interfaceOrientations`](https://developer.apple.com/documentation/uikit/uiwindowscene/geometrypreferences/ios/interfaceorientations) | 希望する向きと，対応する向きの共通範囲からOSが選ぶ． | ディスプレイの物理的な設置方向や，映像信号の回転を指定できるという保証． |
| [`UIWindowSceneDelegate.supportedInterfaceOrientations(for:)`](https://developer.apple.com/documentation/uikit/uiwindowscenedelegate/supportedinterfaceorientations(for:)) | iOS 27以降．Sceneごとに対応する向きを返し，そのSceneのInfo.plistの値を置き換える． | 外部画面の回転を強制する機能ではなく，この宣言だけで縦置きになるという保証はない． |
| [`UIView.transform`](https://developer.apple.com/documentation/uikit/uiview/transform) | 公開APIでViewを回転できる．Auto Layoutは変換前の矩形で計算する．非identity変換中の `frame` は未定義になる． | WKWebViewの動画・レイアウトと，別経路で転送するマウス入力がPlinthで正しく動くか． |

[現在の外部表示ガイド](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display)は，表示専用Sceneが全画面を使うことと，`availableModes` から出力モードを選ぶ手順を説明している．外部画面を縦向きへ回転する手順は，今回確認した本文にはなかった．

[WWDC26のUIKit解説](https://developer.apple.com/videos/play/wwdc2026/278/?time=410)では，サイズを変更できる環境でsupported interface orientationは無視され，SceneやViewの実際の寸法に適応するよう説明している．したがって，`.portrait` の宣言を1080×1920の描画領域が得られる証拠とは扱わない．この説明も，表示専用の外部Sceneで向きの変更が拒否されるという仕様ではない．

[2012年の外部表示ガイド](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/WindowAndScreenGuide/UsingExternalDisplay/UsingExternalDisplay.html)にはstatus bar orientationへの依存が記載されている．これはScene導入前の資料である．現行実装にその手順を流用しない．

## 開発元が公開している製品の前例

| 前例 | 資料に明記されていること | 確認できないこと |
| --- | --- | --- |
| [shiftscreen 4X](https://apps.apple.com/us/app/shiftscreen-4x/id1573652748) | iPhone・iPad，有線またはAirPlayの外部画面，画面回転，内蔵Webブラウザ，マウス・トラックパッド対応．対応OS表記はiOS/iPadOS 14以降． | 回転に使うAPI，縦向きWeb viewportの寸法，回転時のカーソル変換，現在のOS別の動作結果． |
| [Touchpixの公式ヘルプ](https://intercom.help/touchpix/es/articles/9468294-enviar-el-contenido-a-tv) | 2025-11-27付．iPhone・iPad，有線HDMIまたはApple TV，縦置きTV用の設定と左右の向きの選択．写真・映像のセッションやスライドショーを扱う． | UIKitの実装方法，任意Webページの再レイアウト，マウス操作．OS別の条件は記載されていない． |
| [Kiosk Proの外部画面ガイド](https://support.kioskgroup.com/article/827-using-the-app-with-an-external-screen) | 2023-10-27更新．Enterprise版では本体を操作画面にし，外部画面へHTML・PDF・映像を独立表示できる． | このガイドには外部出力を90度回転する手順がない．製品全体が回転非対応だとは断定しない． |

shiftscreenの[公式サイト](https://shiftscreen.app/)も，外部画面上のWebブラウザとマウス操作を案内している．App Storeの[公開メタデータ](https://itunes.apple.com/lookup?id=1573652748&country=us)では初回公開が2021-09-18，取得時のバージョンは1.0，その公開日は2021-09-19だった．OSの拡張デスクトップ全体を回転する機能の証拠ではなく，アプリ自身の外部表示機能の前例として扱う．

Touchpixの[英語の旧ヘルプ](https://touchpix.dev.touchpix.com/knowledge-base/evento/espelhar-sessoes-feitas-com-seu-dispositivo-ios-para-uma-tv-slideshow/)にも，外部TV用設定の `Vertical TV` と左右選択がある．これは映像表示の製品仕様であり，Plinthで必要なWeb表示・入力の成立までは示さない．

Kiosk Proの[外部画面設定API](https://support.kioskgroup.com/article/1108-api-connect-configure-external-screen)は，利用可能モード，現在・推奨モード，ピクセル縦横比，overscanの取得・変更を案内している．このAPIの一覧に回転の操作は見当たらない．解像度の変更と出力内容の回転を別々に調べる材料になる．

## コミュニティの実体験と公開コード

### HDMI・AirPlayの出力内容をアプリ内で回転する例

2019-02-20の[Stack Overflowの回答](https://stackoverflow.com/a/54795751)で，回答者snakeoilは，iOSからHDMI・AirPlay経由で縦置きTVへ映像を出す際に，内容を包むViewで回転させたと報告している．Appleの保証ではなく，回答者自身の経験として扱う．実行したOSの版は書かれていない．

回答が示す[RotatingWrapperView.swiftの固定参照](https://github.com/quantcon/UIKit/blob/02653e981f95180f13c272d916b34c8da0b6e298/AutoLayoutRotationDemo/Views/RotatingWrapperView.swift)を確認した．取得元は `quantcon/UIKit`，参照元ブランチは `master`，対象ファイルの最終変更commitは `02653e981f95180f13c272d916b34c8da0b6e298`（2019-02-20）である．[commit情報](https://github.com/quantcon/UIKit/commit/02653e981f95180f13c272d916b34c8da0b6e298)

コードは，内包するUIViewの変換を一旦解除し，90度・270度では幅と高さを交換した矩形を中央へ配置してから，`CGAffineTransform` を適用する．0度・180度も扱う．OSの画面モードやSceneの向きを変更するコードではない．当該ファイルにはWKWebView，マウスイベント，カーソル座標の変換処理がない．したがって，画面内の内容を回す方法の前例として参照し，Plinthへそのまま流用できる実装とは扱わない．

### 本体の回転と外部画面の回転を混同しない

2019-09-20の[別の質問](https://stackoverflow.com/questions/58027841/uiwindow-does-not-rotate-when-device-orientation-change)では，本体側は回転しても，プロジェクターへ出す別Windowは横向きのままだったと質問者が報告している．旧来のUIScreen／UIWindow実装であり，現在のScene APIへの結論には使わない．本体の向きから外部画面の向きを推定しないための事例として残す．

## 最小アプリの実験結果

iPadOS 26.4と27のSimulatorで，UIKit／WebKitだけのアプリとSwiftUIによる描画を比較した．外部Sceneは表示専用で，OSが示す出力領域は720×480だった．`requestGeometryUpdate` の縦向き要求は両方のOSで `UISceneErrorDomain` のエラー101となり，現在のウィンドウ方式では向きを変更できないと通知された．この結果を，すべてのiPadOS・SceneでのAPI利用不可という仕様へ広げない．

UIKitのView変換とSwiftUIの `rotationEffect` はともに90度の出力に成功した．SwiftUIでは0度・90度・180度・270度を試し，90度・270度でWebの `innerWidth`・`innerHeight` が480×720となり，四隅まで描画された．ボタンの座標をDOMで調べて実行するクリックも成功した．このクリックは物理マウスや本体からの操作試験とは区別する．

iPadOS 27では，回転したWebViewの端がぼける現象を外部画面のスクリーンショットで確認した．UIKitの変換でもSwiftUIの回転でも起き，View自身から取得した画像には現れなかった．最小アプリでスクロール端の効果だけを無効にすると，外部画面の画像も鮮明になった．全画面の展示には効果を重ねるネイティブのバーがないため，PlinthでもiOS 26以降のWebKit Adapterで4辺の効果を非表示にする．使用するのは公開APIの [`UIScrollEdgeEffect.isHidden`](https://developer.apple.com/documentation/uikit/uiscrolledgeeffect/ishidden) と [`UIScrollView.topEdgeEffect`](https://developer.apple.com/documentation/uikit/uiscrollview/topedgeeffect) および他3辺のプロパティである．

PlinthにはSwiftUIの標準APIを使う方式を反映した．iPadOS 26.4と27のSimulatorで，本体の操作面からのクリック・ドラッグ・hover・スクロール，全4方向の表示領域，保存後の再起動，解除の取消，90度のインライン動画再生を確認した．外部画面の画像を全4方向で目視し，ぼけも消えている．修正前の画像検査は失敗し，修正後は両OSで成功した．iPadOS 26.6.2の実機の1920×1200モードでも，全4方向の表示・操作・再起動・解除取消が成功した．ユーザーが実パネルの正円と黒帯なしを確認し，通常起動した展示サイトの右90度でも文字の潰れがないことを確認した．トラックパッドの接続・ロック成立・外部カーソルの描画は実機で確認した．物理入力によるWeb操作と縦置きでの動画の全画面再生の確認は残る．[縦横比の調査](mobile-output-aspect-ratio.md)

## Plinthで確かめる条件

以下は調査結果からの検証案であり，対応済みの機能や動作保証ではない．

1. まず公開APIで外部表示専用Sceneの向き変更を試し，拒否エラーだけでなく，実際のSceneの寸法と表示結果を確認する．拡張デスクトップの通常WindowやSidecarの結果と分ける．
2. アプリ内で回す場合は，出力の1920×1080とWeb表示領域の1080×1920を区別する．横長にレイアウト済みのページを回しただけで縦置き対応としない．`innerWidth`，`innerHeight`，レスポンシブ表示，四隅の欠けを確かめる．
3. 回転後の見た目に対して，クリック・スクロール・ドラッグ・hover・カーソル表示が一致するか実機で確かめる．UIViewの通常の入力処理と，別経路で取得してWebへ送る相対マウス入力を同じものと扱わない．
4. 0度・90度・180度・270度について，本体を回しても外部画面の設置方向を保てること，設定保存，再起動，抜き差しを確かめる．
5. 映像のインライン再生・全画面再生でも向きと表示範囲を確かめる．写真・映像専用アプリの成功を，任意Webサイトの成功へ広げない．

調査対象の製品の購入・インストールは行っていない．最小アプリとPlinthのSimulatorでの結果を，展示用構成での実機検証の代わりにはしない．
