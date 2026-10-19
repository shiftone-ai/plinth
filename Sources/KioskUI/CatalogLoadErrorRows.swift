import KioskLocalization
import KioskPresentation
import SwiftUI

struct CatalogLoadErrorRows: View {
  let corrupt: Bool
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    Group {
      HStack {
        Label(
          L10n.string("Could not open settings collection", locale: locale),
          systemImage: "exclamationmark.circle"
        ).foregroundStyle(.red)
        Spacer()
        Button(L10n.string("Try again", locale: locale)) { send(.retryCatalogLoad) }
      }
      if corrupt {
        Button(L10n.string("Start a new collection", locale: locale)) {
          send(.requestCatalogRecovery)
        }
        .accessibilityIdentifier("catalog-recover")
      }
    }
  }
}
