# 実機への配布

iPad・iPhoneへの配布にはTestFlightを使う．接続したiPhoneへの開発用インストールは，展示前の実機試験に使う．アプリはiOS／iPadOS 18.4以降を対象にする．新しいOSでは新しい画面APIを使い，18.4〜26では従来の公開APIで接続・画面変更を受け取る．ファイル選択を拒否する公開WebKit APIが18.4以降であるため，17は対象に含めない．

## ビルドの元

プロジェクトのルートで次を実行する．生成projectは既存のxcuserdataを保持する．Apple ID・team ID・秘密鍵はprojectや文書へ保存しない．

```sh
python3 scripts/create-xcode-project.py
open -a Xcode Plinth.xcodeproj
```

Scheme `PlinthMobile` を使用する．接続済み端末への署名はXcodeのApple AccountsとAutomatic Signingを使う．試験用のprofileとKeychain serviceはDebugだけで分離し，Releaseは通常の保存先だけを使う．アイコンは `Resources/Assets.xcassets` に置く．

iOS版はPrivacy Manifest `Resources/PrivacyInfo.xcprivacy` で，理由の申告が必要なAPIの利用を申告する．今は無操作の経過時間を測る `systemUptime` だけを申告している．申告が必要な別のAPIを使うときは，その分類と理由を足す．[Appleの資料](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

## TestFlightと展示開始

1. Developer ProgramのチームとApp Store Connectへのアクセスを確認する．TestFlightにはDeveloper Programの配布権限が必要．[AppleのProgram説明](https://developer.apple.com/help/account/membership/programs-overview/)
2. 署名済みRelease archiveを作る．App Store Connect配布用に書き出したIPAを `just check-artifact <IPA>` で調べてから，アップロードする．ビルドの処理完了と，必要なベータ審査の状態を確認する．[TestFlightの概要](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
3. 展示端末の管理者がTestFlightからiPadへインストールし，機種・OS・外部ディスプレイ・接続機器・マウスを記録する．
4. 本体で設定・認証し，外部ディスプレイを選んで開始する．外部表示専用Sceneでは本体の操作面を使う．対話可能なウィンドウを使う場合は外部へ移す．リンク・フォーム・スクロール・動画を展示に使う構成で確認する．
5. 無操作復帰，禁止先，切断，再起動，長時間運用とカーソルの画面間移動を検証する．Simulatorだけで展示開始の合格としない．

表示専用の外部画面では，設定の「解像度」から対応するモードを選択・保存できる．初期値の「自動」はOSの選択を使う．黒帯がある場合は，ディスプレイの仕様に合う解像度へ変更して確認する．

外部展示でマウスを使うiPadOS 26以降の端末は，「設定」の「マルチタスクとジェスチャ」で「フルスクリーンアプリ」を選ぶ．[Appleの設定手順](https://support.apple.com/en-us/123635)．マウスを固定できない場合は本体に設定案内が出る．設定を変えてPlinthに戻ると再確認し，マウス固定に成功したら展示を再開する．別の全画面操作や，バックグラウンドのアプリの終了は不要．案内を表示している間，外部画面は黒くなる．

展示中に別のアプリへ切り替えると一時停止し，Plinthへ戻ると展示とマウス固定をやり直す．OSのアプリ切替自体を防ぐ機能ではない．管理者解除や外部画面の切断後は，自動再開しない．

直接インストールの署名期限と端末登録は，生成したprovisioning profileを見て確認する．TestFlight用の配布署名とは区別する．外部画面と端末制限の条件は [iPad対応](design-docs/ipad-support.md) にある．

管理画面の多言語表示（日本語・英語・韓国語・中国語の簡体字／繁体字）は実装済み．OSの言語と画面内の切り替えについては [管理画面の言語](development.md#管理画面の言語) を参照する．

外部ブラウザから設定するWebサーバー機能は [Issue #2](https://github.com/shiftone-ai/plinth/issues/2) で追跡する．

Touch ID・Face IDによる解除は [Issue #3](https://github.com/shiftone-ai/plinth/issues/3) で追跡する．

## MacのDeveloper ID配布

App Storeを通さずにMacへ渡す版は，Developer IDで署名し，公証チケットをstapleしたzipにする．Bundle IDは `ai.shiftone.plinth` で，`scripts/build-app.sh` の版と同じくSandboxを使わない．設定は `~/Library/Application Support/Plinth/`，パスコードの検証値はログインKeychainのservice `ai.shiftone.plinth` に置く．TestFlight版（`ai.shiftone.plinth.mobile`）とは保存先を共有しない．

XcodeのApple Accountsで配布チームにサインインしてから，プロジェクトのルートで実行する．team IDは環境変数で渡す．build番号は版ごとに増やす．

```sh
PLINTH_TEAM_ID=<team ID> zsh scripts/build-notarized-app.sh 0.1.0 1
```

1. 作業ツリーの `Plinth.xcodeproj` を書き換えないよう，sourceを `.build/developer-id/<version>-<build>/source/` へ複製し，各ファイルのSHA-256を `source.sha256` に記録する．
2. `create-xcode-project.py --developer-id` で，Automatic SigningとHardened Runtimeを有効にしたprojectを生成し，archiveする．Appleへ送る前に，archiveを `scripts/check-artifact.py` で調べる．
3. Developer IDでexportし，Appleの公証サービスへ送る．署名には，チームに登録済みのクラウド管理のDeveloper ID Application証明書を使う．
4. 公証が終わるまで `xcodebuild -exportNotarizedApp` を繰り返し，staple済みのアプリを書き出す．
5. 署名・staple・Gatekeeperの判定を確かめ，`Plinth-<version>-<build>.zip` を作って，同じ検査をかける．

配布先のMacではzipを展開し，`Plinth.app` を `/Applications` へ移してから起動する．

`build-app.sh` の版で保存したパスコードを，署名の異なるこの版が確認画面なしで読めるかは未確認．
