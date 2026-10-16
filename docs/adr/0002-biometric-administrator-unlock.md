# ADR 0002: 管理者解除に使う生体認証の設定

## 決定

管理者パスワードを保存した端末でだけ，Touch IDまたはFace IDによる管理者解除を有効にできる．有効化の際は生体認証を一度成功させる．有効状態は現在の登録内容に結び付けた `.biometryCurrentSet` のKeychain項目で表し，Profile JSONには書かない．登録した指紋・顔が変わると項目が無効になる．

端末に登録されたすべての指紋・顔を使える人に管理画面を開く権限が生じる．この条件と，登録変更時に無効になることを管理画面に表示する．生体認証を解除画面で使う処理は #12・#13 で実装する．

## 理由

[AppleのHIG](https://developer.apple.com/design/human-interface-guidelines/managing-accounts) は，通常，アプリ固有の生体認証設定を避けるよう求めている．このアプリでは展示端末の生体認証登録者に管理者権限を与えるため，利用者が明示的に有効化する設定が必要になる．方式名は `LAContext.biometryType` で判定する．使えないときは未登録・ロックアウトなどの理由を示す．

[AppleのSecurity資料](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset) によると，`.biometryCurrentSet` の項目は指紋の追加・削除や顔の再登録で無効になる．独自に登録状態のハッシュを保存して比較しない．管理者パスワードのKeychain項目とは別の項目を使うため，パスワードの保存形式も変わらない．

RootのMediatorが有効化の可否と操作の寿命を裁定し，Effectが `LAContext` とKeychainを操作する．有効化中は展示開始を拒否する．利用者による認証の取消は設定を変えず，失敗表示も出さない．取消後の結果はoperation tokenで拒否し，Adapterは認証を無効化する．

## 確認範囲

生体認証付きKeychain項目にはMacでもData Protection Keychainが必要であることが[Appleの技術資料](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)に記されている．MacのData Protection Keychainのaccess groupは署名の権限から決まり，その権限にはprovisioning profileの許可が必要になる．Developer ID版に権限を設定し，配布物の検査でprofileの欠落を検出する．ad hoc署名の `build-app.sh` 版では有効化を保証できない．Developer ID版の実動作は署名済み配布物で確認する．iOSでは `NSFaceIDUsageDescription` を4言語で用意する．
