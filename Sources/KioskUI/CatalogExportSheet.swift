import KioskLocalization
import KioskPresentation
import SwiftUI

struct CatalogExportSheet: View {
  let props: CatalogProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField(
            L10n.string("File passphrase", locale: locale),
            text: Binding(
              get: { props.passphrase }, set: { send(.editCatalogPassphrase($0)) })
          )
          .privacySensitive()
          .accessibilityIdentifier("catalog-export-passphrase")
          SecureField(
            L10n.string("Confirm passphrase for export", locale: locale),
            text: Binding(
              get: { props.confirmPassphrase },
              set: { send(.editCatalogConfirmPassphrase($0)) })
          )
          .privacySensitive()
          .accessibilityIdentifier("catalog-export-confirm-passphrase")
          if !props.passphrase.isEmpty && props.passphrase.count < 16 {
            Label(
              L10n.string("Use at least 16 characters", locale: locale),
              systemImage: "info.circle"
            ).foregroundStyle(.secondary)
          }
          Label(
            L10n.string("A lost passphrase cannot be recovered", locale: locale),
            systemImage: "key"
          ).foregroundStyle(.secondary)
          Text(L10n.string("A weak passphrase may be guessed", locale: locale))
            .font(.caption).foregroundStyle(.secondary)
        }
        if props.exportFailed {
          Section {
            Label(
              L10n.string("Could not export settings", locale: locale),
              systemImage: "exclamationmark.circle"
            ).foregroundStyle(.red)
          }
        }
        if props.exporting {
          Section { ProgressView() }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(L10n.string("Export collection", locale: locale))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.string("Cancel", locale: locale)) { send(.cancelCatalogExport) }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.string("Save encrypted file", locale: locale)) {
            send(.exportCatalog(props.exportSelection ?? []))
          }
          .disabled(!props.canExport)
          .accessibilityIdentifier("catalog-export-save-file")
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 280)
    #endif
  }
}
