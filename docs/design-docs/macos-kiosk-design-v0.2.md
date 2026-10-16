# macOS Kiosk Browser — 設計書 v0.2

作成日：2026-10-14  
改訂日：2026-10-14  
ステータス：実装前の設計．macOS実機での動作確認は未実施．

v0.2では，指定されたSwiftUI Pro／Swift Concurrency Pro／Swift Testing ProのSkill本文と関連参照資料を確認し，実装・レビュー規約を追加した．Root所有ツリー，Passive View，CoR，状態機械としてのMediatorという設計原則と，機能スコープは維持する．この改訂ではSkillのインストール，リポジトリへの変更，アプリの実装・ビルド・テストは行っていない．

## 0. 目的と対象範囲

任意のWebページを，来場者が操作しても展示状態を保てるMac用キオスクブラウザを作る．広告配信CMSではなく，単一のWebコンテンツを公開するための展示ランタイムとする．

初版に含めるもの：管理者による開始URL指定，閲覧先のallowlist／denylist，無操作復帰，移動・クリック中心の入力制限，Dock／メニューバーの抑制，管理者解除，通信失敗とWebコンテンツプロセス終了からの復帰．

初版の制約：主コンテンツは1画面．端末の完全なロックダウン，すべての通信先の遮断，クラウド管理，複数コンテンツのスケジュール配信，任意サイトの完全互換は対象外．単一の接続ディスプレイを受け入れ対象とし，複数画面では開始を拒否する．追加画面の遮蔽は拡張項目に分離する．

「任意のURL」は管理者がURLを設定できるという意味とし，来場者向けのアドレスバーやタブは設けない．HTTPSを標準とし，HTTP利用には明示設定と配布時のATS方針の確認が必要．自己署名証明書等のTLSエラーを無条件で無視する機能は設けない．

## 1. アーキテクチャ上の決定

### 1.1 原則

- アプリが所有するすべてのランタイム構成要素はRootから始まる所有ツリーに置く．SwiftUIの一時的なView値，OS自身，表示先WebサイトのDOMは，この所有ツリーそのものとは区別する．
- UIコンポーネントはComponentNodeとして構成する．ViewはPassive Viewであり，表示用の値を描画し，型付きの操作意図を通知するだけとする．
- Presenterは状態スナップショットからViewPropsへの純粋な投影のみを担当する．
- 入力・ライフサイクル・WebKit通知・副作用の結果は，発生Nodeから親方向にChain of Responsibilityで伝播する．
- 業務判断，許可判定，状態遷移，副作用の選択は，そのイベントの所有者であるMediatorだけが行う．
- MediatorはSwiftのenumと明示的な遷移関数で表現する階層的ステートマシンとする．初版では外部の状態管理ライブラリを必須にしない．
- 副作用はEffectとして記述し，Platform Adapterが実行する．Adapterは業務上の判断や自動再試行をしない．
- 設定反映やウィンドウ操作を，Viewの再描画やライフサイクルから発火させない．

「すべてをRootが所有する」と「すべてをRootMediatorが判断する」は別である．RootMediator，ExhibitionMediator，AdministrationMediatorの3つに責務を分ける．表示部品ごとにMediatorを量産しない．

### 1.2 所有・通信・依存の区別

所有ツリーは単一のRootを持つ．イベントの上向き通信は親EventSinkだけに制限する．兄弟Nodeの参照・直接呼び出し・グローバルなPub/Subは用いない．

下向きに渡せるものは，確定したViewProps，子Mediatorへの型付きControlEvent，裁定済みのEffectの3種類だけとする．親から子へのControlEventも，子Nodeを入口として通常のイベント裁定を通す．Viewやサービスの任意メソッドを親が呼び回す構造にはしない．

EffectPortはRootで配線する能力限定のインターフェースであり，Service Locatorではない．Portの参照は所有を移さない．

## 2. コンポーネント階層

```text
RootNode
├── RootRuntime
│   ├── TreeDispatcher / ScopedStateStore（MainActor）
│   ├── RootMediator
│   ├── RenderPropsStore（Node別の表示用投影）
│   └── EffectExecutor
│       └── EffectTaskRegistry
├── PlatformNode
│   ├── ApplicationLifecycleAdapter
│   ├── PresentationAdapter
│   ├── DisplayAdapter
│   └── NativeInputAdapter
├── ExhibitionNode
│   ├── ExhibitionMediator
│   ├── WebSurfaceNode
│   │   ├── WebSurfacePresenter
│   │   ├── PassiveWebHost
│   │   └── WebKitAdapter
│   ├── StatusOverlayNode
│   │   ├── StatusPresenter
│   │   └── StatusView
│   └── IdleClockAdapter
├── AdministrationNode
│   ├── AdministrationMediator
│   ├── UnlockNode
│   │   ├── UnlockPresenter
│   │   └── UnlockView
│   ├── SettingsNode
│   │   ├── SettingsPresenter
│   │   ├── SettingsView
│   │   ├── NavigationRulesNode
│   │   ├── InteractionPolicyNode
│   │   └── ResetPolicyNode
│   └── CredentialAdapter
└── PersistenceNode
    ├── ProfileRepositoryAdapter
    └── DiagnosticLogAdapter
```

表示を持たないAdapterやRepositoryに，形だけのViewを設けない．これらもRoot配下のNodeが所有し，開始・停止・破棄を管理する．

RootNodeは子の寿命，購読，タイマー，WebKit delegate，処理中のTaskを管理する．SwiftUIの再描画によってMediatorやWebViewの寿命を変えない．子から親への参照は循環保持を作らないEventSinkとする．

## 3. 各役割の契約

| 役割 | 許可する責務 | 禁止する責務 |
|---|---|---|
| Passive View | ViewPropsの描画，型付きUIIntentの送出，表示上のフォーカス・ホバー等 | URL判定，入力制限の判断，Timer，保存，認証，Web読み込み |
| Presenter | Snapshotを表示文字列・有効状態・表示形式へ変換 | API呼び出し，状態遷移，イベント購読を契機とする副作用 |
| Component Adapter | View・Presenter・親Sinkの配線 | View変更を監視したload・保存・再試行 |
| Mediator | guard，遷移，許可・拒否，Effectの選択 | AppKit／WebKit／永続ストアの直接操作 |
| Policy Model | URLルール評価，入力分類，設定整合性などの純粋計算 | 状態の変更，イベントの直接送出，I/O |
| Platform Adapter | OS通知の正規化，決定済みEffectの実行，結果の通知 | 独自の業務判断，独自リトライ，他Nodeの状態変更 |
| RootRuntime | 直列配送，状態の確定，投影とEffect実行の順序管理 | 閲覧先や認証の独自判断 |

### 3.1 ViewPropsとEffectを混ぜない

Web表示用Propsの例は，surfaceの識別子，表示領域，表示・非表示，オーバーレイの状態である．URLを「値が変わったら読み込むProps」にしない．URL表示文字列をPropsに入れることと，読み込みを実行することは別である．

WebKitAdapterがWKWebViewを所有する．PassiveWebHostは既存surfaceをホストするだけで，load，reload，goBack，データ消去を実行しない．NSViewRepresentableのupdateNSViewやSwiftUIのonChangeを動作の起点にしない．

入力欄の編集中の値もAdministrationMediatorが所有する．BindingのsetはUIIntentを送信するだけとし，別のローカルdraftをViewに持たせない．@Stateはアニメーション等の表示局所状態に限定する．

### 3.2 概念上の関数形

```text
mediate(state, event, readonlyContext)
  -> Bubble
   | Handled(nextState, reply?, effects, parentEvents, childControlEvents)

present(snapshot)
  -> ViewProps

execute(effect)
  -> platform result event
```

既知のイベントを現在の状態で受け付けられない場合は，Handled(rejected)で止める．Bubbleは「自分の所有イベントではない」場合だけに使う．未知イベントを汎用の成功として握り潰さない．

## 4. イベントとChain of Responsibility

### 4.1 イベントの種類

Requestは裁定を求めるもの，Factは外部から観測された結果，UIIntentは利用者の意図とする．命名例はNavigationRequested，NavigationCommitted，StartExhibitionRequested．

上向きの例：

```text
リンクを開こうとする
  WebKitAdapter
    → WebSurfaceNode
      → ExhibitionNode / ExhibitionMediator が裁定
        → Handled(allow または cancel)
```

```text
設定画面の「展示開始」
  SettingsView
    → SettingsNode
      → AdministrationNode はRoot所有イベントとしてBubble
        → RootNode / RootMediator が裁定
```

```text
AppKitの入力イベント
  NativeInputAdapter
    → PlatformNode
      → RootNode / RootMediator が入力スコープと許可を裁定
```

RootMediatorは入力の最終裁定を一元的に所有する．展示用の入力プロファイル，アプリモード，Exhibitionの読み取り専用inputAvailabilityを組み合わせる．展示への受理入力は，裁定後にExhibitionMediatorへVisitorActivityRecordedというControlEventを渡し，無操作期限を更新させる．

### 4.2 スコープと単一所有者

| イベント領域 | 所有Mediator |
|---|---|
| 展示開始・終了，アプリ終了，画面構成，入力の通過判定，解除の要求 | Root |
| ページ遷移，ページ読み込み，無操作期限，復帰，Webプロセス異常 | Exhibition |
| 設定draft，入力検証，認証画面，認証処理中・失敗表示 | Administration |

認証結果そのものはAdministrationが解釈し，検証済みのAuthenticationVerifiedを親へ通知する．制限を解除する最終権限はRootだけが持つ．Webページ由来のメッセージには，Rootの管理操作イベントを生成できる経路を与えない．

1つのイベントの状態遷移所有者は1つとする．子が処理した後で親にも判断が必要になった場合，別の意味を持つparentEventを生成し，causationIDで元イベントとの関係を保持する．

### 4.3 イベントEnvelope

```text
EventEnvelope
  eventID
  sourceNodeID
  sourceEpoch
  monotonicTimestamp
  causationID?
  requestID?
  webGeneration?
  operationID?
  profileRevision?
  payload: typed event
```

すべてのイベントにすべての識別子を必須にせず，対応する処理に必要なものを持たせる．Native objectやdecisionHandlerはEnvelopeに格納しない．WebKitのrequest等の実体が必要な場合は，Adapter内の短命なregistryに保管し，識別子で対応付ける．

Rootまで未処理で到達した通知は診断対象とする．権限・ナビゲーション等の未処理Requestは拒否する．古いWebViewの通知は破棄するが，返答待ちRequestは黙って捨てずcancelで解決する．

## 5. 実行モデル：同期裁定と非同期副作用の分離

本番ランタイムでは，すべてのMediatorの遷移を，共通のMainActor上で，awaitを含まない同期処理として実行する．TreeDispatcherと可変ScopedStateStoreをMainActorに隔離する．Coreの遷移関数・Policy・値型にはMainActor依存を持たせず，注入した値だけから結果を返す．「MainActorで実行する」と「Coreのすべての型をMainActor隔離する」は区別する．Mediatorごとに独立actorを作って裁定を非同期化しない．詳細は17.3節．

ローカルイベントモニターはイベントまたはnilをその場で返すAPIであり，非同期の判断を待ってから入力を止める構造にはできない．[A1]

処理単位は以下とする．

```text
Ingress
 → sourceから親へのCoR
 → 所有Mediatorのguardと状態遷移
 → 派生した親イベント／子ControlEventを処理
 → TreeStateの確定
 → 確定したreplyをOS／WebKitへ返す
 → Presenterの差分をPassive Viewへ反映
 → Effectを実行
 → 結果を発生Nodeから再びCoRへ
```

stateが確定する前にEffectを実行しない．reply実行時やPlatform Effectから再入したイベントは，確定済みsnapshotに対して処理する．通常通知はqueueに直列化し，同期Requestを処理できない破棄・終了境界では拒否側へ倒す．

長時間処理やストアアクセスはEffect側へ出す．WebKit／AppKit操作自体は要求される実行コンテキストで実行する．

NativeInputの通過判定は毎イベント行うが，マウス移動ごとに画面を再描画したりログを永続化したりしない．Presenterの出力に変化がない場合はViewの更新を省略する．

### 5.1 decisionHandlerの寿命

NavigationRequestのreplyはWebKitAdapterのDecisionRegistryが所有する．決定を反映するのは1回だけとし，registryから取り出してからcallbackを実行する．WebView破棄時・終了時に残っているRequestはcancelする．二重完了・未完了・古い世代へのallowをテストする．

## 6. 状態の所有

状態の保存先はRootRuntime配下のScopedStateStoreとする．状態の意味と変更権限は各Mediatorに属する．RootMediatorが子状態を直接書き換えることは禁止する．

| 所有者 | 正本となる状態 |
|---|---|
| RootMediator | appMode，保存済み設定と展示中の設定revision，presentation取得・解放状態，入力スコープ，管理者セッション |
| ExhibitionMediator | Web世代，読み込みoperation，現在のcommit済みURL，復帰工程，無操作期限，再試行状態 |
| AdministrationMediator | 設定draft，検証結果，保存要求中の状態，認証中・失敗・クールダウン |
| Presenter | 状態を所有しない．必要に応じて表示用の投影キャッシュのみ |
| Adapter | OS handle，callback registry，Task，native object等の技術的な資源のみ |

子snapshotから導かれるinputAvailability等は読み取り専用のfactsとしてRootの裁定に渡す．同じ意味のisResetting等をRootに複製して同期する構造は避ける．Rootと子の遷移を同じrun-to-completion処理で確定させる．

## 7. RootMediatorの状態機械

```text
Bootstrapping
  ├── 初回セットアップ → Administration
  ├── 設定済み → EnteringKiosk
  └── 設定・資格情報の異常 → SafeHold

Administration
  → EnteringKiosk
  → Exhibiting
  → Unlocking
  → LeavingKiosk
  → Administration

Exhibiting → LeavingKiosk
  ├── Webでやり直す → EnteringKiosk
  └── Webで止める → Paused
Paused → EnteringKiosk（Webで再開）
Paused → Unlocking → LeavingKiosk → Administration（端末で認証）
SafeHold → EnteringKiosk（Webで再開，開始条件を満たす場合）

EnteringKiosk / Exhibiting / Unlocking / LeavingKiosk
  → SafeHold

Administration
  → Terminating
```

| 状態 | 意味・主要な処理 |
|---|---|
| Bootstrapping | 保存設定，資格情報の有無，接続画面を確認する．設定済みの再起動では管理画面を無認証で開かない |
| Administration | 通常ウィンドウで設定・確認．初回以外のアクセスは認証を前提にする |
| EnteringKiosk | 設定検証済みsnapshot固定，展示ウィンドウ準備，Presentation適用，Web開始 |
| Exhibiting | Kiosk表示を保持し，Exhibition状態に応じて入力を通す |
| Unlocking | Kiosk表示を維持し，認証UIだけ入力可．背後のWebは操作不可 |
| LeavingKiosk | Web停止，入力監視やPresentationを復元する |
| Paused | 展示用Webを止め，停止中の画面を保つ．端末の管理者入口とWebからの再開を受け付ける |
| SafeHold | 可能な範囲で展示ウィンドウを保持し，ネイティブ障害表示．管理者解除は受け付ける |
| Terminating | 管理者が要求した終了処理を行う |

認証失敗からLeavingKioskへの遷移は存在しない．RootはUnlockingに入る前の復帰先を保持する．Exhibitingからの解除要求をキャンセルまたはタイムアウトした場合は，Webセッションを初期化してExhibitingへ戻る．SafeHold起点の場合はSafeHoldに戻し，未起動の展示を勝手に開始しない．

Webの管理画面から展示を開始するときは，端末の開始操作と同じRootの条件を通す．Webからのやり直し・停止・再開では，端末のAdministrationとUnlockingを通らない．やり直し・停止ではマウス固定を解放する．停止中はPresentationを保持したまま展示用Webを止める．再開時はPresentationを解放してから保存済み設定で取得し直し，必要ならマウス固定を取り直す．端末の管理者入口からのみUnlockingへ進み，パスワードまたは生体認証の成功後に管理画面を開く．停止中の状態は保存しない．

EnteringKioskは成功したEffectの取得状況を記録する．開始失敗時には，取得済みの資源だけを解放する．正常な終了・解除時は，変更前のPresentation設定を復元する．資源の取得・解放はtokenで対応付ける．

SafeHoldは端末のセキュアロックを意味しない．アプリ非アクティブ化やクラッシュを含めたOS全体の隔離は保証しない．

## 8. ExhibitionMediatorの状態機械

```text
Inactive
  → Preparing
  → Ready
       ├── Pristine
       └── Engaged(deadline)
  → Resetting
       ├── Quiescing
       ├── RecreatingSurface
       └── LoadingHome
  → Ready.Pristine

Preparing / Ready / Resetting
  → Recovering(attempt, nextRetryAt)
  → Preparing

Recovering
  → Unavailable(reason)
```

Ready中の通常のページ遷移は，pageLoadという子状態でloading／settledを管理する．強制復帰中と通常のリンク遷移を同じloadingフラグに押し込めない．

NavigationRequestはReadyに加え，PreparingとResetting.LoadingHomeでも，現在の読み込みoperationに属するものを裁定する．QuiescingやRecreatingSurfaceで到着した旧世代Requestはcancelする．アプリ自身が開始した読み込みも同じURLポリシーを通す．許可リストでは開始URLのoriginを表示付きで自動許可するが，schemeやHTTPの検証は省略しない．

### 8.1 無操作の意味

既定値は暫定120秒．有効なカーソル移動・主ボタン操作・許可されたスクロール等をVisitorActivityとして扱う．ブロックした右クリックやジェスチャ，ページの通信，動画の再生，JavaScriptの自動動作は操作として数えない．

起動・復帰が成功した直後はPristineとし，無操作タイマーは未armedにする．最初の受理入力でEngagedに入り，期限を設定する．以後の受理入力で期限を延長する．URLが開始URLと同じでも，操作を受けたらEngagedにする．

基準表示完了後に別の主ページへ自動遷移した場合も，Pristineならその時点で一度だけ期限を設定する．その後の自動遷移では延長しない．任意サイトのDOM内部変化まで検知できる保証は設けない．

Timerは発火の通知のみ行う．期限切れの判定はMediatorが，注入された単調時計の時刻と現在のdeadlineで行う．時計変更による誤動作を避ける．マウス移動のたびにTimerを作り直さず，期限通知が早すぎたときに最新deadlineへ再設定する方式を用いる．

復帰に入った時点でidleを解除し，成功後はPristineへ戻す．これにより誰も触っていない間の無限再読み込みを防ぐ．読み込み失敗からの再試行はIdleではなくRecoveryが管理する．

### 8.2 復帰モード

| モード | 実装方針 | 保持・破棄 |
|---|---|---|
| RetainWebsiteData | WebViewを作り直し，同じWebsiteDataStoreを利用する | DOM・WebView履歴は作り直す．Cookie等のサイトデータは保持 |
| NewVisitorSession | WebViewと非永続WebsiteDataStoreの両方を新しくする | 新しい閲覧セッションへ切り替える |

非永続WebsiteDataStoreはメモリー上にWebデータを置くAPIである．非永続に設定しただけで，時間経過による消去が実装されるわけではない．[A4]

サーバーに保存された状態やサーバー側セッションの無効化までは，いずれのモードも保証しない．保持モードでは，サイトが保存データから表示位置や入力を復元する可能性もあるため，「必ず完全な初期画面になる」とは表現しない．

### 8.3 復帰処理の工程

1. Resettingへの遷移と同時にWebへの入力を止める．webGenerationを更新し，以後の旧世代通知を無効にする．
2. 旧WebViewの読み込みを止め，残存Requestをcancelし，delegate・ホスト・参照を解放する．旧surfaceの破棄完了を確認する．
3. モードに応じたWebsiteDataStoreと新WebViewを用意する．
4. 展示中の設定snapshotにある開始URLを，新operationIDで読み込む．
5. 現世代・現operationの成功だけを受け付け，Ready.Pristineに戻す．

これらは単純な並列Effect配列にしない．工程ごとの結果イベントを受けて次工程へ進む．

### 8.4 障害復帰

WebKitのコンテンツプロセス終了通知をイベント化する．[A5] 加えて読み込みタイムアウトを設ける．任意のWebアプリの内部停止まで完全に検出できるとはしない．

一時的な通信失敗等には回数上限付きの再試行を行う．待機時間と上限は設定として保持し，Adapter内に固定しない．URLポリシーによるcancel，認証失敗，無効な設定，TLS問題は無条件の再試行対象にしない．

アプリ自身のクラッシュ後の再起動は，プロセス内部のMediatorでは担当できないため，ログイン起動や外部監視の別機能として扱う．

## 9. URLポリシー

### 9.1 初版のルール単位

初版の許可・拒否単位はorigin（scheme，host，port）とする．開始URLのpath・query・fragmentは保持して読み込むが，閲覧先ルールの判定には含めない．設定画面には開始URLのoriginを編集・削除できない行で表示する．

```text
NavigationPolicy
  mode: allowlist | denylist
  rules: OriginRule[]

OriginRule
  scheme: https | http
  host: canonical host
  port: normalized port
  includeSubdomains: Bool
```

allowlistは開始URLのoriginと追加ルールに一致したoriginを許可する．開始URLの自動許可はProfileから算出し，追加ルールとして重複保存しない．denylistは一致したoriginを拒否する．いずれでも，危険なscheme等を拒否する共通の制約は先に適用する．

ルール評価は文字列部分一致にしない．URLの解析・正規化，hostの大小文字，既定port，IDNA，末尾ドット，IPv4／IPv6を一貫して処理し，解釈できないURLは拒否する．userinfo付きURLは初版では拒否する．サブドメイン判定はラベル境界で行う．

例：example.comのサブドメイン許可は，sub.example.comを許可するが，example.com.attacker.invalidやnotexample.comを許可しない．

allowlistでは開始URLの変更に自動許可も追従する．この許可をサブドメインや異なるscheme・portへ広げない．denylistで開始URLが拒否される設定は保存・展示開始できない．保存時の検証，実際の遷移，開始・無操作復帰の読み込みはProfileの共通の評価を使う．

path単位の制限は，SPAの同一document遷移等の意味を詰める必要があるため初版に含めない．originだけでは要件が満たせない展示は，開始前に仕様を追加する．

### 9.2 適用範囲

主フレームのナビゲーションと，新規ウィンドウへの移動に適用する．埋め込みフレームや画像・動画・API等の読み込みは，主フレームの許可リストと同一視しない．初版は埋め込みWebコンテンツを許容する互換性優先の仕様とし，この制限範囲を設定画面にも明示する．

ナビゲーションのaction段階とresponse段階を使い，観測できるリダイレクトも再評価する．response側の最終URLも確認する．主ページへの遷移を許可する機構としてWebKitのNavigationDelegateを利用する．[A2]

これは「未許可先へ1リクエストも送信しない」というネットワーク隔離の保証ではない．その保証が必要な場合は，ネットワーク制御を独立した要件として設計する．

### 9.3 新規ウィンドウと周辺機能

WebKitの新規WebView生成要求も，ExhibitionMediatorへ裁定を求める．[A3] 初版は新しい展示ウィンドウを作らない．

許可された通常のGETリンクは，同じWebViewで開くEffectへ変換する．空のwindow.open，window.openerに依存するフロー，新規ウィンドウへのPOST等は，無理にGETへ変換せず拒否する．これらに依存するOAuthやサイト動作は互換性対象外とする．

外部アプリ起動，ファイルダウンロード，ファイル選択，権限要求は初版で拒否する．JavaScriptのalert／confirm／promptはOS標準モーダルを直接開かず，型に応じた閉じる・否定・取消の応答で解決する．これらを使うコンテンツの互換性は受け入れ試験で確認する．

file，mailto等の外部・非Web schemeへ渡さない．独自の管理用JavaScriptブリッジを任意サイトへ公開しない．

### 9.4 HTTPの扱い

ランタイムでHTTPを許可することと，アプリのATS設定は別である．ATS例外はInfo.plist等の配布構成と整合させる必要がある．[A9] 初版の配布条件を確定する時に，固定の例外で足りるか，任意HTTPのWeb表示が必要かを決める．URLルールの実装だけでHTTPが利用可能になるとはしない．

## 10. 入力ポリシー

### 10.1 初期値

| 入力 | 展示中の初期値 |
|---|---|
| カーソル移動，主ボタンdown／up | 許可 |
| スクロール | 拒否．設定で許可可能 |
| ドラッグ | 拒否．設定で許可可能 |
| 右クリック，その他ボタン，Control-click | 拒否 |
| 拡大縮小，回転，戻る・進むジェスチャ | 拒否 |
| 一般キー入力・ショートカット | 拒否 |
| 管理者解除用ショートカット | Rootが認証開始要求として扱う |

WebKit側でもallowsMagnificationとallowsBackForwardNavigationGesturesを無効にする．後者は水平スワイプによるページの戻る・進むを制御するAPIである．[A6]

RootMediator内のInputPolicyは，AppMode，入力先scope，ExhibitionのinputAvailability，設定snapshot，押下中の状態を入力として，pass／dropを返す．AdapterはNSEventへの変換と適用のみを行う．

### 10.2 入力スコープ

ExhibitingではWebSurface，Unlockingでは認証UI，Administrationでは管理画面を入力スコープとする．ResettingやSafeHoldでは，Webへの入力を許可しないが管理者解除要求は常に受理できるようにする．

認証UIの文字入力を通すことと，アプリ終了やウィンドウ操作のショートカットを許可することは分ける．window close，アプリ終了，メニュー操作もRootのRequestに変換する．

### 10.3 down／upと世代変更

入力は単発イベントではなく，押下から解放までの列として扱う．RootのInputStateに，どのsurface世代へdownを渡したかを保持する．downを渡した対象へのupを不整合に捨てない．

復帰・モード変更中に旧surfaceが破棄された場合は，その押下列を旧世代で終わらせ，新surfaceへupだけを渡さない．必要な場合はボタン解放まで新しい入力列を受け付けない．

単純なleftMouseDraggedの抑制だけで，任意サイトが独自実装した長押しや全ジェスチャを完全に禁止できるとはしない．初版が制御するのはAppKitに届く入力と，公開WebKit APIで制御できる機能である．

### 10.4 OS側のジェスチャ

ローカルイベントモニターが制御できるのは自アプリに配信されるイベントである．グローバルイベントモニターも他アプリへのイベント配送を止めるものではない．[A1]

Mission Control等のトラックパッド操作と，カーソルを角へ移動するだけで作動するホットコーナーは，専用アカウントの設定と実機検証を前提にする．[A8] 初版ではCGEventTapや非公開設定の書き換えを必須にしない．

## 11. Presentationと管理者解除

展示用のAppKitウィンドウを用意し，タイトルバーや通常の閉じる操作を来場者に公開しない．設定画面は通常のSwiftUIウィンドウとする．

PresentationAdapterはhideDock，hideMenuBar，disableProcessSwitchingの適用と復元を担当する．hideMenuBarはhideDockと併用する．これらの設定はアプリがアクティブな間のシステム表示に作用するものである．[A7]

管理者は物理キーボードで専用ショートカットを入力し，アプリ独自の認証画面で管理者パスワードを検証する．Rootは認証成功前にPresentationを解除しない．認証処理に伴ってOSの資格情報UIを展示中に出さないように，保存方式と利用条件を初期セットアップで確認する．

資格情報はCredentialAdapter経由で扱い，設定JSONへ平文保存しない．Keychainに検証用情報を保存する設計とする．認証失敗回数・クールダウンはAdministrationMediatorで管理する．管理者パスワード・入力内容を診断ログへ出さない．コード内の `passcode` 識別子と既存のKeychain項目名 `administrator-verifier` は，保存済み資格情報とテストの互換性を保つため変更しない．利用者に見せる文言には「管理者パスワード」を使う．

Webからの管理を端末で有効にすると，端末内のHTTPサーバーが同じ管理者パスワードを検証する．Webからの失敗もAdministrationの失敗回数・待ち時間に加える．Webの認証成功だけでは端末のPresentationを解除せず，端末に管理画面を出さない．セッションはRootが所有し，条件は [ADR 0003](../adr/0003-web-administration.md) に記録する．

管理者パスワードの保存後に，管理画面で生体認証による解除を有効にできる．有効化時はTouch IDまたはFace IDで一度確認する．有効状態は登録中の指紋・顔に結び付けた別のKeychain項目で表し，設定JSONには含めない．端末の登録者全員が管理画面を開ける条件と，登録変更時に無効になることを表示する．解除画面で明示的に生体認証を選んだときだけKeychain項目を照合する．iPad・iPhoneでは解除中に限り，OSの認証画面を本体の画面に出す．外部の展示画面には出さない．取消・60秒の期限後に届く成功はRootが拒否し，生体認証の失敗は管理者パスワードの待ち時間に加えない．登録変更で無効になったときは再設定を案内する．判断と確認範囲は [ADR 0002](../adr/0002-biometric-administrator-unlock.md) に記録する．

展示中の解除画面では，利用者がTouch IDのボタンを押したときだけ認証を始める．Macでは管理者パスワード欄の横にTouch IDのアイコンを置き，同じ `LAContext` に結び付けた `LAAuthenticationView` を解除画面に取り付けてから評価する．展示中にOS標準の認証パネルを出さない．成功の条件は登録内容に結び付けたKeychain項目を読めることとする．失敗や取消後も管理者パスワードを使え，認証中の60秒経過とSafeHold移行ではRootが操作を取り消す．

アプリが固まった場合の管理者復旧は，アプリ内ショートカットだけに依存できない．スタッフ側の端末アクセスを運用上確保する．開発中はOSの最終的な復旧経路を封じる設定を有効にしない．

ディスプレイの切断・追加，アプリの非アクティブ化はPlatformのFactとしてRootに通知する．対象外の構成ではSafeHoldに入り，再開前に管理者確認を求める．iPad・iPhoneの一時的なアプリ切替に限り，Plinthへ戻ったときに展示を再開する．管理者解除・OSのスリープ通知・画面の切断はこの対象にしない．詳細は [外部表示](mobile-external-output.md) を参照する．物理ディスプレイ変更の瞬間にもデスクトップが絶対に見えない，という保証はしない．

## 12. 設定と保存

```text
KioskProfile
  schemaVersion
  revision
  startURL
  navigationPolicy
  interactionPolicy
  idleTimeout
  resetMode
  recoveryPolicy
  presentationPolicy
  webAdministrationEnabled
```

設定の正本は3種類に分ける．

- savedProfile：保存済みの設定．Rootが所有する．
- draftProfile：管理者が編集中の設定．Administrationが所有する．
- activeProfile：展示開始時に固定した設定snapshot．Rootが所有し，Exhibitionへ読み取り専用で渡す．

端末では管理画面で設定を変更する．Webからは管理中・展示中・停止中・SafeHoldで，同じdraftを編集して保存できる．展示中に保存してもactiveProfileを変えず，現在の展示ルールは差し替えない．Webから開始・やり直し・再開を要求したとき，未保存のdraftがあれば拒否する．成功すれば保存済みの設定で展示を始める．

保存経路は，Viewの変更通知 → Administrationのdraft変更・検証 → ProfileCommitRequestedを親へ送出 → Rootの保存裁定 → Repository Effect → 結果Fact → 保存完了の通知，とする．保存失敗を成功として表示しない．

Webからの管理は既定で無効とし，端末の管理画面でのみ切り替える．有効なときのURLとQRコードは端末の管理画面に出す．iPadの外部展示中・停止中は，本体にもQRコードを出し，外部画面には出さない．Webの画面はRootの保存済みProfile・状態とAdministrationのdraftをPresenterで投影する．入力中の管理者パスワードを含む端末用Propsは使わない．Webからは管理者パスワード・生体認証・Web管理の有効状態を変更できない．画面や解像度の選択肢は端末と同じ接続状態から作り，一覧にない値は拒否する．外部用ウィンドウの準備は端末で行う．通信と状態遷移の理由は [ADR 0003](../adr/0003-web-administration.md) に記録する．

Repositoryは一時ファイルからの置換等による原子的な更新，schemaVersionの検証，破損時の報告を担当する．移行できない設定を勝手に補って展示開始しない．

## 13. モジュール境界

```text
KioskCore
  Events / Models / Policies
  Root / Exhibition / Administration state machines
  Ports / Transition contracts

KioskPresentation
  Immutable ViewProps / UIIntent contracts
  Pure Presenters

KioskMacApp
  Composition / RootRuntime
  UI: Passive SwiftUI views and render-only hosts
  Platform: AppKit / WebKit / Keychain / persistence adapters

Tests（Swift Testing）
  Core / Routing / Presentation / AdapterContract / NativeIntegration

UITests（XCTest + XCUIAutomation）
  Administration / Exhibition / Recovery workflows
```

CoreはAppKit，WebKit，SwiftUIに依存させない．PresentationはCoreのsnapshotを入力として投影する．View側は表示用契約だけを読み，ModelやMediatorの可変状態を直接読まない．

パッケージ境界と静的検査で依存方向を維持する．Viewの中にload，reload，URLSession，Timer，Taskを使った業務処理，ストアへの保存，設定判断が入る変更はレビューで拒否する．Native APIの形式変換はAdapterに限定する．

## 14. 診断とプライバシー

記録するのは，状態遷移名，イベント型，拒否理由コード，世代・operation識別子，再試行回数，設定revision，障害分類である．UIの全入力やマウス座標は永続化しない．URLを記録する場合はquery，fragment，userinfoを落とし，必要性に応じてoriginまでに制限する．

debug用のイベント経路表示はRootRuntimeで生成する．通常利用では高頻度入力をログ化しない．決定的な再現は，秘密情報を含まないテストfixtureとFakeClockを基準とし，本番ログに全ペイロードを保存する方式は採用しない．

## 15. 不変条件とテスト

### 15.1 不変条件

- すべてのNodeはRootから到達可能である．
- 1つのイベントは最大1つの所有Mediatorで裁定される．
- 既知だが不許可のイベントを親へ横流ししない．
- Viewの再描画は新しいEffectを発生させない．
- 古い世代・operationの結果は現在のWeb状態を書き換えない．
- WebKitのRequestは破棄時を含めて一度だけ完了する．
- 認証前にPresentation解除へ進まない．
- Resetting中はWebへの利用者入力を通さない．
- 無操作復帰が成功した後は，次の操作等でarmedされるまで再復帰しない．
- 許可された開始URLが存在しない設定では展示を開始しない．

### 15.2 テスト構成

CoreのテストにはFakeClock，RecordingEffectExecutor，ScriptedWebPortを使用する．WebKitやウィンドウを起動せずに，状態とEffect列を検証できるようにする．

| 分類 | 主な受け入れ条件 |
|---|---|
| CoR | 子が未知イベントをBubbleし，正しい親が処理する．既知の不許可イベントはそこで止まる |
| Passive View | 同じPropsで何度描画しても読み込み・保存Effectが増えない |
| URL | 境界の違うhost，サブドメイン，port，IDN，壊れたURL，リダイレクト，新規ウィンドウを確認 |
| Idle | 同じURLのまま操作しても復帰する．自動通信では期限が延びない．復帰後に繰り返さない |
| 世代 | 旧didFinish・旧timeoutは無視する．旧decisionHandlerはcancelされる |
| 入力 | 拒否操作がWebに届かない．down→reset→upで新surfaceに孤立upが届かない |
| 認証 | 失敗・取消・タイムアウトで制限を解除しない．成功時だけ離脱工程へ進む |
| 障害 | Webプロセス終了・通信失敗で上限付き復帰．URL拒否から自動リトライしない |
| 保存 | 不正設定を適用しない．保存失敗時にdraftとsavedを混同しない |
| 実機 | 画面端，多指ジェスチャ，Control-click，Force Click，外部ディスプレイ，スリープ復帰を検証 |

実機試験はCoreのユニットテストで代替しない．対象のmacOS，機種，トラックパッドを受け入れ環境として記録する．

## 16. 実装順序

| 段階 | 作るもの | 完了条件 |
|---|---|---|
| 1 | Root所有ツリー，CoR，状態・Effect契約，FakeClock | UIなしで主要シナリオを実行できる |
| 2 | 最小の展示ウィンドウ，Presentation，管理者解除，NativeInput | 実機で解除経路を確認し，OS側の制限範囲が判明している |
| 3 | WebSurface，NavigationPolicy，callback registry | 許可・拒否・リダイレクト・新規ウィンドウの受け入れ試験が通る |
| 4 | Idle，Web世代，復帰工程，Recovery | 遅延通知・通信失敗・Webプロセス終了を含めて復帰できる |
| 5 | Passiveな設定画面，原子的保存，診断 | 設定→展示→放置→復帰→管理者解除の通し試験が通る |

最初の実機検証で確認する中心は，トラックパッドによるOS操作の抜け道と管理者解除である．設定画面の作り込みはその後に行う．

## 17. Swift Agent Skillsを反映した実装・レビュー規約

### 17.1 参照方法と優先関係

| 参照Skill | 本プロジェクトでの用途 | 一律には適用しないもの |
|---|---|---|
| SwiftUI Pro [S1] | Observation，Viewの分割，安定したidentity，アクセシビリティ，再描画コスト，APIの適用可否 | Viewからの業務処理，Modelへの直接書き込み，iOS専用API・画面構成 |
| Swift Concurrency Pro [S2] | isolation，Sendable，Taskの所有，協調キャンセル，await境界の状態検証 | 同期裁定のasync化，Mediatorごとのactor化，全Effectの並列実行 |
| Swift Testing Pro [S3] | 新規の単体・結合テスト，パラメーター化，非同期完了の検証，fixture分離 | UIテストをSwift Testingへ置き換えること，待機時間頼みのテスト |

これらは実装品質を点検する参照規約であり，アプリに組み込むランタイムライブラリではない．本プロジェクトの責務境界は1〜16節を正本とする．Skillにある一般例が責務境界に合わない場合，境界を崩さずに目的を満たす代替を採る．コンパイラ・SDKの契約と矛盾する設計は，警告抑制で通さず設計上の問題として解決する．

SwiftUI SkillにはiOSや新しいSwift／Xcodeを前提にした記述が含まれる．READMEと個別Skillの前提バージョンも同一とは限らない．採用するmacOS，SDK，Swiftコンパイラの実体を確認し，iOSの前提をMacへ機械的に移さない．この追補だけを理由にdeployment targetを引き上げない．[S1][S4]

参照先を導入・更新する時は，実際に取得したcommitを記録する．この文書の末尾には今回読んだファイルのblob SHAを記載するが，これはリポジトリのcommit SHAやインストール済みである証明ではない．Skill本体をこの文書へ複製せず，必要な参照ファイルだけを読む運用とする．

### 17.2 SwiftUI：Observationを表示境界に限定する

採用する表示経路は次のとおりとする．

```text
確定したCore State
  → 純粋なPresenter
  → Node別のRenderPropsStore
  → Component Adapter
  → Passive View(props, sendIntent)
```

RenderPropsStoreはRootRuntime配下で所有する，表示用の投影キャッシュである．業務状態の第二の正本ではない．Observationを採用する場合は`@Observable`かつ`@MainActor`とし，Runtime以外から投影値を書き換えられないAPIにする．Passive ViewにMediator，Repository，可変Core Storeへの参照を渡さない．Observationを使ってもMVVMへ変更するわけではない．[A10]

Observationを含むSwiftUI対応の下限はmacOS 14である．より古いMacの対応が必要な場合は，表示通知のAdapterを変える判断が別途必要となる．本追補では対象OSの下限自体を確定しない．[A10]

ViewPropsは可能な範囲でEquatableな値型とし，Runtimeは等価な投影を再発行しない．巨大なTreeState全体を一つのObservableプロパティに載せて全画面へ配らず，Node単位の投影に分ける．カーソル移動に伴うidle deadlineの更新だけでは，無関係な設定画面やWeb hostを更新しない．この設計だけで再描画回数をゼロと保証せず，SwiftUI側の更新は計測する．

Bindingは「Propsから読み，UIIntentを送る」ための薄い接続に限定する．`Binding(get:set:)`を使うこと自体は禁止しない．setは型付き意図を送るだけとし，draftの変更，検証，保存の要否はAdministrationMediatorが同期的に裁定する．Bindingのクロージャを部品ごとに乱造せず，Component Adapterで共通化する．同一値の再設定を含む入力の意味と，プログラムによる値変更を区別する．[S4]

SwiftUI Skillの「直接Binding＋onChangeで保存」という例は本プロジェクトでは採用しない．`.onChange`，`.task`，`.onAppear`，`updateNSView`から，load，保存，認証，タイマー開始，Presentation適用を呼び出さない．表示のみのフォーカスやアニメーションは別だが，業務上の遷移へ昇格する操作はUIIntentを経由させる．[S1]

設定入力の正本は引き続きAdministrationのdraftとする．数値欄の入力途中の空文字や不完全な文字列も編集状態として保持し，検証済みの数値と区別する．値が一時的に無効でもViewに別のdraftを作って補わない．URLルールの行は追加時に安定したruleIDを発行し，配列indexや編集中のhostをidentityにしない．[S4]

管理画面・解除画面には，明示したラベル，フォーカス順序，アクセス可能な操作名を設ける．展示モードの入力制限を管理画面の操作性まで一律に適用しない．外観の刷新やLiquid Glassの追加は本改訂の範囲外とする．

### 17.3 Concurrency：同期の制御経路と非同期の実行経路

| 実行領域 | 隔離と所有 | 契約 |
|---|---|---|
| KioskCore | default isolationはnonisolated．遷移・Policyは純粋な値操作 | await，I/O，Task生成を持たない．本番ではMainActorのDispatcherから同期呼び出し |
| KioskPresentation | 純粋なPresenterと値型Propsはnonisolated | UI frameworkを必要とする可変通知オブジェクトはここへ混ぜない |
| KioskMacAppの制御・表示 | TreeDispatcher，Store，Node，RenderPropsStore，AppKit／WebKit AdapterはMainActor | 即時Replyを返す経路ではawaitしない |
| Effectの実行 | Root配下のExecutorがTaskを所有．必要なI/O・計算は専用の隔離領域へ | 結果は値イベントとして入口Nodeから返す．Core Stateを直接変更しない |
| テスト | 純粋Coreテストはnonisolated．Runtime／UI境界のテストだけMainActor | テスト全体をMainActorへ寄せてデータ共有問題を隠さない |

最低でもSwift 6 language modeでデータ競合安全性を検証する方針とする．具体的なコンパイラ／Xcode／SDK／deployment targetは実装開始時に記録し，アプリ・Package・テストそれぞれのdefault actor isolationとupcoming feature設定も記録する．「Swiftのバージョンが同じだから隔離も同じ」とみなさない．[S2][A11]

`async`や`Task {}`だけを付けてメイン実行経路から退避したと考えない．nonisolated async関数の実行場所は，NonisolatedNonsendingByDefault等の設定にも依存する．重い処理を退避する場合は，利用するtoolchainで検証したworker actorや`@concurrent`等を明示し，メイン経路で行われないことを確認する．actorを専用OSスレッドと同一視しない．[A11]

CoRへの同期Requestを`Task { await ... }`やAsyncStreamへ変換しない．ここでは保存済みsnapshotと純粋Policyだけで判断する．非同期の問い合わせが必要な業務は，先に状態をpendingへ遷移させる別のRequestとしてモデル化する．同期Requestでsemaphore待機やmain queueへの同期dispatchを使わない．[A1]

actor境界を越えるEvent payload，Effect descriptor，結果snapshotはSendableな値で表現する．Node参照，WKWebView，NSEvent，decisionHandler，Bindingを別actorへ渡さない．native objectを識別子で参照するregistryはMainActor側に残す．`@unchecked Sendable`，`nonisolated(unsafe)`，包括的な`@preconcurrency`を診断抑制目的で導入しない．SDKの注釈不足に対処する必要がある場合も，根拠を確認した狭いInterop境界としてレビューする．[S2]

### 17.4 EffectTaskRegistryとキャンセルの契約

```text
EffectTaskRecord
  effectID
  ownerNodeID
  ownerEpoch
  operationID
  webGeneration? / profileRevision?
  taskHandle
```

TaskはRoot配下のEffectExecutorだけを通常の生成窓口とし，Registryに所有Nodeと実行IDを記録する．View・Presenter・MediatorからTaskを生成しない．同期イベントから非同期Effectを開始する境界では，handleを所有する非構造化Taskを許容するが，内部の独立した複数処理はstructured concurrencyを優先する．復帰の依存工程をtask groupで並列化しない．[S2][A12]

同じoperationの置換・Node終了・Root停止では，状態側で旧operationを無効にしてから，RegistryのTaskへcancelを伝える．明示的なstop工程で回収し，deinitだけに寿命管理を依存しない．TaskクロージャからNodeやRootを不要に強参照し続けない．

Swiftのキャンセルは協調的であり，cancel()は処理停止や結果の不着を保証しない．結果の受理時に，ownerEpoch，operationID，必要なwebGeneration／profileRevisionをMediatorが再照合する．キャンセルの有無と古い結果の拒否は，それぞれ独立した防御とする．通常の取消を通信障害としてリトライしたり，エラー表示したりしない．[A12][S5]

WebKitの返答待ちRequestはTaskではなくDecisionRegistryの管理対象である．一度だけ完了するReplyの契約を維持し，不要なcontinuationへ包み替えない．真に非同期のcallback APIをawaitへ橋渡しする場合だけ，成功・失敗・取消のすべてで一度だけresumeする契約を追加する．

`withTaskCancellationHandler`のonCancelからMainActor上のregistryやWebViewを直接変更しない．cancel側と完了側の競合をAdapter境界で解決し，MainActorで必要な資源解放は明示的な終了工程の一部として完了通知を待つ．[S5][A12]

破棄対象世代の通常の読み込み通知は拒否するが，登録済みの破棄operationに対するReleaseCompletedまで「古い世代」として一律に捨てない．資源解放の結果はteardown tokenで照合し，Quiescingの完了を確定する．

取消は外部I/Oの巻き戻しでもない．設定保存はrevision付きで直列に実行し，原子的置換と実際の結果で確定する．取消後に古い書き込みが新しい保存結果を上書きしないように，Repositoryの実行順と結果の照合をテストする．

### 17.5 Swift Testing：処理の完了を検証できる設計

Core，Policy，Presenter，CoR，Adapter contractの新規単体・結合テストはSwift Testingで記述する．画面操作を伴うUIテストはXCTest＋XCUIAutomationの別ターゲットに置く．同じテスト内で両者のassertion APIを混在させない．[S3][A13]

テストは結果のStateだけでなく，Reply，Effect列，拒否理由，親・子イベントの経路を比較する．URLルールと入力ポリシーは，期待結果を持つケース値の配列によるパラメーター化テストにする．二つの独立配列を渡した時の直積と，対応するケースの組を混同しない．前提を満たさなければ検証を継続できない箇所では`#require`，独立した検証には`#expect`を用いる．[S3][S7]

実時間のsleepや繰り返しyieldを，処理完了の根拠にしない．FakeClockのadvance，ScriptedWebPortの結果送出，Effectのoperation単位の完了待機を備える．RootRuntimeはテストから，指定したoperationの結果イベントが配送・確定したことを観測できるようにする．常設タイマーを含む全Taskの終了を待つ汎用drainではなく，対象を限定した完了契約を使う．

`confirmation`は期待イベントを自動で待ち続ける機構ではなく，渡したclosureが戻る時点で条件を確認する．callbackを登録してすぐ戻らず，対象operationの完了をclosure内でawaitする．`expectedCount: 0`も観測した実行区間だけの検証であり，将来永久に発火しないことの証明として扱わない．[S6][A14]

テストごとにRoot／Runtime，FakeClock，一時ディレクトリ，プロフィール，fake credential storeを新規生成する．本物のKeychain，本番プロフィール，共有UserDefaults，固定ポートへ依存させない．WebKitの実結合テストでは管理下のローカルfixtureを使い，Coreテストではライブネットワークを使わない．

Swift Testingは並列実行が既定であり，`.serialized`はsuite内またはパラメーター化テスト内を直列化するが，無関係なsuiteとの排他にはならない．NSApplicationなどプロセス共有状態が必要な実結合テストは，専用のtest target／test planへ分け，その実行ジョブ全体の並列化を制御する．`.serialized`で依存の漏れを隠さない．[A15]

Presentationを実際に変更するテストは，通常の単体テストや開発端末で自動実行しない．専用の実機試験として明示的に起動し，復元経路を確保する．OSジェスチャやトラックパッドの検証は引き続き実機で行う．

追加する回帰シナリオ：

| シナリオ | 合格条件 |
|---|---|
| TextFieldへ同じ値を再入力 | UIIntentの扱いはMediatorで一貫し，onChange依存で保存の意味が変わらない |
| Propsを繰り返し更新・再描画 | WebViewの生成・load・保存・Task起動が増えない |
| Reset直後に旧読み込みが成功 | 現世代のStateと表示は変わらない |
| 認証取消後に検証成功が返る | Rootの管理者セッションは作成されずPresentationは解除されない |
| Task cancel後に結果が返る | stale照合で拒否され，不要な再試行が発生しない |
| 旧surfaceの破棄完了 | 破棄operationのtokenが一致すれば次工程へ進める |
| 確認closureの終了前に完了を待つ | callback未発火を見落とす偽陽性・待機不足の偽陰性がない |
| テストを並列実行 | ほかのfixtureの状態・ファイル・時刻を変更しない |

### 17.6 エージェント向けの実装・レビュー順序

実装着手時には，先に本設計の責務境界と変更対象を確認する．UI変更ではSwiftUI Pro，非同期境界ではSwift Concurrency Pro，テスト変更ではSwift Testing Proの該当参照を読む．どのSkillも，本プロジェクトのアーキテクチャを一般的なViewModel構成へ置き換える理由にしない．

レビューは，責務境界 → 状態遷移とReply → Task寿命と取消 → テストの決定性 → API・アクセシビリティ・描画性能の順で行う．実行したビルド・テストの環境と結果，未実行の実機項目を区別して報告する．実装対象外の外観刷新や大規模なモダナイズを同じ変更に混ぜない．

## 18. 参照資料と確認範囲

A1〜A9はv0.1の参照先を継承したもので，今回すべてを再検証したものではない．A10〜A15およびS1〜S7を本改訂で確認した．Skillは作成者自身の実装・レビュー指針，Apple／Swiftの資料はプラットフォーム・言語・テストAPIの根拠として区別する．いずれも，この設計全体がビルド済み・実機検証済みであることを意味しない．

- [A1] Apple, Cocoa Event Handling Guide — Monitoring Events： https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html
- [A2] Apple, WKNavigationDelegate / navigation action and response policies： https://developer.apple.com/documentation/webkit/wknavigationdelegate
- [A3] Apple, WKUIDelegate — createWebViewWith： https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:createwebviewwith:for:windowfeatures:)
- [A4] Apple, WKWebsiteDataStore.nonPersistent()： https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()
- [A5] Apple, webViewWebContentProcessDidTerminate： https://developer.apple.com/documentation/webkit/wknavigationdelegate/webviewwebcontentprocessdidterminate(_:)
- [A6] Apple, WKWebView gesture settings： https://developer.apple.com/documentation/webkit/wkwebview/allowsbackforwardnavigationgestures ／ https://developer.apple.com/documentation/webkit/wkwebview/allowsmagnification
- [A7] Apple, NSApplication.PresentationOptions / presentationOptions： https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct ／ https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.property
- [A8] Apple Support, Hot Corners / Trackpad settings： https://support.apple.com/guide/mac-help/perform-quick-actions-with-hot-corners-mchlp3000/mac ／ https://support.apple.com/guide/mac-help/mchlp1226/mac
- [A9] Apple, Preventing Insecure Network Connections： https://developer.apple.com/documentation/security/preventing-insecure-network-connections

- [A10] Apple, Managing model data in your app： https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app/
- [A11] Swift.org, Swift 6.2 Released / NonisolatedNonsendingByDefault： https://www.swift.org/blog/swift-6.2-released/ ／ https://docs.swift.org/latest/documentation/diagnostics/nonisolated-nonsending-by-default/
- [A12] Swift, Task.cancel() / Concurrency： https://docs.swift.org/latest/documentation/swift/task/cancel%28%29/ ／ https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html
- [A13] Apple, Testing / XCTest： https://developer.apple.com/documentation/xcode/testing ／ https://developer.apple.com/documentation/xctest
- [A14] Apple, confirmation(_:expectedCount:isolation:sourceLocation:_:)： https://developer.apple.com/documentation/testing/confirmation%28_%3Aexpectedcount%3Aisolation%3Asourcelocation%3A_%3A%29-5mqz2
- [A15] Swift, ParallelizationTrait： https://docs.swift.org/latest/documentation/testing/parallelizationtrait/

#### 今回確認したSkillファイル（2026-10-14）

以下のSHAは各ファイルのGit blob SHAであり，commit SHAではない．default branchの参照内容は将来変わるため，実際に導入する際は取得commitも記録する．Skillの外部リンク先をすべて確認したという意味ではなく，以下の本文と，SwiftUI／ConcurrencyのREADMEを読んだ範囲を示す．

| ID | Repository / path | 読み取ったblob SHA |
|---|---|---|
| S1 | twostraws/SwiftUI-Agent-Skill / swiftui-pro/SKILL.md | 916d0d500c2910188f0da1502ae97f05511c2d70 |
| S2 | twostraws/Swift-Concurrency-Agent-Skill / swift-concurrency-pro/SKILL.md | 5549099b5473626ad78da0c61546706f3ea6b30d |
| S3 | twostraws/Swift-Testing-Agent-Skill / swift-testing-pro/SKILL.md | b26429479c8615d293bd41b23ed0e6a02b2e1ad7 |
| S4 | twostraws/SwiftUI-Agent-Skill / swiftui-pro/references/data.md | 966a63bb477b8a78c2f5e8f8eaac6ebdf8250165 |
| S5 | twostraws/Swift-Concurrency-Agent-Skill / swift-concurrency-pro/references/cancellation.md | cdbb82ec14a1bc918a9e530f3496c5538504d55c |
| S6 | twostraws/Swift-Testing-Agent-Skill / swift-testing-pro/references/async-tests.md | 69d5e5d2bc500d188590f036901bd06fb6de529e |
| S7 | twostraws/Swift-Testing-Agent-Skill / swift-testing-pro/references/core-rules.md | e20e131c7aa459840295734b232efbc845fa0c46 |

- SwiftUI Pro： https://github.com/twostraws/swiftui-agent-skill
- Swift Concurrency Pro： https://github.com/twostraws/Swift-Concurrency-Agent-Skill
- Swift Testing Pro： https://github.com/twostraws/Swift-Testing-Agent-Skill
