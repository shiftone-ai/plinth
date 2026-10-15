# Concurrency

同期裁定，非同期Effect，Taskの所有・取消，WebKitのreply，保存処理を変更するときに読む．設計書の5節，17.3〜17.4節を参照する．

[設計書v0.2](../design-docs/macos-kiosk-design-v0.2.md)

- TreeDispatcher，可変Store，Node，UI／WebKit境界はMainActor．CoR裁定は同期・awaitなし．Coreの純粋な遷移関数・Policyはactor非依存の値操作とする．
- Mediatorを個別actorにしない．同期の入力判定をTaskやAsyncStreamへ送らない．
- asyncやTask追加だけをバックグラウンド化とみなさない．targetのisolationとfeature設定を確認する．
- actor境界を越えるものはSendableな値．WKWebView，NSEvent，decisionHandler，Nodeを持ち出さない．診断抑制のためにunchecked Sendable等を付けない．

## 非同期処理と資源の寿命

- 非同期TaskはEffectExecutorがhandleとownerをRegistryで管理する．独立処理のstructured concurrencyは推奨するが，順序依存の復帰工程は並列化しない．
- 置換・停止時は旧operationを無効化してからcancelする．cancel後の結果もownerEpoch／operationID／webGeneration等で再照合する．deinitだけにcleanupを依存しない．
- WebKitのreplyは一度だけ完了する．破棄時もcancelで解決する．通常の旧世代通知と，tokenで照合すべき資源解放完了は区別する．
- 保存取消でI/Oが巻き戻ると仮定しない．revision付きの直列・原子的保存を守る．
