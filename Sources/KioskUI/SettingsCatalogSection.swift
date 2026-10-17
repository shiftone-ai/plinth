import KioskLocalization
import KioskPresentation
import SwiftUI

struct SettingsCatalogSection: View {
  let props: CatalogProps
  let send: (SettingsIntent) -> Void
  let openImporter: () -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    Group {
      Section(L10n.string("Settings collection", locale: locale)) {
        if props.loaded {
          HStack {
            TextField(
              L10n.string("Name", locale: locale),
              text: Binding(
                get: { props.nameDraft }, set: { send(.editCatalogName($0)) })
            )
            .accessibilityIdentifier("catalog-name")
            Button(L10n.string("Save current settings", locale: locale), systemImage: "plus") {
              send(.registerCatalog(props.nameDraft))
            }
            .disabled(!props.canRegister)
            .accessibilityIdentifier("catalog-register")
          }
          ForEach(props.visibleEntries) { entry in
            Button {
              send(.selectCatalog(entry.id))
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                Text(verbatim: entry.snapshot.startURL)
                  .font(.caption).foregroundStyle(.secondary).lineLimit(1)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .disabled(!props.canManage)
            .accessibilityIdentifier("catalog-entry-\(entry.id.uuidString)")
          }
          if !props.hiddenEntries.isEmpty {
            Text(L10n.string("Available", locale: locale))
              .font(.caption).foregroundStyle(.secondary)
            ForEach(props.hiddenEntries) { entry in
              HStack {
                Text(entry.name)
                Spacer()
                Button(L10n.string("Show on this device", locale: locale)) {
                  send(.setCatalogVisibility(id: entry.id, visible: true))
                }
                .disabled(!props.canManage)
                .accessibilityIdentifier("catalog-show-\(entry.id.uuidString)")
              }
            }
          }
          if props.saving { ProgressView().controlSize(.small) }
          if props.saveFailed {
            Label(
              L10n.string("Could not save settings collection", locale: locale),
              systemImage: "exclamationmark.circle"
            ).foregroundStyle(.red)
          }
        } else if props.loadFailed {
          HStack {
            Label(
              L10n.string("Could not open settings collection", locale: locale),
              systemImage: "exclamationmark.circle"
            ).foregroundStyle(.red)
            Spacer()
            Button(L10n.string("Try again", locale: locale)) { send(.retryCatalogLoad) }
          }
        } else {
          ProgressView().controlSize(.small)
        }
      }
      Section(L10n.string("File", locale: locale)) {
        SecureField(
          L10n.string("File passphrase", locale: locale),
          text: Binding(
            get: { props.passphrase }, set: { send(.editCatalogPassphrase($0)) })
        )
        .privacySensitive()
        .accessibilityIdentifier("catalog-passphrase")
        SecureField(
          L10n.string("Confirm passphrase for export", locale: locale),
          text: Binding(
            get: { props.confirmPassphrase },
            set: { send(.editCatalogConfirmPassphrase($0)) })
        )
        .privacySensitive()
        .accessibilityIdentifier("catalog-confirm-passphrase")
        if !props.passphrase.isEmpty && props.passphrase.count < 16 {
          Label(
            L10n.string("Use at least 16 characters", locale: locale),
            systemImage: "info.circle"
          ).font(.caption).foregroundStyle(.secondary)
        }
        Label(
          L10n.string("A lost passphrase cannot be recovered", locale: locale),
          systemImage: "key"
        ).font(.caption).foregroundStyle(.secondary)
        Text(L10n.string("A weak passphrase may be guessed", locale: locale))
          .font(.caption).foregroundStyle(.secondary)
        Button(L10n.string("Export collection", locale: locale)) {
          send(.exportCatalog([]))
        }
        .disabled(!props.canExport)
        .accessibilityIdentifier("catalog-export-all")
        Button(L10n.string("Import file", locale: locale)) { openImporter() }
          .disabled(!props.canImport)
          .accessibilityIdentifier("catalog-import-file")
        if props.exporting || props.importing { ProgressView().controlSize(.small) }
        if props.exportFailed {
          Label(
            L10n.string("Could not export settings", locale: locale),
            systemImage: "exclamationmark.circle"
          ).foregroundStyle(.red)
        }
        if props.importFailed {
          Label(
            L10n.string("Could not import settings", locale: locale),
            systemImage: "exclamationmark.circle"
          ).foregroundStyle(.red)
        }
      }
      Section(L10n.string("iCloud", locale: locale)) {
        if props.syncEnabled {
          Button(L10n.string("Turn off sync", locale: locale)) {
            send(.disableCatalogSync)
          }
          .disabled(!props.canManage)
          .accessibilityIdentifier("catalog-sync-disable")
        } else {
          Button(L10n.string("Turn on sync", locale: locale)) {
            send(.requestCatalogSync)
          }
          .disabled(!props.canManage)
          .accessibilityIdentifier("catalog-sync-enable")
        }
        syncStatus
        if !props.conflicts.isEmpty {
          ForEach(props.conflicts) { conflict in
            VStack(alignment: .leading, spacing: 6) {
              Text(
                props.visibleEntries.first(where: { $0.id == conflict.id })?.name
                  ?? props.hiddenEntries.first(where: { $0.id == conflict.id })?.name
                  ?? conflict.remote?.name ?? conflict.id.uuidString)
              Text(
                conflict.remote == nil
                  ? L10n.string("Removed in iCloud", locale: locale)
                  : L10n.string("Changed on another device", locale: locale)
              )
              .font(.caption).foregroundStyle(.secondary)
              if conflict.remote != nil {
                DisclosureGroup(L10n.string("Changes", locale: locale)) {
                  ForEach(props.conflictDifferences[conflict.id] ?? []) { difference in
                    VStack(alignment: .leading, spacing: 4) {
                      Text(L10n.string(difference.labelKey, locale: locale)).font(.headline)
                      HStack(alignment: .top, spacing: 12) {
                        conflictValue(difference.current)
                          .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                          .accessibilityHidden(true)
                        conflictValue(difference.selected)
                          .frame(maxWidth: .infinity, alignment: .leading)
                      }
                    }
                    .accessibilityElement(children: .combine)
                  }
                }
              }
              Button(L10n.string("Keep this version", locale: locale)) {
                send(.resolveCatalogConflict(conflict.id, useRemote: false))
              }
              .buttonStyle(.borderless)
              .disabled(!props.canManage)
              Button(L10n.string("Use iCloud version", locale: locale)) {
                send(.resolveCatalogConflict(conflict.id, useRemote: true))
              }
              .buttonStyle(.borderless)
              .disabled(!props.canManage)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func conflictValue(_ value: CatalogDisplayValue) -> some View {
    switch value {
    case .text(let text): Text(verbatim: text)
    case .localized(let key): Text(L10n.string(key, locale: locale))
    case .absent: Text(verbatim: "—")
    }
  }

  @ViewBuilder
  private var syncStatus: some View {
    switch props.syncStatus {
    case .disabled: EmptyView()
    case .checking:
      Label(L10n.string("Checking iCloud account", locale: locale), systemImage: "clock")
    case .ready:
      Label(
        L10n.string("Settings collection is synced", locale: locale),
        systemImage: "checkmark.icloud")
    case .pending:
      Label(L10n.string("Sync pending", locale: locale), systemImage: "clock.arrow.circlepath")
    case .offline:
      Label(L10n.string("Sync waiting for a connection", locale: locale), systemImage: "wifi.slash")
    case .signInRequired:
      HStack {
        Label(
          L10n.string("Sign in to iCloud to sync", locale: locale),
          systemImage: "person.crop.circle.badge.exclamationmark")
        Spacer()
        Button(L10n.string("Try again", locale: locale)) { send(.retryCatalogSync) }
          .disabled(!props.canManage)
          .accessibilityIdentifier("catalog-sync-retry")
      }
    case .accountChanged:
      Label(
        L10n.string("iCloud account changed; sync is off", locale: locale),
        systemImage: "person.crop.circle.badge.exclamationmark")
    case .failed:
      Label(L10n.string("Sync failed", locale: locale), systemImage: "exclamationmark.icloud")
    }
  }
}
