import Foundation
import KioskCore

public enum SettingsIntent: Sendable {
  case edit(ProfileDraftEdit)
  case editPasscode(String)
  case save, discard
  case configurePasscode
  case changeBiometricUnlock(Bool)
  case cancelBiometricChange
  case start, quit
  case prepareExternalScene
  case addOriginRule
  case removeOriginRule(UInt64)
  case editCatalogName(String)
  case registerCatalog(String)
  case selectCatalog(UUID)
  case dismissCatalogSelection
  case applyCatalogSelection
  case editCatalogSelectionName(String)
  case renameCatalog(id: UUID, name: String)
  case confirmCatalogRename(UUID)
  case cancelCatalogRename
  case updateCatalog(UUID)
  case confirmCatalogUpdate(UUID)
  case cancelCatalogUpdate
  case setCatalogVisibility(id: UUID, visible: Bool)
  case promptCatalogRemoval(UUID)
  case cancelCatalogRemoval
  case confirmCatalogRemoval(UUID)
  case editCatalogPassphrase(String)
  case editCatalogConfirmPassphrase(String)
  case exportCatalog([UUID])
  case fileExportCompleted(Bool)
  case dismissCatalogExport
  case importCatalogFile(URL)
  case confirmCatalogImport
  case cancelCatalogImport
  case retryCatalogLoad
  case requestCatalogSync, confirmCatalogSync, cancelCatalogSync, disableCatalogSync,
    retryCatalogSync
  case requestCatalogShare(UUID)
  case confirmCatalogShare(UUID)
  case cancelCatalogShare
  case resolveCatalogConflict(UUID, useRemote: Bool)
}

public enum UnlockIntent: Sendable {
  case editPasscode(String)
  case submit
  case authenticateWithBiometrics
  case cancelBiometricAuthentication
  case cancel
}

public enum RootIntent: Sendable { case unlock }
