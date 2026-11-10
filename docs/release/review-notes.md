# App Review用メモの原稿

App Store Connectの各プラットフォームの「Notes」に入力する原稿．審査へ追加する前に，選択した候補ビルドで画面名と手順を再確認する．サインイン用の外部アカウントは不要．審査員がアプリ内で設定する管理者パスワードは，審査員自身が決める．

## iPhone・iPad版

Plinth displays an administrator-selected website for an exhibition. No account or external hardware is required for the basic path.

Business model: Plinth is free. It has no store, checkout, paid content, subscriptions, license keys, or paid feature unlocks. The administrator passcode protects local settings and is created in the app at no charge. There is no Plinth account registration. Optional iCloud sync uses the user's existing Apple account. Administrators choose their own websites; Plinth does not sell or unlock access to them. The sample below is free and requires no login.

1. On the first settings screen, enter `https://shiftone-ai.github.io/plinth/demo/index.html` as the Start URL. Leave the exhibition destination set to this device.
2. Create an administrator passcode of at least eight characters, save the passcode and settings, then tap Start Exhibition.
3. The artwork fills the page. Tap “Next exhibit” to test navigation within the allowed origin; the link changes to “First exhibit” on the second page.
4. Tap the administrator control, enter the passcode you created, and return to settings. Restart the app to verify that it resumes the saved exhibition.

The sample site is maintained by the developer and requires no login. The app settings include Privacy Policy, Support and Licenses links. Web management is optional and off by default. It requires another browser on the same local network and uses HTTP, so test it only on an isolated network. Biometric unlock is optional on supported devices; the administrator passcode remains available. For an external display exhibition, a compatible iPhone or iPad, a display and a mouse are required. The available output route depends on the device and OS settings. External display and mouse behavior are outside the basic device-only path. Plinth does not prevent OS app switching.

The Settings collection is optional. After saving settings, enter a name and tap Save current settings. Select the saved entry, then tap Load into editor or Export this setting. iCloud sync is off by default. To test it, sign in to iCloud on two devices, turn on sync in Settings collection on each, then explicitly choose Share in iCloud for an entry. The administrator passcode is never part of an entry.

## Mac版

Plinth displays an administrator-selected website for an exhibition. No account or external display is required for the basic path.

Business model: Plinth is free. It has no store, checkout, paid content, subscriptions, license keys, or paid feature unlocks. The administrator passcode protects local settings and is created in the app at no charge. There is no Plinth account registration. Optional iCloud sync uses the user's existing Apple account. Administrators choose their own websites; Plinth does not sell or unlock access to them. The sample below is free and requires no login.

1. Launch the app and enter `https://shiftone-ai.github.io/plinth/demo/index.html` as the Start URL. In Output, choose Fixed full screen and the built-in display, or your single display. Create a passcode of at least eight characters, save the passcode and settings, then start the exhibition.
2. Click Next exhibit to navigate within the allowed origin; First exhibit returns to the starting page. The animation can be paused with its on-page control.
3. Press Command-Option-Shift-K, enter the passcode you created, and return to settings. Restart the app to verify that it resumes the saved exhibition. Use the same shortcut and passcode to leave it again.
4. To compare output modes, choose Window in Output, save settings, and start the exhibition. The window can be moved and resized. Use Command-Option-Shift-K and your passcode to return to settings.

Fixed full screen intentionally hides the Dock and menu bar, disables Command-Tab app switching, covers other displays in black, and confines the pointer to the exhibition display. Successful administrator unlock releases these restrictions. Window mode leaves the Dock, menu bar, and Command-Tab available. Quit and window-close requests are refused during an exhibition; unlock first to exit. Launch normally for review. The documented --preview command-line option disables kiosk OS presentation for development/testing; it does not unlock additional features or depend on a reviewer account.

Web management is optional and off by default. After saving a passcode, turn on Allow web management and save settings. The app uses `com.apple.security.network.server` to listen on TCP port 47623 and displays a local network URL and QR code. From another browser on the same isolated network, open that URL and sign in with your administrator passcode. You can edit and save settings, start, restart, stop, and resume the exhibition. Disable Allow web management on the Mac and save to stop the listener. This feature uses unencrypted HTTP.

Biometric unlock is optional on supported Macs. Enable it in Administrator, complete the system authentication, start an exhibition, then press Command-Option-Shift-K and choose the biometric control. The passcode remains available on Macs without biometrics.

Settings collection is optional. After saving settings, enter a name and click Save current settings. Select the entry and choose Load into editor or Export this setting. Export collection and Import file transfer encrypted settings files using a file passphrase. This passphrase does not unlock paid features. The administrator passcode is never included in an entry or exported file.

iCloud sync is off by default. Sign in to iCloud on two devices, choose Turn on sync in Settings collection on each, then choose Share in iCloud for an entry. This synchronizes settings, not a paid content catalog.

The settings screen also exposes allowed destinations, HTTP permission, scrolling and dragging, idle return, and cookie/site-data retention. Privacy Policy, Support, and Licenses are available in settings. A second monitor is required only to test external display output.

## 提出前の照合

- 手順は端末単体の候補ビルドで最初から最後まで操作する．画面名や初期値が異なれば，この原稿を修正する．
- 外部ディスプレイとマウスの説明は，候補の実機結果を付けて確認する．未確認の機種やOSへ対応を広げない．
- Web管理と生体認証の説明を，選択した候補の設定画面と照合する．基本手順では使わない．
- 審査連絡先の氏名・電話番号・メールはApp Store Connect内で担当者が確定する．公開リポジトリに非公開の連絡先を記録しない．
