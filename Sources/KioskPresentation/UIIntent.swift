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
  case remoteTab(RemoteManagementTab)
  case remoteEnabled(Bool)
  case remoteVisibility(UUID, Bool)
  case remoteSelectDevice(UUID?)
  case remoteRefresh
  case remotePairingCode
  case remotePairingInput(String)
  case remotePairingRequest
  case remotePairingApproval(Bool)
  case remoteRevokeController(UUID)
  case remoteStatus
  case remoteEditOpen
  case remoteEditStartURL(String)
  case remoteEditDraft(ProfileDraftEdit)
  case remoteEditAddRule
  case remoteEditRemoveRule(UInt64)
  case remoteEditReview
  case remoteEditCancel
  case remoteEditSave
  case remoteExhibitionReview(RemoteExhibitionAction)
  case remoteExhibitionCancelReview
  case remoteExhibitionRequest(RemoteExhibitionAction)
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
  case requestCatalogExport([UUID])
  case cancelCatalogExport
  case exportCatalog([UUID])
  case fileExportCompleted(Bool)
  case dismissCatalogExport
  case selectCatalogImportFile(URL)
  case importCatalogFile(URL)
  case confirmCatalogImport
  case cancelCatalogImport
  case retryCatalogLoad
  case requestCatalogRecovery, cancelCatalogRecovery, confirmCatalogRecovery
  case requestCatalogSync, confirmCatalogSync, cancelCatalogSync, disableCatalogSync,
    retryCatalogSync
  case requestCatalogShare(UUID)
  case confirmCatalogShare(UUID)
  case cancelCatalogShare
  case resolveCatalogConflict(UUID, useRemote: Bool)
  case openInformationPage(InformationPage, locale: String)
  case openLicenses, closeLicenses
}

public enum UnlockIntent: Sendable {
  case editPasscode(String)
  case submit
  case authenticateWithBiometrics
  case cancelBiometricAuthentication
  case cancel
}

public enum RootIntent: Sendable { case unlock }
