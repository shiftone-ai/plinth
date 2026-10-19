# Plinthの設計

機能と責務境界は [設計書v0.2](docs/design-docs/macos-kiosk-design-v0.2.md) を参照する．対象の節だけを読む．

iPad版の本体・外部への展示，展示Viewと管理Viewの切替，マウス入力とOS制限の条件は [iPad対応の方針](docs/design-docs/ipad-support.md) を参照する．現在の実装と追加予定を区別する．

設定集の登録，端末への適用，iCloud同期，暗号化ファイルの責務は [設定集](docs/design-docs/settings-catalog.md) を参照する．

| 判断すること | 設計書の節 |
| --- | --- |
| 目的・初版の範囲・所有ツリー・役割・イベント配送 | 0〜6節 |
| RootとExhibitionの状態遷移・無操作復帰・障害復帰 | 7〜8節 |
| URL・入力・Presentation・管理者解除・設定保存 | 9〜12節 |
| モジュール境界・診断・不変条件・実装段階 | 13〜16節 |
| SwiftUI・Concurrency・Swift Testingの適用条件 | 17〜18節 |

## モジュールと実装

| モジュール | 責務 |
| --- | --- |
| [KioskCore](Sources/KioskCore) | イベント，値モデル，Policy，状態機械，Reply・Effect・Controlの契約 |
| [KioskLocalization](Sources/KioskLocalization) | 管理画面の翻訳，OSの言語と画面内の言語選択，選択の保存 |
| [KioskPresentation](Sources/KioskPresentation) | 不変Propsと純粋なPresenter |
| [KioskRuntime](Sources/KioskRuntime) | Root所有ツリー，同期CoR配送，Effect・Task・reply管理，共通WebKit・Keychain・保存Adapter |
| [KioskUI](Sources/KioskUI) | Mac・iOS共通のPassive SwiftUI View |
| [KioskMacApp](Sources/KioskMacApp) | AppKitの起動・入力・Presentationと共通Runtimeの組み立て |
| [KioskMobileApp](Sources/KioskMobileApp) | UIKitのScene所有・入力・Presentationと共通Runtimeの組み立て |
| [Plinth](Sources/Plinth) | アプリの起動とCLIオプション |
| [PlinthMobile](Sources/PlinthMobile) | iPhone・iPad用UIApplicationの起動 |

OS別のApplicationがRuntimeとNative資源を所有し，[NativeEffectPort](Sources/KioskRuntime/Effects/NativeEffectPort.swift) が裁定済みEffectを実行する．MobileApplicationは正常に起動したSessionを最後のSceneの切断後も保持し，管理者認証と進行中の解除操作を終了する．iCloud同期は画面がない間も続け，次のScene接続では同じSessionを使う．初期読み込みに失敗したSessionは最後のSceneの切断時に終了し，次の接続で作り直す．展示用Sceneと管理用Sceneの役割は固定し，外部に管理画面を描画しない．targetとisolationは [Package.swift](Package.swift)，アプリのwrapperは [project生成手順](scripts/create-xcode-project.py) で管理する．

Runtimeの入口は [RootRuntime](Sources/KioskRuntime/Runtime/RootRuntime.swift)．ViewのBindingは項目別の意図を送るだけで，draftの更新・検証と送信時の管理者パスワード選択はAdministration Mediatorが行う．外部Sceneの作成は接続またはエラーの完了を待ち，取消時はoperationを無効化してから待機を解放する．実装の条件は [実装規約](docs/rules/index.md)，検証の範囲は [開発と検証](docs/development.md) を参照する．
