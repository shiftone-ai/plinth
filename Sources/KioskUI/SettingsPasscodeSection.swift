import KioskLocalization
import KioskPresentation
import SwiftUI

struct SettingsPasscodeSection: View {
  let props: SettingsProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale
  @FocusState private var focused: Bool

  var body: some View {
    Section(L10n.string("管理者", locale: locale)) {
      SecureField(
        L10n.string("新しいパスコード（8文字以上）", locale: locale),
        text: Binding(get: { props.passcode }, set: { send(.editPasscode($0)) })
      )
      .accessibilityIdentifier("setup-passcode")
      .focused($focused)
      .submitLabel(.done)
      .onSubmit { focused = false }
      Button(
        props.credentialsConfigured
          ? L10n.string("パスコードを変更", locale: locale)
          : L10n.string("パスコードを保存", locale: locale)
      ) {
        send(.configurePasscode)
      }
      .disabled(props.passcode.count < 8 || props.configuringCredential)
      .accessibilityIdentifier("save-passcode")
      if props.credentialConfigurationFailed {
        Label(
          L10n.string("パスコードを保存できませんでした", locale: locale),
          systemImage: "exclamationmark.circle"
        )
        .foregroundStyle(.red)
      }
      #if os(macOS)
        LabeledContent(L10n.string("管理者解除", locale: locale), value: "⌘ ⌥ ⇧ K")
      #endif
    }
  }
}
