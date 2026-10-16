import Foundation
import KioskCore

extension Presenters {
  static func catalog(_ root: RootState, _ administration: AdministrationState)
    -> CatalogProps
  {
    let selection = administration.catalogSelection.flatMap { selected in
      root.catalog.entries.first(where: { $0.id == selected.id })
    }
    let savedSnapshot = root.savedProfile.flatMap(CatalogSnapshot.init)
    let available = root.catalog.entries.filter(root.catalogEntryAvailable)
    return CatalogProps(
      syncEnabled: root.catalog.syncEnabled, syncStatus: root.catalogSyncStatus,
      syncConsentPending: root.catalogSyncConsentPending,
      shareCandidate: root.catalog.entries.first { $0.id == root.catalogShareCandidateID },
      conflicts: root.catalog.conflicts,
      conflictDifferences: Dictionary(
        uniqueKeysWithValues: root.catalog.conflicts.compactMap { conflict in
          guard let remote = conflict.remote else { return nil }
          let local = root.catalog.entries.first { $0.id == conflict.id }
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
      loadFailed: root.catalogLoadFailed, saving: root.catalogSaveOperation != nil,
      saveFailed: root.catalogSaveFailed, nameDraft: administration.catalogNameDraft,
      canRegister: root.mode == .administration && root.catalogLoaded
        && root.catalogSaveOperation == nil && root.saveOperation == nil
        && administration.savedProfile != nil && !administration.hasUnsavedDraft
        && CatalogEntry.validName(
          administration.catalogNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
      selectedEntry: selection,
      selectedNameDraft: administration.catalogSelectionNameDraft,
      renameCandidate: root.catalogRenameCandidate,
      updateCandidateID: root.catalogUpdateCandidateID,
      differences: selection.map {
        CatalogComparison.differences(current: root.savedProfile, selected: $0.snapshot)
      } ?? [],
      contents: selection.map {
        CatalogComparison.differences(current: nil, selected: $0.snapshot)
      } ?? [],
      canApply: selection != nil && root.mode == .administration
        && !administration.hasUnsavedDraft && !administration.saving,
      canManage: root.mode == .administration && root.catalogLoaded
        && root.catalogSaveOperation == nil,
      canShare: selection?.scope == .device && root.catalog.syncEnabled
        && root.catalog.accountIdentifier != nil && root.catalogSaveOperation == nil,
      canRename: selection != nil && root.catalogSaveOperation == nil
        && !root.catalog.conflicts.contains(where: { $0.id == selection?.id })
        && CatalogEntry.validName(administration.catalogSelectionNameDraft)
        && administration.catalogSelectionNameDraft != selection?.name,
      canUpdate: selection != nil && savedSnapshot != nil
        && !root.catalog.conflicts.contains(where: { $0.id == selection?.id })
        && savedSnapshot != selection?.snapshot
        && root.catalogSaveOperation == nil && root.saveOperation == nil
        && !administration.hasUnsavedDraft,
      removalCandidate: root.catalog.entries.first {
        $0.id == root.catalogRemovalCandidateID
      },
      passphrase: administration.catalogPassphrase,
      confirmPassphrase: administration.catalogConfirmPassphrase,
      canExport: root.mode == .administration && root.catalogLoaded
        && !root.catalog.entries.isEmpty && root.catalogExportOperation == nil
        && root.catalogExportData == nil
        && administration.catalogPassphrase.precomposedStringWithCanonicalMapping.count >= 16
        && administration.catalogPassphrase.utf8.count <= 1024
        && administration.catalogPassphrase.precomposedStringWithCanonicalMapping
          == administration.catalogConfirmPassphrase.precomposedStringWithCanonicalMapping,
      canImport: root.mode == .administration && root.catalogLoaded
        && root.catalogImportOperation == nil && root.catalogImportPreview == nil
        && administration.catalogPassphrase.precomposedStringWithCanonicalMapping.count >= 16
        && administration.catalogPassphrase.utf8.count <= 1024,
      exporting: root.catalogExportOperation != nil, exportData: root.catalogExportData,
      exportFailed: root.catalogExportFailed,
      importing: root.catalogImportOperation != nil,
      importPreview: root.catalogImportPreview,
      importMatches: Dictionary(
        uniqueKeysWithValues: (root.catalogImportPreview ?? []).compactMap { item in
          if let existing = root.catalog.entries.first(where: { $0.id == item.id }) {
            return (
              item.id,
              existing.name == item.name && existing.snapshot == item.snapshot
                ? CatalogImportMatch.alreadyPresent : .separateCopy
            )
          }
          if root.catalog.entries.contains(where: { $0.name == item.name }) {
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

}
