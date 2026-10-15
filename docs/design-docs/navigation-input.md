# ドメインの入力と拒否時の動作

閲覧先にはドメインまたはURLを入力する．サブドメインを含めるときは `*.` を使う．入力をoriginへ正規化して評価し，部分文字列では判定しない．

| 入力例 | 評価範囲 |
| --- | --- |
| `example.co.jp` | HTTPS・443番のこのドメイン |
| `*.example.co.jp` | HTTPS・443番のこのドメインと全サブドメイン |
| `events.example.co.jp` | HTTPS・443番のこのサブドメインだけ |
| `https://*.example.co.jp:8443` | HTTPS・8443番のこのドメインと全サブドメイン |
| `http://example.com` | HTTP・80番．別途「HTTPを許可」が必要 |

URLのパスは制限条件に含めない．`https://example.com/path` を入力しても，対象は同じorigin全体になる．IPアドレスのワイルドカードは拒否する．旧設定のサブドメイン指定は読み込み時に `*.` の入力へ投影し，編集した文字列をMediatorが解析する．

設定画面の「許可リスト」では，開始URLのoriginを自動で許可する．鍵の付いた行へ表示し，その行は編集・削除できない．追加で許可するドメインだけを入力する．開始URLを変えると自動の許可先も変わり，同じoriginのほかのページも開ける．自動の行は保存するルールへ重複して書き込まず，明示的に追加したルールは保持する．

「拒否リスト」は一致する主ページを拒否し，開始URLも例外にしない．画像などの埋め込み資源はこのoriginルールの対象外．TLS検証はWebKitに任せ，証明書エラーを迂回しない．

自動許可でもHTTPの許可設定，危険なscheme，資格情報付きURLと壊れたルールの検証を省略しない．サブドメインや異なるport，リダイレクト先を自動で追加しない．

通常の操作で許可されない主ページへ移動すると，WebKitのnavigationをcancelして現在のページに留まる．別の警告バナーは表示しない．開始ページや復帰先のリダイレクトが拒否先へ進む場合は展示を停止し，その拒否に対して再試行しない．

`*.example.co.jp` は `https://events.example.co.jp/exhibitions/1` を許可する．`example.co.jp.attacker.invalid` と `notexample.co.jp` は含めない．期待値付きのケースは `Tests/KioskCoreTests/Policies/OriginRuleDraftTests.swift` にある．
