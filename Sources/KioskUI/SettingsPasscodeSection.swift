import KioskLocalization
import KioskPresentation
import SwiftUI

struct SettingsPasscodeSection: View {
  let props: SettingsProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale
  @FocusState private var focused: Bool

  var body: some View {
    Section(L10n.string("Administrator", locale: locale)) {
      SecureField(
        L10n.string("Administrator password", locale: locale),
        text: Binding(get: { props.passcode }, set: { send(.editPasscode($0)) })
      )
      .accessibilityIdentifier("setup-passcode")
      .focused($focused)
      .submitLabel(.done)
      .onSubmit { focused = false }
      Text(L10n.string("8 characters or more", locale: locale)).font(.caption)
        .foregroundStyle(.secondary)
      Button(
        props.credentialsConfigured
          ? L10n.string("Change administrator password", locale: locale)
          : L10n.string("Save administrator password", locale: locale)
      ) {
        send(.configurePasscode)
      }
      .disabled(props.passcode.count < 8 || props.configuringCredential)
      .accessibilityIdentifier("save-passcode")
      if props.credentialConfigurationFailed {
        Label(
          L10n.string("Could not save administrator password", locale: locale),
          systemImage: "exclamationmark.circle"
        )
        .foregroundStyle(.red)
      }
      Toggle(
        L10n.string(props.biometricLabelKey, locale: locale),
        isOn: Binding(
          get: { props.biometricEnabled },
          set: { send(.changeBiometricUnlock($0)) })
      )
      .disabled(!props.canChangeBiometric)
      .accessibilityIdentifier("biometric-unlock")
      if let reason = props.biometricUnavailableKey {
        Text(L10n.string(reason, locale: locale)).font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("biometric-unavailable")
      }
      Text(
        L10n.string(
          "Everyone with a registered fingerprint or face on this device can open administrator settings. Changes to enrollment turn this off.",
          locale: locale)
      )
      .font(.caption).foregroundStyle(.secondary)
      if props.biometricChanging {
        HStack {
          ProgressView().controlSize(.small)
          Button(L10n.string("Cancel", locale: locale)) { send(.cancelBiometricChange) }
            .accessibilityIdentifier("cancel-biometric-change")
        }
      }
      if props.biometricChangeFailed {
        Label(
          L10n.string("Could not change biometric unlock", locale: locale),
          systemImage: "exclamationmark.circle"
        )
        .foregroundStyle(.red)
        .accessibilityIdentifier("biometric-change-failed")
      }
      #if os(macOS)
        LabeledContent(L10n.string("Administrator unlock", locale: locale), value: "⌘ ⌥ ⇧ K")
      #endif
    }
  }
}
