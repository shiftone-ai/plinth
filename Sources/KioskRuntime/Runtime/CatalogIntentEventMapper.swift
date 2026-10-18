import Foundation
import KioskCore
import KioskPresentation

/// Maps the shared settings collection UI actions for both native platforms.
public enum CatalogIntentEventMapper {
  public static func event(for intent: SettingsIntent, importCount: Int) -> Event? {
    switch intent {
    case .editCatalogName(let value): .catalogNameEdited(value)
    case .registerCatalog(let name): .catalogRegisterRequested(id: UUID(), name: name)
    case .selectCatalog(let id): .catalogSelectRequested(id)
    case .dismissCatalogSelection: .catalogSelectionDismissed
    case .applyCatalogSelection: .catalogApplyRequested
    case .editCatalogSelectionName(let value): .catalogSelectionNameEdited(value)
    case .renameCatalog(let id, let name): .catalogRenameRequested(id: id, name: name)
    case .confirmCatalogRename(let id): .catalogRenameConfirmed(id)
    case .cancelCatalogRename: .catalogRenameCancelled
    case .updateCatalog(let id): .catalogUpdateRequested(id)
    case .confirmCatalogUpdate(let id): .catalogUpdateConfirmed(id)
    case .cancelCatalogUpdate: .catalogUpdateCancelled
    case .setCatalogVisibility(let id, let visible):
      .catalogVisibilityRequested(id: id, visible: visible)
    case .promptCatalogRemoval(let id): .catalogRemovePromptRequested(id)
    case .cancelCatalogRemoval: .catalogRemovePromptCancelled
    case .confirmCatalogRemoval(let id): .catalogRemoveConfirmed(id)
    case .editCatalogPassphrase(let value): .catalogPassphraseEdited(value)
    case .editCatalogConfirmPassphrase(let value): .catalogConfirmPassphraseEdited(value)
    case .requestCatalogExport(let ids): .catalogExportPromptRequested(ids: ids)
    case .cancelCatalogExport: .catalogExportPromptCancelled
    case .exportCatalog(let ids): .catalogExportRequested(ids: ids)
    case .fileExportCompleted(let succeeded): .catalogFileExportCompleted(succeeded)
    case .dismissCatalogExport: .catalogExportDismissed
    case .selectCatalogImportFile(let url): .catalogImportFileSelected(url)
    case .importCatalogFile(let url): .catalogImportFileRequested(url)
    case .confirmCatalogImport:
      .catalogImportConfirmed(replacementIDs: (0..<importCount).map { _ in UUID() })
    case .cancelCatalogImport: .catalogImportCancelled
    case .retryCatalogLoad: .catalogLoadRequested
    case .requestCatalogRecovery: .catalogRecoveryRequested
    case .cancelCatalogRecovery: .catalogRecoveryCancelled
    case .confirmCatalogRecovery: .catalogRecoveryConfirmed
    case .requestCatalogSync: .catalogSyncEnableRequested
    case .confirmCatalogSync: .catalogSyncEnableConfirmed
    case .cancelCatalogSync: .catalogSyncEnableCancelled
    case .disableCatalogSync: .catalogSyncDisableRequested
    case .retryCatalogSync: .catalogSyncRetryRequested
    case .requestCatalogShare(let id): .catalogSharePromptRequested(id)
    case .confirmCatalogShare(let id): .catalogShareConfirmed(id)
    case .cancelCatalogShare: .catalogSharePromptCancelled
    case .resolveCatalogConflict(let id, let useRemote):
      .catalogConflictResolved(id, useRemote: useRemote)
    default: nil
    }
  }
}
