import KioskLocalization
import SwiftUI

struct LicensesView: View {
  @Environment(\.locale) private var locale
  let onClose: () -> Void

  var body: some View {
    NavigationStack {
      ContentUnavailableView {
        Label(
          L10n.string("No third-party licenses", locale: locale), systemImage: "doc.text"
        )
        .accessibilityIdentifier("license-empty")
      }
      .navigationTitle(L10n.string("Licenses", locale: locale))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.string("Close", locale: locale), action: onClose)
            .accessibilityIdentifier("license-close")
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 300)
    #endif
  }
}
