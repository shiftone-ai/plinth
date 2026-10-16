import KioskLocalization
import KioskPresentation
import SwiftUI

public struct UnlockView: View {
  let props: UnlockProps
  let biometricHost: AnyView?
  let send: (UnlockIntent) -> Void
  @Environment(\.locale) private var locale
  @FocusState private var focused: Bool

  public init(
    props: UnlockProps, biometricHost: AnyView? = nil,
    send: @escaping (UnlockIntent) -> Void
  ) {
    self.props = props
    self.biometricHost = biometricHost
    self.send = send
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(L10n.string("Administrator unlock", locale: locale)).font(.title2)
      HStack(spacing: 8) {
        SecureField(
          L10n.string("Administrator password", locale: locale),
          text: Binding(
            get: { props.passcode }, set: { send(.editPasscode($0)) })
        )
        .focused($focused)
        .accessibilityIdentifier("unlock-passcode")
        .onSubmit { send(.submit) }
        .disabled(props.verifying)
        #if os(macOS)
          if props.biometricVerifying {
            if let biometricHost { biometricHost }
            Button {
              send(.cancelBiometricAuthentication)
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.string("Cancel", locale: locale))
            .accessibilityLabel(L10n.string("Cancel", locale: locale))
            .accessibilityIdentifier("cancel-biometric-unlock")
          } else if let label = props.biometricLabelKey {
            Button {
              send(.authenticateWithBiometrics)
            } label: {
              Image(systemName: "touchid")
                .font(.title2)
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(props.biometricVerifying)
            .help(L10n.string(label, locale: locale))
            .accessibilityLabel(L10n.string(label, locale: locale))
            .accessibilityIdentifier("verify-biometric")
          }
        #endif
      }
      if props.failedAttempts > 0 {
        Label(
          L10n.string("Incorrect administrator password", locale: locale),
          systemImage: "exclamationmark.circle"
        )
        .foregroundStyle(.red)
        .accessibilityIdentifier("incorrect-credential")
      }
      if props.cooldownRemaining > 0 {
        Label(L10n.string("Try again in 30 seconds", locale: locale), systemImage: "clock")
      }
      #if !os(macOS)
        if let label = props.biometricLabelKey {
          HStack {
            Button(L10n.string(label, locale: locale)) {
              send(.authenticateWithBiometrics)
            }
            .disabled(props.biometricVerifying)
            .accessibilityIdentifier("verify-biometric")
            if props.biometricVerifying {
              if let biometricHost { biometricHost } else { ProgressView().controlSize(.small) }
              Button(L10n.string("Cancel", locale: locale)) {
                send(.cancelBiometricAuthentication)
              }
              .accessibilityIdentifier("cancel-biometric-unlock")
            }
          }
        }
      #endif
      if props.biometricFailed {
        Label(
          L10n.string("Could not unlock with biometrics", locale: locale),
          systemImage: "exclamationmark.circle"
        )
        .foregroundStyle(.red)
        .accessibilityIdentifier("biometric-unlock-failed")
      }
      HStack {
        Button(L10n.string("Return to exhibition", locale: locale)) { send(.cancel) }
          .accessibilityIdentifier("cancel-unlock")
        Spacer()
        if props.verifying { ProgressView().controlSize(.small) }
        Button(L10n.string("Unlock", locale: locale)) { send(.submit) }
          .disabled(props.verifying || props.passcode.isEmpty)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("verify-passcode")
      }
    }
    .padding(28)
    .frame(maxWidth: 420)
    .padding(20)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .defaultFocus($focused, true)
  }
}
