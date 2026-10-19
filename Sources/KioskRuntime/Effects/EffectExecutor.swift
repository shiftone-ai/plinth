import KioskCore

@MainActor
public final class EffectExecutor: EffectExecuting {
  public var resultSink: (@MainActor (Event, NodeID) -> Void)?
  public let registry = EffectTaskRegistry()
  private var nextCatalogTaskID: UInt64 = 0
  private var nextRemoteTaskID: UInt64 = 0
  private let port: any EffectPort
  public init(port: any EffectPort) { self.port = port }

  public func execute(_ effect: Effect) {
    if case .confineNativePointer(let point) = effect.kind {
      if !port.confinePointer(point) { resultSink?(.nativePointerConstraintFailed, .platform) }
      return
    }
    if case .releaseExternalPointer = effect.kind {
      // Release is synchronous in the owning adapter; it must not replace the unlock timer's task.
      port.releasePointer()
      return
    }
    if case .stopWebServer = effect.kind {
      port.stopWebServer()
      return
    }
    if case .cancelOperation(let token) = effect.kind {
      registry.cancel(token)
      port.cancel(token)
      return
    }
    let source: NodeID
    switch effect.kind {
    case .applyPresentation, .releasePresentation, .prepareExternalScene, .captureExternalPointer,
      .openInformationPage:
      source = .platform
    case .releaseExternalPointer, .confineNativePointer: return
    case .createSurface, .releaseSurface, .load, .controlExternalWeb: source = .webSurface
    case .scheduleIdle, .scheduleRetry, .scheduleUnlockTimeout,
      .scheduleRemotePairingDeadline, .scheduleRemotePairingCodeExpiry,
      .scheduleRemoteCommandDeadline:
      source = .idleClock
    case .verifyPasscode, .configurePasscode, .readBiometricStatus, .changeBiometricUnlock,
      .performBiometricUnlock:
      source = .credentials
    case .saveProfile, .recoverProfile, .bootstrap: source = .profileRepository
    case .loadCatalog, .recoverCatalog, .saveCatalog, .prepareCatalogExport,
      .importCatalogFile:
      source = .catalogRepository
    case .checkCatalogAccount, .checkCatalogAccountAfterStopping,
      .startCatalogCloudSync, .stopCatalogCloudSync,
      .publishCatalogChanges:
      source = .cloudCatalog
    case .loadRemoteConfiguration, .checkRemoteAccount, .startRemoteDirectory,
      .stopRemoteDirectory, .refreshRemoteDirectory, .setRemoteEnabled,
      .setRemoteVisibility, .generateRemotePairingCode, .sendRemotePairingRequest,
      .respondToRemotePairing, .saveRemoteTargetGrant, .revokeRemoteController,
      .sendRemoteCommand, .claimRemoteCommand, .sendRemoteCommandResult,
      .rejectRemoteCommand, .reportRemoteCommandProgress:
      source = .cloudRemote
    case .startWebServer: source = .webAdministration
    case .stopWebServer: return
    case .cancelOperation: return
    }
    let registrationToken: OperationToken
    if source == .cloudCatalog {
      nextCatalogTaskID &+= 1
      precondition(nextCatalogTaskID != 0)
      registrationToken = OperationToken(
        owner: .cloudCatalog, ownerEpoch: effect.token.ownerEpoch,
        operationID: nextCatalogTaskID)
    } else if source == .cloudRemote {
      nextRemoteTaskID &+= 1
      precondition(nextRemoteTaskID != 0)
      registrationToken = OperationToken(
        owner: .cloudRemote, ownerEpoch: effect.token.ownerEpoch,
        operationID: nextRemoteTaskID)
    } else {
      registrationToken = effect.token
    }
    registry.start(
      registrationToken, operation: { [port] in await port.perform(effect) },
      completion: { [weak self] event in self?.resultSink?(event, source) })
  }

  public func stop() {
    registry.cancelAll()
    resultSink = nil
    port.stop()
  }
}
