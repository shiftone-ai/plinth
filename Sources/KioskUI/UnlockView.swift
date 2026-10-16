import KioskLocalization
import KioskPresentation
import SwiftUI

public struct UnlockView: View {
  let props: UnlockProps
  let send: (UnlockIntent) -> Void
  @Environment(\.locale) private var locale
  @FocusState private var focused: Bool

  public init(props: UnlockProps, send: @escaping (UnlockIntent) -> Void) {
    self.props = props
    self.send = send
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(L10n.string("Administrator unlock", locale: locale)).font(.title2)
      SecureField(
        L10n.string("Administrator password", locale: locale),
        text: Binding(
          get: { props.passcode }, set: { send(.editPasscode($0)) })
      )
      .focused($focused)
      .accessibilityIdentifier("unlock-passcode")
      .onSubmit { send(.submit) }
      .disabled(props.verifying)
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
