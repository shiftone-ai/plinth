# App Store掲載文の原稿

Issue #28の公開候補に使う原稿．iOSとmacOSはApp Store Connectの同じアプリ記録にある別バージョン．説明と画像はプラットフォームごとに登録する．審査提出前に，実際に選ぶビルドの機能と照合する．

## 共通情報

| 項目 | 原稿・確認結果 |
| --- | --- |
| アプリ名 | Plinth Kiosk（現在の日本語登録名） |
| サブタイトル | 日本語：Webコンテンツを展示／英語：Web content for exhibitions／韓国語：웹 콘텐츠 전시／簡体字中国語：展示网页内容 |
| カテゴリ | ユーティリティ．App Store Connectに保存済み |
| サポートURL | 言語別の `https://shiftone-ai.github.io/plinth/{lang}/support.html` |
| プライバシーURL | 言語別の `https://shiftone-ai.github.io/plinth/{lang}/privacy.html` |
| アイコン | `Resources/Assets.xcassets` のアプリアイコンを候補ビルドと照合する |
| Promotional Text | 空欄．更新なしで掲載文を固定できる状態にする |

Web管理は統合した`main`に含まれ，以下の説明をApp Store Connectへ保存した．生体認証は対象ビルドでの再検証まで掲載文には含めない．利用者の指定に従い，無料・全175地域をApp Store Connectに保存した．

## iPhone・iPad版

### 日本語

**説明**

Plinth Kioskは，管理者が選んだWebページをiPhoneやiPadで展示するアプリです．端末本体に表示するほか，対応する端末では外部ディスプレイにも表示できます．

開始URL，移動を許すサイト，スクロールやドラッグ，無操作時の復帰，Cookieなどの保持方法を設定できます．管理画面への切り替えは管理者パスワードで保護します．

端末でWeb管理を有効にすると，同じローカルネットワークのブラウザから設定できます．通信は暗号化されないHTTPを使うため，隔離したネットワークで運用してください．

外部ディスプレイでの展示には，対応する画面とマウスが必要です．端末とOSの設定によって利用できる表示方式が異なります．PlinthはOSのアプリ切り替えを禁止しません．端末を1つのアプリに限定する運用は，端末側で別途設定してください．

**キーワード**：キオスク,展示,Web,ディスプレイ,デジタルサイネージ

### English

**Description**

Plinth Kiosk displays a web page chosen by an administrator on iPhone or iPad. Show it on the device, or on an external display when the device supports that setup.

Set a starting URL, allowed destinations, scrolling and dragging, idle reset, and how cookies and site data are kept. An administrator passcode protects access to settings.

Enable web management on the device to change settings from a browser on the same local network. It uses unencrypted HTTP, so use a network separated from untrusted devices.

External display exhibitions require a compatible display and a mouse. Available display modes depend on the device and OS settings. Plinth does not prevent switching to other apps. Configure device restrictions separately if your installation needs them.

**Keywords**: kiosk,exhibition,web display,digital signage,interactive display

### 한국어

**설명**

Plinth Kiosk는 관리자가 선택한 웹페이지를 iPhone 또는 iPad에 전시하는 앱입니다. 기기 화면에 표시하거나, 지원되는 기기에서는 외부 디스플레이에 표시할 수 있습니다.

시작 URL, 이동할 수 있는 사이트, 스크롤과 드래그, 유휴 상태에서의 복귀, 쿠키와 사이트 데이터 보관 방식을 설정할 수 있습니다. 관리자 암호로 설정 화면을 보호합니다.

기기에서 웹 관리를 켜면 같은 로컬 네트워크의 브라우저에서 설정을 변경할 수 있습니다. 암호화되지 않은 HTTP를 사용하므로 신뢰할 수 없는 기기와 네트워크를 분리하세요.

외부 디스플레이 전시에는 호환되는 화면과 마우스가 필요합니다. 사용할 수 있는 표시 방식은 기기와 OS 설정에 따라 다릅니다. Plinth는 다른 앱으로 전환하는 것을 막지 않습니다. 기기를 한 앱으로 제한하려면 기기에서 별도로 설정하세요.

**키워드**: 키오스크,전시,웹,디스플레이,디지털 사이니지

### 简体中文

**描述**

```text
Plinth Kiosk 可以在 iPhone 或 iPad 上展示管理员选择的网页。你可以在设备屏幕上展示；使用受支持的设备时，也可以在外接显示器上展示。

你可以设置起始 URL、允许访问的网站、滚动和拖动、闲置后恢复，以及 Cookie 和网站数据的保留方式。管理员密码用于保护设置页面。

在设备上启用网页管理后，可以从同一局域网内的浏览器更改设置。该功能使用未加密的 HTTP，请将展示网络与不可信的设备隔离。

使用外接显示器展示需要兼容的显示器和鼠标。可用的显示方式取决于设备及系统设置。Plinth 不会阻止用户切换到其他应用；如需将设备限定在一个应用中，请另行配置设备限制。
```

**关键词**：信息亭,展览,网页,显示器,数字标牌

## Mac専用版

### 日本語

**説明**

Plinth Kioskは，管理者が選んだWebページをMacで展示するアプリです．本体の画面や外部ディスプレイを選び，全画面またはウィンドウで表示できます．

開始URL，移動を許すサイト，スクロールやドラッグ，無操作時の復帰，Cookieなどの保持方法を設定できます．管理画面への切り替えは管理者パスワードで保護します．

MacでWeb管理を有効にすると，同じローカルネットワークのブラウザから設定できます．通信は暗号化されないHTTPを使うため，隔離したネットワークで運用してください．

外部ディスプレイを使う場合は，Macに対応する画面を接続してください．PlinthはmacOSのアプリ切り替えや端末の設定変更を禁止しません．端末を1つのアプリに限定する運用は，Mac側で別途設定してください．

**キーワード**：キオスク,展示,Web,Mac,ディスプレイ,デジタルサイネージ

### English

**Description**

Plinth Kiosk displays a web page chosen by an administrator on Mac. Choose the built-in or an external display, and present it full screen or in a window.

Set a starting URL, allowed destinations, scrolling and dragging, idle reset, and how cookies and site data are kept. An administrator passcode protects access to settings.

Enable web management on the Mac to change settings from a browser on the same local network. It uses unencrypted HTTP, so use a network separated from untrusted devices.

Connect a compatible display if you use external output. Plinth does not prevent macOS app switching or changes to device settings. Configure device restrictions separately if your installation needs them.

**Keywords**: kiosk,exhibition,web display,Mac,digital signage

### 한국어

**설명**

Plinth Kiosk는 관리자가 선택한 웹페이지를 Mac에 전시하는 앱입니다. 내장 화면이나 외부 디스플레이를 선택하고 전체 화면 또는 창에서 표시할 수 있습니다.

시작 URL, 이동할 수 있는 사이트, 스크롤과 드래그, 유휴 상태에서의 복귀, 쿠키와 사이트 데이터 보관 방식을 설정할 수 있습니다. 관리자 암호로 설정 화면을 보호합니다.

Mac에서 웹 관리를 켜면 같은 로컬 네트워크의 브라우저에서 설정을 변경할 수 있습니다. 암호화되지 않은 HTTP를 사용하므로 신뢰할 수 없는 기기와 네트워크를 분리하세요.

외부 화면을 사용하려면 Mac과 호환되는 디스플레이를 연결하세요. Plinth는 macOS의 앱 전환이나 기기 설정 변경을 막지 않습니다. 기기를 한 앱으로 제한하려면 Mac에서 별도로 설정하세요.

**키워드**: 키오스크,전시,웹,Mac,디스플레이,디지털 사이니지

### 简体中文

**描述**

```text
Plinth Kiosk 可以在 Mac 上展示管理员选择的网页。你可以选择内置屏幕或外接显示器，并以全屏或窗口方式展示。

你可以设置起始 URL、允许访问的网站、滚动和拖动、闲置后恢复，以及 Cookie 和网站数据的保留方式。管理员密码用于保护设置页面。

在 Mac 上启用网页管理后，可以从同一局域网内的浏览器更改设置。该功能使用未加密的 HTTP，请将展示网络与不可信的设备隔离。

如需使用外接屏幕，请连接与 Mac 兼容的显示器。Plinth 不会阻止 macOS 的应用切换或设备设置更改；如需将设备限定在一个应用中，请另行配置 Mac 限制。
```

**关键词**：信息亭,展览,网页,Mac,显示器,数字标牌
