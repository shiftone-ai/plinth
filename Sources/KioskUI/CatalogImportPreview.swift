import KioskCore
import KioskLocalization
import KioskPresentation
import SwiftUI

struct CatalogImportPreview: View {
  let entries: [CatalogEntry]
  let canConfirm: Bool
  let matches: [UUID: CatalogImportMatch]
  let contents: [UUID: [CatalogDifference]]
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.string("Review imported settings", locale: locale)) {
          ForEach(entries) { entry in
            VStack(alignment: .leading, spacing: 3) {
              Text(entry.name)
              Text(verbatim: entry.snapshot.startURL)
                .font(.caption).foregroundStyle(.secondary)
              if let match = matches[entry.id] {
                matchText(match).font(.caption).foregroundStyle(.secondary)
              }
              DisclosureGroup(L10n.string("Contents", locale: locale)) {
                ForEach(contents[entry.id] ?? []) { value in
                  HStack(alignment: .top) {
                    Text(L10n.string(value.labelKey, locale: locale))
                    Spacer()
                    displayValue(value.selected)
                      .multilineTextAlignment(.trailing)
                  }
                }
              }
            }
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(L10n.string("Import settings", locale: locale))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.string("Cancel", locale: locale)) { send(.cancelCatalogImport) }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.string("Add to collection", locale: locale)) {
            send(.confirmCatalogImport)
          }
          .disabled(!canConfirm)
          .accessibilityIdentifier("catalog-import-confirm")
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 360)
    #endif
  }

  private func matchText(_ match: CatalogImportMatch) -> Text {
    switch match {
    case .alreadyPresent:
      Text(L10n.string("Already in this collection; skipped", locale: locale))
    case .separateCopy:
      Text(L10n.string("Changed copy; added separately", locale: locale))
    case .sameName:
      Text(L10n.string("Name already in this collection", locale: locale))
    }
  }

  @ViewBuilder
  private func displayValue(_ value: CatalogDisplayValue) -> some View {
    switch value {
    case .text(let text): Text(verbatim: text)
    case .localized(let key): Text(L10n.string(key, locale: locale))
    case .absent: Text(verbatim: "—")
    }
  }
}
