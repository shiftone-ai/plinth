# iPad外部出力の縦横比を調べる

描画座標，表示バッファ，実パネル上の寸法を分けて比較する．PNGの円が正円でも，モニター側の表示まで正しいとは断定できない．逆に，PNG上の楕円だけを根拠にアプリの描画不良とは断定できない．これは，Appleが表示モードの画素数と画素の縦横比を別の値として扱い，UIKitの座標にはその補正が含まれると説明していることからの推論である．個別の機器や接続での原因を示すものではない．[UIScreenMode](https://developer.apple.com/documentation/uikit/uiscreenmode)

## 公開APIで分かること

以下の導入バージョンはAppleのAPI資料とiOS SDK 27.0の公開ヘッダーで確認した．iPadOSの表記が分かれる前のものはiOSの導入バージョンを示す．

| 値 | 契約と解釈 | 導入 |
| --- | --- | --- |
| `UIScreenMode.size` | 表示バッファの幅・高さを画素で示す．物理パネルの画素配置そのものとは区別する．[size](https://developer.apple.com/documentation/uikit/uiscreenmode/size) | iOS 3.2 |
| `UIScreenMode.pixelAspectRatio` | 1画素の横幅÷高さ．画像全体の縦横比ではない．[pixelAspectRatio](https://developer.apple.com/documentation/uikit/uiscreenmode/pixelaspectratio) | iOS 3.2 |
| `UIScreen.bounds` | 画面をポイントで表した描画領域．Appleは画面・ウィンドウのboundsが画素の縦横比と描画ハードウェアを自動的に考慮すると説明している．[UIScreenMode](https://developer.apple.com/documentation/uikit/uiscreenmode)，[bounds](https://developer.apple.com/documentation/uikit/uiscreen/bounds) | iOS 2.0 |
| `UIScreen.nativeBounds` | 物理画面の境界を画素で示す．端末が正立した向きを基準とし，端末の回転では変化しない．[nativeBounds](https://developer.apple.com/documentation/uikit/uiscreen/nativebounds) | iOS 8.0 |
| `UIScreen.scale`・`nativeScale` | 前者はポイント座標から画面座標への倍率，後者は物理画面のnative scale．Retinaの倍率だけから画素の縦横比は判断しない．[scale](https://developer.apple.com/documentation/uikit/uiscreen/scale)，[nativeScale](https://developer.apple.com/documentation/uikit/uiscreen/nativescale) | iOS 4.0・8.0 |

通常のUIKit描画にはUIKitが与えるboundsを使う．`currentMode.size`をそのままポイント単位のwindowやviewの寸法に代入したり，`pixelAspectRatio`で一律に再補正したりする根拠はない．画素を直接扱う実装では，UIKitによる補正との重複を調べる．[UIScreenMode](https://developer.apple.com/documentation/uikit/uiscreenmode)

`nativeBounds`の説明は，外部接続のEDIDが正しいこと，モニターの入力タイミング，モニター内の拡大処理まで保証していない．これらを`nativeBounds`だけで同定できるという契約は，今回確認したAPI資料には見当たらない．[nativeBounds](https://developer.apple.com/documentation/uikit/uiscreen/nativebounds)

## モードの初期値と切替

| API | 公開契約 | 導入 |
| --- | --- | --- |
| `availableModes` | 関連付け可能なモード一覧．選択値はこの一覧から取得する．[availableModes](https://developer.apple.com/documentation/uikit/uiscreen/availablemodes)，[currentMode](https://developer.apple.com/documentation/uikit/uiscreen/currentmode) | iOS 3.2 |
| `currentMode` | 現在のモード．iOSでは変更可能，tvOSでは読み取りのみ．資料は初期値を最大解像度のモードと説明する．[currentMode](https://developer.apple.com/documentation/uikit/uiscreen/currentmode) | iOS 3.2 |
| `preferredMode` | 画面の推奨モード．公開ヘッダーは良い結果を得られる可能性が高いと説明するが，パネルの物理解像度との一致は保証していない．[preferredMode](https://developer.apple.com/documentation/uikit/uiscreen/preferredmode) | iOS 4.3 |
| `modeDidChangeNotification` | モードが変化した画面を`object`に持ち，MainActorで通知される．`userInfo`はない．[modeDidChangeNotification](https://developer.apple.com/documentation/uikit/uiscreen/modedidchangenotification) | iOS 3.2 |

外部表示の現行ガイドは初期値を一般的なモードと表現し，古いガイドは推奨モードと表現している．`currentMode`の個別資料とは表現がそろっていないため，実際の`currentMode`と`preferredMode`を別々に採取する．名称だけから「物理解像度が自動選択された」と判断しない．[現行ガイド](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display)，[旧ガイド](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/WindowAndScreenGuide/UsingExternalDisplay/UsingExternalDisplay.html)

Appleは既定以外のモードを使う場合，screenをwindowへ関連付ける前にモードを設定するよう案内している．対象は`windowExternalDisplayNonInteractive`であり，`windowApplication`の画面のモードは変更しないよう明記されている．[外部表示のガイド](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display)

モード設定のsetterから戻った時点で，画面・Scene・Windowの寸法更新と最終描画がすべて完了するという保証は，確認した資料にはない．モード通知に加え，実際のSceneのgeometryとレイアウト後のview寸法を記録する．`effectiveGeometry`はiOS 16以降でKVOに対応する．iOS 26以降では`windowScene(_:didUpdateEffectiveGeometry:)`，それ以前では旧Scene delegateでgeometryの変化を取得できる．[effectiveGeometry](https://developer.apple.com/documentation/uikit/uiwindowscene/effectivegeometry)，[新しいdelegate](https://developer.apple.com/documentation/uikit/uiwindowscenedelegate/windowscene(_:didupdateeffectivegeometry:))，[旧delegate](https://developer.apple.com/documentation/uikit/uiwindowscenedelegate/windowscene(_:didupdate:interfaceorientation:traitcollection:))

## Native Viewでも伸びる条件

`UIView.contentMode`は，bounds変更時にlayerのキャッシュ済み画像をどう扱うかを決める．既定値の`scaleToFill`は必要に応じて画像の縦横比を変えて拡縮する．単にviewのgeometryを変えても通常は再描画されず，キャッシュ済み画像が調整される．[contentMode](https://developer.apple.com/documentation/uikit/uiview/contentmode-swift.property)，[scaleToFill](https://developer.apple.com/documentation/uikit/uiview/contentmode-swift.enum/scaletofill)，[setNeedsDisplay()](https://developer.apple.com/documentation/uikit/uiview/setneedsdisplay())

したがって，`draw(_:)`で円を描く比較用Viewにも，モード変更後の古い画像の引き伸ばしが入り得る．これは公開APIから導ける条件であり，個別の症状の原因確定ではない．比較実験では`.redraw`を指定し，安定後のboundsで描かれたことを確認する．`.redraw`はbounds変更時に`setNeedsDisplay()`を呼ぶが，実際の描画は次の描画サイクルで行われる．[redraw](https://developer.apple.com/documentation/uikit/uiview/contentmode-swift.enum/redraw)，[setNeedsDisplay()](https://developer.apple.com/documentation/uikit/uiview/setneedsdisplay())

## Overscanとの区別

`overscanCompensation`はiOS 5以降で利用でき，既定値は`.scale`である．`.scale`は最終合成済みframebufferを可視範囲へ縮小する．`.insetBounds`はboundsを狭め，`.none`は拡縮せず，クリッピング回避に必要な値を`overscanCompensationInsets`で得る．`.none`とinsetsはiOS 9以降である．これらは画面端の欠落への対処であり，EDIDやパネルの実寸を訂正するAPIではない．[overscanCompensation](https://developer.apple.com/documentation/uikit/uiscreen/overscancompensation-swift.property)，[scale](https://developer.apple.com/documentation/uikit/uiscreen/overscancompensation-swift.enum/scale)，[insetBounds](https://developer.apple.com/documentation/uikit/uiscreen/overscancompensation-swift.enum/insetbounds)，[none](https://developer.apple.com/documentation/uikit/uiscreen/overscancompensation-swift.enum/none)

## 取得画像と実パネルを比較する

以下はAPI契約から導く検証上の注意である．取得画像の画素数は，映像ケーブルを通った信号やモニター内部の拡縮処理を直接計測する値ではない．描画画像，合成済み画面，実パネルの写真・実測を同じ観測点として扱わない．[size](https://developer.apple.com/documentation/uikit/uiscreenmode/size)，[pixelAspectRatio](https://developer.apple.com/documentation/uikit/uiscreenmode/pixelaspectratio)，[UIScreenMode](https://developer.apple.com/documentation/uikit/uiscreenmode)

画素の物理的な横幅と高さが異なれば，100×100画素は物理的な正方形とは限らない．このため，画素寸法だけを証拠に「モニター側の問題」または「描画側の問題」と決めない．また，モニターの入力信号の解像度とパネルの画素数は分けて記録する．[pixelAspectRatio](https://developer.apple.com/documentation/uikit/uiscreenmode/pixelaspectratio)

切り分けは次の順で行う．これは原因の断定ではなく，観測をそろえるための手順である．

1. 回転なしの比較画面で円と正方形を表示する．Native Viewの再描画を有効にし，viewの最終boundsと描画時のboundsを記録する．
2. モード選択前，モード変更通知時，Scene更新時，レイアウト完了時の値を分けて採取する．`currentMode.size`・`pixelAspectRatio`，`UIScreen.bounds`・`nativeBounds`・各scale，Scene・Window・Viewの寸法を残す．
3. 同じ安定状態で描画画像と合成済み画面を取得し，パネル上の円の縦横寸法と比較する．モニターの入力解像度と画面比率設定も記録する．
4. 同じ内容のまま`availableModes`内の別モードを選び，接続後・再起動後にも再現するか確かめる．最後に回転を加え，回転前からの問題と分ける．

## コミュニティで確認できた事例と限界

Apple Developer Forumsには，フルHD対応のモニターでもiPadOSが1280×1024を選び，拡張表示を使えない場合があるという開発者本人の報告がある．AppleのDTS担当者は2024年10月の返信で，報告されたFeedbackの一つが調査中であると回答した．これはモード選択の問題が報告された証拠だが，今回の接続やOSに同じ原因があるという証拠ではない．また，現在も未解決とは断定しない．[iPad external display inconsistency](https://developer.apple.com/forums/thread/767450)

今回確認した一次資料の範囲では，1920×1200と1920×1080の選択差，または1280×720への変更で縦横比が変わる症状に一致し，原因まで確定したAppleの説明は見つからなかった．EDID，OSの出力処理，モニター側の拡縮，アプリ側の古い描画画像の拡縮は，実測で別々に確かめる必要がある．
