# 翻訳

管理画面・解除画面・展示停止・Webからの管理画面の文言は [String Catalog](../../Sources/KioskLocalization/Localizable.xcstrings) で管理する．原文のキーは自然な英語とし，en・ja・ko・zh-Hansをすべて訳す．中国語は簡体字を対象とする．対応していない言語と欠けた訳は英語のキーを表示する．展示するWebコンテンツは対象外．この判断は [ADR](../adr/0001-localization.md) に記録した．

1. Viewの文言は英語のキーを `L10n.string("Save settings", locale: locale)` で取り，Viewの `@Environment(\.locale)` を渡す．package内のresource bundleを参照するため，アプリ本体のBundleには頼らない．
2. キーと各言語の訳をcatalogへ追加する．あいまいな語と補間値には翻訳者向けのcommentを付ける．Presenterは翻訳せず，入力エラーの英語キーをViewへ渡す．
3. `python3 scripts/check-localizations.py` は宣言した言語の欠訳と，コードにある未登録キーを検出する．`just lint` のSwiftLint規則はUIソースの日本語リテラルを検出する．新しい動的キーの供給元を増やすときは，checkerの参照元も追加する．
4. OSの言語と画面内の切替を実画面で確かめる．管理者パスワードと保存済み設定が切替・再起動後も使えること，未対応言語で英語に戻ることを確認する．

管理画面には日付表示がない．無操作時間は秒で入力し，解像度はピクセル数で表示する．数値入力の小数点は対象言語で `.` とする．
