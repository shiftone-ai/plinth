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
          CatalogLoadErrorRows(corrupt: props.corrupt, send: send)
        } else {
          ProgressView().controlSize(.small)
        }
      }
      Section(L10n.string("File", locale: locale)) {
        Button(L10n.string("Export collection", locale: locale)) {
          send(.requestCatalogExport([]))
        }
        .disabled(!props.canStartExport)
        .accessibilityIdentifier("catalog-export-all")
        Button(L10n.string("Import file", locale: locale)) { openImporter() }
          .disabled(!props.canStartImport)
          .accessibilityIdentifier("catalog-import-file")
        if props.exportFailed && props.exportSelection == nil {
          Label(
            L10n.string("Could not export settings", locale: locale),
            systemImage: "exclamationmark.circle"
          ).foregroundStyle(.red)
        }
        if props.importFailed && props.importFileURL == nil {
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
          .disabled(!props.canManage || !props.cloudAvailable)
          .accessibilityIdentifier("catalog-sync-enable")
        }
        if props.cloudAvailable {
          syncStatus
        } else {
          Label(
            L10n.string("iCloud sync is unavailable in this build", locale: locale),
            systemImage: "icloud.slash")
        }
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
              Button(
                props.pendingDeletionIDs.contains(conflict.id)
                  ? L10n.string("Remove iCloud version", locale: locale)
                  : localCopyIsDevice(conflict.id)
                    ? L10n.string("Share this version", locale: locale)
                    : L10n.string("Keep this version", locale: locale)
              ) {
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

  private func localCopyIsDevice(_ id: UUID) -> Bool {
    (props.visibleEntries + props.hiddenEntries).contains {
      $0.id == id && $0.scope == .device
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
      HStack {
        Label(
          L10n.string("Sync waiting for a connection", locale: locale), systemImage: "wifi.slash")
        Spacer()
        Button(L10n.string("Try again", locale: locale)) { send(.retryCatalogSync) }
          .disabled(!props.canManage)
          .accessibilityIdentifier("catalog-sync-retry")
      }
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
      HStack {
        Label(L10n.string("Sync failed", locale: locale), systemImage: "exclamationmark.icloud")
        Spacer()
        Button(L10n.string("Try again", locale: locale)) { send(.retryCatalogSync) }
          .disabled(!props.canManage)
          .accessibilityIdentifier("catalog-sync-retry")
      }
    }
  }
}
