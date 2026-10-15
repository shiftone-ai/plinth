import KioskPresentation
import SwiftUI

public struct UnlockView: View {
  let props: UnlockProps
  let send: (UnlockIntent) -> Void
  @FocusState private var focused: Bool

  public init(props: UnlockProps, send: @escaping (UnlockIntent) -> Void) {
    self.props = props
    self.send = send
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("管理者解除").font(.title2)
      SecureField(
        "パスコード",
        text: Binding(
          get: { props.passcode }, set: { send(.editPasscode($0)) })
      )
      .focused($focused)
      .accessibilityIdentifier("unlock-passcode")
      .onSubmit { send(.submit) }
      .disabled(props.verifying)
      if props.failedAttempts > 0 {
        Label("パスコードが一致しません", systemImage: "exclamationmark.circle")
          .foregroundStyle(.red)
      }
      if props.cooldownRemaining > 0 {
        Label("30秒後にもう一度入力してください", systemImage: "clock")
      }
      HStack {
        Button("展示に戻る") { send(.cancel) }
          .accessibilityIdentifier("cancel-unlock")
        Spacer()
        if props.verifying { ProgressView().controlSize(.small) }
        Button("解除") { send(.submit) }
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
