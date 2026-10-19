import Foundation

public struct Effect: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case bootstrap
    case applyPresentation(PresentationRequest)
    case releasePresentation
    case prepareExternalScene
    case createSurface(ResetMode, interaction: InteractionPolicy = .init())
    case releaseSurface(generation: UInt64)
    case load(String)
    case controlExternalWeb(ExternalWebControl)
    case captureExternalPointer
    case releaseExternalPointer
    case confineNativePointer(SurfacePoint)
    case scheduleIdle(deadline: Double)
    case scheduleRetry(deadline: Double)
    case scheduleUnlockTimeout(deadline: Double)
    case verifyPasscode(String)
    case configurePasscode(String)
    case readBiometricStatus
    case changeBiometricUnlock(Bool)
    case performBiometricUnlock
    case saveProfile(KioskProfile)
    case recoverProfile(KioskProfile)
    case loadRemoteConfiguration
    case checkRemoteAccount
    case startRemoteDirectory(accountIdentifier: String, installation: RemoteInstallation)
    case stopRemoteDirectory
    case refreshRemoteDirectory
    case setRemoteEnabled(Bool, accountIdentifier: String)
    case setRemoteVisibility(UUID, visible: Bool, accountIdentifier: String)
    case generateRemotePairingCode
    case scheduleRemotePairingCodeExpiry(Double)
    case sendRemotePairingRequest(
      target: RemoteDevice, code: String, requestID: UUID, accountIdentifier: String)
    case respondToRemotePairing(RemotePairingProposal, approved: Bool)
    case saveRemoteTargetGrant(RemotePeerGrant, requestID: UUID)
    case revokeRemoteController(UUID, accountIdentifier: String)
    case scheduleRemotePairingDeadline(Double, requestID: UUID)
    case sendRemoteCommand(
      target: RemotePeerGrant, command: RemoteCommandPayload,
      requestID: UUID, accountIdentifier: String)
    case claimRemoteCommand(RemoteCommandRequest)
    case sendRemoteCommandResult(RemoteCommandRequest, RemoteCommandOutcome)
    case rejectRemoteCommand(RemoteCommandRequest, RemoteCommandRejection)
    case reportRemoteCommandProgress(RemoteCommandRequest, RemoteCommandOutcome)
    case scheduleRemoteCommandDeadline(Double, requestID: UUID)
    case loadCatalog
    case recoverCatalog
    case saveCatalog(SettingsCatalog)
    case checkCatalogAccount
    case checkCatalogAccountAfterStopping
    case startCatalogCloudSync(
      String, entries: [CatalogEntry], conflicts: [UUID],
      pendingDeletions: [CatalogPendingDeletion])
    case stopCatalogCloudSync
    case publishCatalogChanges(
      session: OperationToken, resolvedConflicts: [UUID], saves: [CatalogEntry],
      deletions: [CatalogPendingDeletion])
    case prepareCatalogExport([CatalogEntry], passphrase: String)
    case importCatalogFile(URL, passphrase: String)
    case openInformationPage(InformationPage, locale: String)
    case startWebServer
    case stopWebServer
    case cancelOperation(OperationToken)
  }
  public let token: OperationToken
  public let kind: Kind
  public init(_ token: OperationToken, _ kind: Kind) {
    self.token = token
    self.kind = kind
  }
}
