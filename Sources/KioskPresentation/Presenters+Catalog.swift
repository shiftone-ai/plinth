import Foundation
import KioskCore

extension Presenters {
  static func catalog(_ root: RootState, _ administration: AdministrationState)
    -> CatalogProps
  {
    let selection = administration.catalogSelection.flatMap { selected in
      root.catalog.entries.first(where: {
        $0.id == selected.id && root.catalogEntryAvailable($0)
      })
    }
    let savedSnapshot = root.savedProfile.flatMap(CatalogSnapshot.init)
    let available = root.catalog.entries.filter(root.catalogEntryAvailable)
    let conflicts = root.catalog.conflicts.filter(root.catalogConflictAvailable)
    let oversizedConflictLocalIDs = Set(
      conflicts.compactMap { conflict -> UUID? in
        guard let local = available.first(where: { $0.id == conflict.id }),
          let nextVersion = ProfileRevision.next(
            after: max(local.version, conflict.remote?.version ?? 0))
        else { return nil }
        var chosen = local
        chosen.version = nextVersion
        chosen.scope = .iCloud
        chosen.accountIdentifier = root.catalog.accountIdentifier
        return CatalogCloudPayload.encoded(chosen) == nil ? conflict.id : nil
      })
    let shareTooLarge =
      selection.map {
        $0.scope == .device && cloudPayloadTooLarge($0)
      } ?? false
    let renameTooLarge =
      selection.map {
        $0.scope == .iCloud && CatalogEntry.validName(administration.catalogSelectionNameDraft)
          && administration.catalogSelectionNameDraft != $0.name
          && cloudPayloadTooLarge($0, name: administration.catalogSelectionNameDraft)
      } ?? false
    let updateTooLarge =
      selection.map { entry in
        guard entry.scope == .iCloud, let savedSnapshot,
          savedSnapshot != entry.snapshot
        else { return false }
        return cloudPayloadTooLarge(entry, snapshot: savedSnapshot)
      } ?? false
    let fileIdle =
      root.mode == .administration && root.catalogLoaded
      && root.catalogSaveOperation == nil && root.catalogExportOperation == nil
      && root.catalogImportOperation == nil && root.catalogImportPreview == nil
      && root.catalogExportData == nil
    let passphraseValid =
      administration.catalogPassphrase.precomposedStringWithCanonicalMapping
      .count >= 16 && administration.catalogPassphrase.utf8.count <= 1024
    return CatalogProps(
      syncEnabled: root.catalog.syncEnabled, cloudAvailable: root.catalogCloudAvailable,
      syncStatus: root.catalogSyncStatus,
      syncConsentPending: root.catalogSyncConsentPending,
      shareCandidate: root.catalog.entries.first { $0.id == root.catalogShareCandidateID },
      conflicts: conflicts,
      oversizedConflictLocalIDs: oversizedConflictLocalIDs,
      pendingDeletionIDs: Set(
        root.catalog.pendingDeletions.filter {
          $0.accountIdentifier == root.catalog.accountIdentifier
        }.map(\.id)),
      conflictDifferences: Dictionary(
        uniqueKeysWithValues: conflicts.compactMap { conflict in
          guard let remote = conflict.remote else { return nil }
          let local = root.catalog.entries.first {
            $0.id == conflict.id && root.catalogEntryAvailable($0)
          }
          var differences = CatalogComparison.differences(
            current: local?.snapshot.profile(revision: 1), selected: remote.snapshot)
          if local?.name != remote.name {
            differences.insert(
              .init(
                labelKey: "Name", current: local.map { .text($0.name) } ?? .absent,
                selected: .text(remote.name)), at: 0)
          }
          if differences.isEmpty {
            differences = CatalogComparison.differences(current: nil, selected: remote.snapshot)
          }
          return (conflict.id, differences)
        }),
      visibleEntries: available.filter(\.isVisible),
      hiddenEntries: available.filter { !$0.isVisible },
      loaded: root.catalogLoaded,
      loadFailed: root.catalogLoadFailed, corrupt: root.catalogCorrupt,
      recoveryPending: root.catalogRecoveryPending,
      saving: root.catalogSaveOperation != nil,
      saveFailed: root.catalogSaveFailed, nameDraft: administration.catalogNameDraft,
      canRegister: root.mode == .administration && root.catalogLoaded
        && root.catalogSaveOperation == nil && root.saveOperation == nil
        && administration.savedProfile != nil && !administration.hasUnsavedDraft
        && CatalogEntry.validName(
          administration.catalogNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
      selectedEntry: selection,
      selectedNameDraft: administration.catalogSelectionNameDraft,
      renameCandidate: selection == nil ? nil : root.catalogRenameCandidate,
      updateCandidateID: selection == nil ? nil : root.catalogUpdateCandidateID,
      differences: selection.map {
        CatalogComparison.differences(current: root.savedProfile, selected: $0.snapshot)
      } ?? [],
      contents: selection.map {
        CatalogComparison.differences(current: nil, selected: $0.snapshot)
      } ?? [],
      canApply: selection != nil && root.mode == .administration
        && root.catalogSaveOperation == nil
        && !administration.hasUnsavedDraft && !administration.saving,
      canSelect: root.mode == .administration && root.catalogLoaded
        && root.catalogSaveOperation == nil && !administration.hasUnsavedDraft,
      canManage: root.mode == .administration && root.catalogLoaded
        && root.catalogSaveOperation == nil,
      canShare: selection?.scope == .device && root.catalogCanShare
        && root.catalogSaveOperation == nil
        && !conflicts.contains(where: { $0.id == selection?.id })
        && !root.catalog.pendingDeletions.contains(where: {
          $0.id == selection?.id && $0.accountIdentifier == root.catalog.accountIdentifier
        })
        && !shareTooLarge,
      shareTooLarge: shareTooLarge,
      canRename: selection != nil && root.catalogSaveOperation == nil
        && !conflicts.contains(where: { $0.id == selection?.id })
        && CatalogEntry.validName(administration.catalogSelectionNameDraft)
        && administration.catalogSelectionNameDraft != selection?.name
        && !renameTooLarge,
      renameTooLarge: renameTooLarge,
      canUpdate: selection != nil && savedSnapshot != nil
        && !conflicts.contains(where: { $0.id == selection?.id })
        && savedSnapshot != selection?.snapshot
        && root.catalogSaveOperation == nil && root.saveOperation == nil
        && !administration.hasUnsavedDraft && !updateTooLarge,
      updateTooLarge: updateTooLarge,
      removalCandidate: root.catalog.entries.first {
        $0.id == root.catalogRemovalCandidateID && root.catalogEntryAvailable($0)
      },
      passphrase: administration.catalogPassphrase,
      confirmPassphrase: administration.catalogConfirmPassphrase,
      exportSelection: root.catalogExportCandidateIDs,
      canStartExport: fileIdle && !available.isEmpty
        && root.catalogExportCandidateIDs == nil && root.catalogImportSelectedURL == nil,
      canExport: fileIdle && !available.isEmpty
        && root.catalogExportCandidateIDs.map({ ids in
          ids.allSatisfy { id in available.contains(where: { $0.id == id }) }
        }) == true && root.catalogImportSelectedURL == nil
        && passphraseValid
        && administration.catalogPassphrase.precomposedStringWithCanonicalMapping
          == administration.catalogConfirmPassphrase.precomposedStringWithCanonicalMapping,
      importFileURL: root.catalogImportSelectedURL,
      canStartImport: fileIdle && root.catalogExportCandidateIDs == nil
        && root.catalogImportSelectedURL == nil,
      canImport: fileIdle && root.catalogImportSelectedURL != nil
        && root.catalogExportCandidateIDs == nil && passphraseValid,
      exporting: root.catalogExportOperation != nil, exportData: root.catalogExportData,
      exportFailed: root.catalogExportFailed,
      importing: root.catalogImportOperation != nil,
      importPreview: root.catalogImportPreview,
      importMatches: Dictionary(
        uniqueKeysWithValues: (root.catalogImportPreview ?? []).compactMap { item in
          if let existing = root.catalog.entries.first(where: {
            $0.id == item.id && root.catalogEntryAvailable($0)
          }) ?? root.catalog.entries.first(where: { $0.id == item.id }) {
            return (
              item.id,
              root.catalogEntryAvailable(existing)
                && existing.name == item.name && existing.snapshot == item.snapshot
                ? CatalogImportMatch.alreadyPresent : .separateCopy
            )
          }
          if root.catalog.entries.contains(where: {
            $0.name == item.name && root.catalogEntryAvailable($0)
          }) {
            return (item.id, .sameName)
          }
          return nil
        }),
      importContents: Dictionary(
        uniqueKeysWithValues: (root.catalogImportPreview ?? []).map {
          ($0.id, CatalogComparison.differences(current: nil, selected: $0.snapshot))
        }),
      importFailed: root.catalogImportFailed,
      canConfirmImport: root.catalogImportPreview != nil
        && root.catalogSaveOperation == nil)
  }

  private static func cloudPayloadTooLarge(
    _ entry: CatalogEntry, name: String? = nil, snapshot: CatalogSnapshot? = nil
  ) -> Bool {
    var proposed = entry
    if let name { proposed.name = name }
    if let snapshot { proposed.snapshot = snapshot }
    if proposed.scope == .iCloud, name != nil || snapshot != nil {
      guard let nextVersion = ProfileRevision.next(after: proposed.version)
      else { return true }
      proposed.version = nextVersion
    }
    return CatalogCloudPayload.encoded(proposed) == nil
  }
}
