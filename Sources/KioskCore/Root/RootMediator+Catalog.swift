import Foundation

extension RootMediator {
  static func reduceCatalog(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    switch envelope.event {
    case .catalogLoadRequested, .catalogLoaded, .catalogLoadFailed,
      .catalogRegistrationRequested, .catalogSelectRequested, .catalogApplyRequested,
      .catalogRenameRequested, .catalogRenameConfirmed, .catalogRenameCancelled,
      .catalogUpdateRequested, .catalogUpdateConfirmed, .catalogUpdateCancelled,
      .catalogVisibilityRequested, .catalogRemovePromptRequested,
      .catalogRemovePromptCancelled, .catalogRemoveConfirmed,
      .catalogSaved, .catalogSaveFailed:
      return reduceCatalogLocal(state, envelope, context: context)
    case .catalogExportOperationRequested, .catalogExportPrepared, .catalogExportFailed,
      .catalogExportDismissed, .catalogFileExportCompleted,
      .catalogImportOperationRequested, .catalogImportPreviewReady,
      .catalogImportFailed, .catalogImportConfirmed, .catalogImportCancelled:
      return reduceCatalogFile(state, envelope)
    case .catalogSyncEnableRequested, .catalogSyncEnableCancelled,
      .catalogSyncEnableConfirmed, .catalogSyncDisableRequested,
      .catalogAccountChecked, .catalogCloudAccountChanged, .catalogCloudStatus,
      .catalogCloudChanges, .catalogCloudAcknowledged,
      .catalogCloudDeletionsAcknowledged, .catalogSharePromptRequested,
      .catalogSharePromptCancelled, .catalogShareConfirmed, .catalogConflictResolved:
      return reduceCatalogCloud(state, envelope)
    default: return .bubble
    }
  }

  static func canEditCatalog(_ state: RootState, _ envelope: EventEnvelope) -> Bool {
    envelope.source == .settings && state.mode == .administration && state.catalogLoaded
      && state.catalogSaveOperation == nil && state.saveOperation == nil
  }

  static func commitCatalog(
    _ state: RootState, _ catalog: SettingsCatalog, token: OperationToken,
    publish: Bool = true
  ) -> Mediation<RootState> {
    guard let revision = ProfileRevision.next(after: state.catalog.revision)
    else { return .reject(state, .invalidProfile) }
    var document = catalog
    document.revision = revision
    var next = state
    next.pendingCatalog = document
    next.catalogSaveOperation = token
    next.catalogSaveFailed = false
    next.pendingCatalogPublishes = publish
    return .handled(.init(next, reply: .accepted, effects: [Effect(token, .saveCatalog(document))]))
  }

  static func receiveCloudChanges(
    _ changes: [CatalogCloudChange], into catalog: SettingsCatalog, accountID: String
  ) -> SettingsCatalog? {
    var document = catalog
    for change in changes {
      let id: UUID
      let remote: CatalogEntry?
      switch change {
      case .upsert(let value):
        guard value.scope == .iCloud, value.accountIdentifier == accountID else { continue }
        id = value.id
        remote = value
      case .delete(let value):
        id = value
        remote = nil
      }
      if let index = document.entries.firstIndex(where: { $0.id == id }) {
        let local = document.entries[index]
        guard local.scope == .iCloud, local.accountIdentifier == accountID else {
          document.conflicts.removeAll { $0.id == id }
          document.conflicts.append(CatalogConflict(id: id, remote: remote))
          continue
        }
        if let remote, local.sameCloudContents(as: remote) {
          document.entries[index].version = remote.version
          document.entries[index].syncedVersion = remote.version
          document.conflicts.removeAll { $0.id == id }
          continue
        }
        if local.version == local.syncedVersion {
          if var remote {
            remote.isVisible = local.isVisible
            remote.syncedVersion = remote.version
            document.entries[index] = remote
          } else {
            document.entries.remove(at: index)
          }
          document.conflicts.removeAll { $0.id == id }
        } else {
          document.conflicts.removeAll { $0.id == id }
          document.conflicts.append(CatalogConflict(id: id, remote: remote))
        }
      } else if var remote {
        if let pending = document.pendingDeletions.first(where: {
          $0.id == id && $0.accountIdentifier == accountID
        }) {
          if pending.baseVersion != remote.version {
            document.conflicts.removeAll { $0.id == id }
            document.conflicts.append(CatalogConflict(id: id, remote: remote))
          }
        } else {
          remote.isVisible = false
          remote.syncedVersion = remote.version
          document.entries.append(remote)
        }
      } else {
        document.pendingDeletions.removeAll {
          $0.id == id && $0.accountIdentifier == accountID
        }
        document.conflicts.removeAll { $0.id == id }
      }
    }
    return document == catalog ? nil : document
  }
}
