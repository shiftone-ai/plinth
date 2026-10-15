# 構造と責務

Node・CoR・Mediator・View・Presenterの実装や責務境界を変更するときに読む．設計書の1〜6節，13節，17.2節を参照する．

[設計書v0.2](../design-docs/macos-kiosk-design-v0.2.md)

iPadの画面構成を変更する場合は [対応方針](../design-docs/ipad-support.md) も読む．展示先と管理モードを分け，Viewの切替だけでRootの認証・停止の裁定を迂回しない．

- アプリ所有のNode，Adapter，Task，native資源はRoot配下で生成・停止・破棄する．SwiftUIの一時的な描画ツリーと所有ツリーを混同しない．
- UIIntent，Request，Factは発生Nodeから親方向へCoRで送る．兄弟の直接呼び出しやグローバルPub/Subで迂回しない．
- Root／Exhibition／AdministrationのMediatorが状態機械として裁定する．既知だが不許可のイベントはHandled(rejected)で止める．Bubbleは担当外のイベントだけ．
- 裁定で選んだEffectだけをAdapterが実行する．AdapterにURL判断，認証判断，再試行方針を置かない．

## 表示と入力

- Passive Viewは不変Propsを描画し，型付きUIIntentを上げるだけ．Presenterは状態からPropsへの純粋な投影だけを行う．
- ViewへMediatorや可変Core Storeを渡さない．ObservationはNode別RenderPropsStoreの通知に使い，別のViewModelへ業務状態を複製しない．
- Bindingのsetは意図送出だけ．draftの更新・検証はMediatorが行う．onChange，task，onAppear，updateNSViewから保存・Web読み込み・タイマー・認証・Presentation変更を起動しない．
