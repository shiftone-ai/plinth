# App Review用メモの原稿

App Store Connectの各プラットフォームの「Notes」に入力する原稿．審査へ追加する前に，選択した候補ビルドで画面名と手順を再確認する．サインイン用の外部アカウントは不要．審査員がアプリ内で設定する管理者パスワードは，審査員自身が決める．

## iPhone・iPad版

Plinth displays an administrator-selected website for an exhibition. No account or external hardware is required for the basic path.

1. On the first settings screen, enter `https://shiftone-ai.github.io/plinth/demo/index.html` as the Start URL. Leave the exhibition destination set to this device.
2. Create an administrator passcode of at least eight characters, save the passcode and settings, then tap Start Exhibition.
3. The artwork fills the page. Tap “Next exhibit” to test navigation within the allowed origin; the link changes to “First exhibit” on the second page.
4. Tap the administrator control, enter the passcode you created, and return to settings. Restart the app to verify that it resumes the saved exhibition.

The sample site is maintained by the developer and requires no login. The app settings include Privacy Policy, Support and Licenses links. Web management is optional and off by default. It requires another browser on the same local network and uses HTTP, so test it only on an isolated network. Biometric unlock is optional on supported devices; the administrator passcode remains available. For an external display exhibition, a compatible iPhone or iPad, a display and a mouse are required. The available output route depends on the device and OS settings. External display and mouse behavior are outside the basic device-only path. Plinth does not prevent OS app switching.

The Settings collection is optional. After saving settings, enter a name and tap Save current settings. Select the saved entry, then tap Load into editor or Export this setting. iCloud sync is off by default. To test it, sign in to iCloud on two devices, turn on sync in Settings collection on each, then explicitly choose Share in iCloud for an entry. The administrator passcode is never part of an entry.

## Mac版

Plinth displays an administrator-selected website for an exhibition. No account or external display is required for the basic path.

1. Launch the app and enter `https://shiftone-ai.github.io/plinth/demo/index.html` as the Start URL. Choose the Mac's built-in display for the basic path.
2. Create an administrator passcode of at least eight characters, save the passcode and settings, then start the exhibition.
3. The artwork fills the page. Click “Next exhibit” to test navigation within the allowed origin; the link changes to “First exhibit” on the second page.
4. Use Command–Option–Shift–K to request administrator unlock, enter the passcode you created, and return to settings. Restart the app to verify that it resumes the saved exhibition.

The sample site is maintained by the developer and requires no login. The app settings include Privacy Policy, Support and Licenses links. Web management is optional and off by default. It requires another browser on the same local network and uses HTTP, so test it only on an isolated network. Biometric unlock is optional on supported Macs; the administrator passcode remains available. A second monitor is required only for external display output. Plinth does not prevent macOS app switching.

The macOS app needs `com.apple.security.network.server` for optional Web management. After creating the administrator passcode, turn on Allow web management in the Mac settings and save. The app listens for incoming TCP connections on port 47623 and shows its local network URL and QR code. Open that URL in a browser on the same isolated network and sign in with the administrator passcode to manage the exhibition. Turning off Allow web management and saving stops the listener. The app does not listen while this option is off.

The Settings collection is optional. After saving settings, enter a name and click Save current settings. Select the saved entry, then click Load into editor or Export this setting. iCloud sync is off by default. To test it, sign in to iCloud on two devices, turn on sync in Settings collection on each, then explicitly choose Share in iCloud for an entry. The administrator passcode is never part of an entry.

## 提出前の照合

- 手順は端末単体の候補ビルドで最初から最後まで操作する．画面名や初期値が異なれば，この原稿を修正する．
- 外部ディスプレイとマウスの説明は，候補の実機結果を付けて確認する．未確認の機種やOSへ対応を広げない．
- Web管理と生体認証の説明を，選択した候補の設定画面と照合する．基本手順では使わない．
- 審査連絡先の氏名・電話番号・メールはApp Store Connect内で担当者が確定する．公開リポジトリに非公開の連絡先を記録しない．
