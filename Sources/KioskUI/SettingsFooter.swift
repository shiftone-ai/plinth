import KioskLocalization
import KioskPresentation
import SwiftUI

struct SettingsFooter: View {
  let props: SettingsProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    HStack {
      #if os(macOS)
        Button(L10n.string("終了", locale: locale)) { send(.quit) }
      #endif
      Spacer()
      if props.saveFailed {
        Label(L10n.string("設定を保存できませんでした", locale: locale), systemImage: "exclamationmark.circle")
          .foregroundStyle(.red)
      }
      if props.saving { ProgressView().controlSize(.small) }
      Button(L10n.string("変更を破棄", locale: locale)) { send(.discard) }.disabled(props.saving)
      Button(L10n.string("設定を保存", locale: locale)) { send(.save) }.disabled(!props.canSave)
        .accessibilityIdentifier("save-profile")
      Button(L10n.string("展示を開始", locale: locale)) { send(.start) }.disabled(!props.canStart)
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("start-exhibition")
    }
    .padding()
  }
}
