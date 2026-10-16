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
        Button(L10n.string("Quit", locale: locale)) { send(.quit) }
      #endif
      Spacer()
      if props.saveFailed {
        Label(
          L10n.string("Could not save settings", locale: locale),
          systemImage: "exclamationmark.circle"
        )
        .foregroundStyle(.red)
      }
      if props.saving { ProgressView().controlSize(.small) }
      Button(L10n.string("Discard changes", locale: locale)) { send(.discard) }.disabled(
        props.saving)
      Button(L10n.string("Save settings", locale: locale)) { send(.save) }.disabled(!props.canSave)
        .accessibilityIdentifier("save-profile")
      Button(L10n.string("Start exhibition", locale: locale)) { send(.start) }.disabled(
        !props.canStart
      )
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("start-exhibition")
    }
    .padding()
  }
}
