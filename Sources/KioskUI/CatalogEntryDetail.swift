import KioskCore
import KioskLocalization
import KioskPresentation
import SwiftUI

struct CatalogEntryDetail: View {
  let entry: CatalogEntry
  let props: CatalogProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(
            L10n.string("Name", locale: locale),
            text: Binding(
              get: { props.selectedNameDraft },
              set: { send(.editCatalogSelectionName($0)) })
          )
          .accessibilityIdentifier("catalog-selected-name")
          Button(L10n.string("Rename", locale: locale)) {
            send(.renameCatalog(id: entry.id, name: props.selectedNameDraft))
          }
          .disabled(!props.canRename)
          .accessibilityIdentifier("catalog-rename")
          Button(L10n.string("Update from saved settings", locale: locale)) {
            send(.updateCatalog(entry.id))
          }
          .disabled(!props.canUpdate)
          .accessibilityIdentifier("catalog-update")
          if props.renameTooLarge || props.updateTooLarge {
            iCloudSizeWarning
          }
        }
        Section(L10n.string("Contents", locale: locale)) {
          ForEach(props.contents) { value in
            HStack(alignment: .top) {
              Text(L10n.string(value.labelKey, locale: locale))
              Spacer()
              comparisonValue(value.selected)
                .multilineTextAlignment(.trailing)
            }
          }
        }
        if !props.differences.isEmpty {
          Section(L10n.string("Changes", locale: locale)) {
            ForEach(props.differences) { difference in
              VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(difference.labelKey, locale: locale)).font(.headline)
                HStack(alignment: .top, spacing: 12) {
                  comparisonValue(difference.current)
                    .frame(maxWidth: .infinity, alignment: .leading)
                  Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                  comparisonValue(difference.selected)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .accessibilityElement(children: .combine)
            }
          }
        }
        Section {
          if entry.scope == .device {
            Button(L10n.string("Share in iCloud", locale: locale)) {
              send(.requestCatalogShare(entry.id))
            }
            .disabled(!props.canShare)
            .accessibilityIdentifier("catalog-share")
            if props.shareTooLarge {
              iCloudSizeWarning
            }
          } else {
            Label(L10n.string("Shared in iCloud", locale: locale), systemImage: "icloud")
          }
          Button(L10n.string("Load into editor", locale: locale)) {
            send(.applyCatalogSelection)
          }
          .disabled(!props.canApply)
          .accessibilityIdentifier("catalog-apply")
          Button(L10n.string("Hide on this device", locale: locale)) {
            send(.setCatalogVisibility(id: entry.id, visible: false))
            send(.dismissCatalogSelection)
          }
          .disabled(!props.canManage)
          Button(L10n.string("Remove from collection", locale: locale), role: .destructive) {
            send(.promptCatalogRemoval(entry.id))
          }
          .disabled(!props.canManage || props.conflicts.contains(where: { $0.id == entry.id }))
          .accessibilityIdentifier("catalog-remove")
        }
        Section(L10n.string("File", locale: locale)) {
          SecureField(
            L10n.string("File passphrase", locale: locale),
            text: Binding(
              get: { props.passphrase }, set: { send(.editCatalogPassphrase($0)) })
          )
          .privacySensitive()
          SecureField(
            L10n.string("Confirm passphrase for export", locale: locale),
            text: Binding(
              get: { props.confirmPassphrase },
              set: { send(.editCatalogConfirmPassphrase($0)) })
          )
          .privacySensitive()
          Button(L10n.string("Export this setting", locale: locale)) {
            send(.dismissCatalogSelection)
            send(.exportCatalog([entry.id]))
          }
          .disabled(!props.canExport)
          .accessibilityIdentifier("catalog-export-item")
        }
      }
      .navigationTitle(entry.name)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.string("Close", locale: locale)) { send(.dismissCatalogSelection) }
        }
      }
      .confirmationDialog(
        L10n.string("Rename shared setting?", locale: locale),
        isPresented: Binding(
          get: { props.renameCandidate?.id == entry.id },
          set: { if !$0 { send(.cancelCatalogRename) } }
        ), titleVisibility: .visible
      ) {
        Button(L10n.string("Rename on all devices", locale: locale)) {
          send(.confirmCatalogRename(entry.id))
        }
      } message: {
        Text(L10n.string("The new name will appear on other devices.", locale: locale))
      }
      .confirmationDialog(
        L10n.string("Update shared setting?", locale: locale),
        isPresented: Binding(
          get: { props.updateCandidateID == entry.id },
          set: { if !$0 { send(.cancelCatalogUpdate) } }
        ), titleVisibility: .visible
      ) {
        Button(L10n.string("Update on all devices", locale: locale)) {
          send(.confirmCatalogUpdate(entry.id))
        }
      } message: {
        Text(
          L10n.string(
            "The saved settings will replace this shared item on other devices.", locale: locale))
      }
      .confirmationDialog(
        L10n.string("Share this setting in iCloud?", locale: locale),
        isPresented: Binding(
          get: { props.shareCandidate?.id == entry.id },
          set: { if !$0 { send(.cancelCatalogShare) } }
        ), titleVisibility: .visible
      ) {
        Button(L10n.string("Share setting", locale: locale)) {
          send(.confirmCatalogShare(entry.id))
        }
      } message: {
        Text(
          L10n.string(
            "The contents shown above will reach devices using this Apple Account.", locale: locale)
        )
      }
      .confirmationDialog(
        L10n.string("Remove from collection", locale: locale),
        isPresented: Binding(
          get: { props.removalCandidate?.id == entry.id },
          set: { if !$0 { send(.cancelCatalogRemoval) } }
        ), titleVisibility: .visible
      ) {
        Button(L10n.string("Remove", locale: locale), role: .destructive) {
          send(.confirmCatalogRemoval(entry.id))
          send(.dismissCatalogSelection)
        }
      } message: {
        if entry.scope == .iCloud {
          Text(
            L10n.string("This removes the setting from other devices' collections.", locale: locale)
          )
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 400, minHeight: 400)
    #endif
  }

  @ViewBuilder
  private func comparisonValue(_ value: CatalogDisplayValue) -> some View {
    switch value {
    case .text(let text): Text(verbatim: text)
    case .localized(let key): Text(L10n.string(key, locale: locale))
    case .absent: Text(verbatim: "—")
    }
  }

  private var iCloudSizeWarning: some View {
    Label(
      L10n.string("Too much content for iCloud", locale: locale),
      systemImage: "exclamationmark.triangle"
    )
    .foregroundStyle(.secondary)
  }
}
