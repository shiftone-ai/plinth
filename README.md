# Plinth

Mac・iPad・iPhoneでWebコンテンツを展示するキオスクランタイム．管理者が開始URLと閲覧・入力の制限を設定し，無操作や通信障害から展示状態へ復帰させる．

## 初版の機能

- 本体または外部ディスプレイへの展示．Macは出力先と全画面固定・ウィンドウ表示を選択できる．
- 開始URL，許可・拒否リスト，HTTP・スクロール・ドラッグの制限．開始URLのoriginは許可リストへ自動で追加される．
- 無操作・通信障害からの復帰と，復帰時のサイトデータの扱いの選択．iPad・iPhoneは一時的なアプリ切替から戻ったときに展示を再開する．
- 管理者パスコードによる解除と，revision付きの設定保存．
- iPad・iPhoneの独立した外部表示，解像度の選択・回転，本体からの操作と外部マウス入力．

閲覧先は `*.example.co.jp` のように入力できる．[ドメインの入力と拒否時の動作](docs/design-docs/navigation-input.md) に評価範囲をまとめている．

Mac専用版，iPad・iPhone版を実装し，実機とSimulatorで設定・URL制限・無操作復帰・管理者解除を確認した．iPadの外部表示では，解像度・全4方向の回転・設定から戻った後の復帰も確認した．物理トラックパッドによるWeb操作と画面の端での制限，実ケーブルの抜き差し，複数画面のMacと1週間の実時間運転は未確認．検証範囲は [開発と検証](docs/development.md) を参照する．

多言語対応（[#1](https://github.com/shiftone-ai/plinth/issues/1)），Webからの設定（[#2](https://github.com/shiftone-ai/plinth/issues/2)），生体認証による解除（[#3](https://github.com/shiftone-ai/plinth/issues/3)）は後続の機能として管理する．[iPadの対応方針](docs/design-docs/ipad-support.md) と [実機への配布](docs/distribution.md) を参照する．

## ビルドとテスト

プロジェクトのルートで実行する．Swift 6.4以上とmacOSのXcode環境を使用する．検査ツールの版はdevenvで固定している．direnvで `direnv allow` を実行するか，`devenv shell` に入ってから実行する．

```sh
just check   # 整形・静的検査と，警告をエラーとしたビルド・テスト
just fmt     # 整形
zsh scripts/build-app.sh
```

検証環境とテストの範囲は [開発と検証](docs/development.md) を参照する．

生成先は `.build/Plinth.app`．`--preview` を指定すると，Dock・メニューバー・アプリ切替の設定を変更せずに起動する．管理者解除のショートカットは `⌘ ⌥ ⇧ K`．通常モードの受け入れ試験は専用Macで行う．

## 開発資料

- [資料一覧](docs/index.md)
- [設計の入口](ARCHITECTURE.md)
- [設計書v0.2](docs/design-docs/macos-kiosk-design-v0.2.md)
- [実装規約](docs/rules/index.md)
- [エージェント向けの入口](AGENTS.md)
