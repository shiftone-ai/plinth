import KioskLocalization
import KioskPresentation
import SwiftUI

struct CatalogImportPassphraseSheet: View {
  let props: CatalogProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if let url = props.importFileURL {
            Label(url.lastPathComponent, systemImage: "doc")
          }
          SecureField(
            L10n.string("File passphrase", locale: locale),
            text: Binding(
              get: { props.passphrase }, set: { send(.editCatalogPassphrase($0)) })
          )
          .privacySensitive()
          .accessibilityIdentifier("catalog-import-passphrase")
        }
        if props.importFailed {
          Section {
            Label(
              L10n.string("Could not import settings", locale: locale),
              systemImage: "exclamationmark.circle"
            ).foregroundStyle(.red)
          }
        }
        if props.importing {
          Section { ProgressView() }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(L10n.string("Open encrypted file", locale: locale))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.string("Cancel", locale: locale)) { send(.cancelCatalogImport) }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.string("Review settings", locale: locale)) {
            if let url = props.importFileURL { send(.importCatalogFile(url)) }
          }
          .disabled(!props.canImport)
          .accessibilityIdentifier("catalog-import-review")
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 280)
    #endif
  }
}
