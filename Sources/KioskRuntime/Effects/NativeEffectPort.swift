import Foundation
import KioskCore
import KioskLocalization

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor
public final class NativeEffectPort: EffectPort {
  public let web: any WebSurfacePort
  private let presentation: any PresentationPort
  private let repository: ProfileRepository
  private let catalogRepository: CatalogRepository?
  private let catalogCloudSync: CatalogCloudSync?
  private let remoteDirectory: (any RemoteDirectoryPort)?
  private var cloudStopTask: Task<Void, Never>?
  private var remoteStopTask: Task<Void, Never>?
  private let credentials: CredentialStore
  private let biometrics: any BiometricCredentialPort
  private let clock: any ClockPort
  private let displays: any DisplayReadingPort
  private let webServer: (any WebAdministrationServerPort)?
  public init(
    web: any WebSurfacePort, presentation: any PresentationPort, repository: ProfileRepository,
    credentials: CredentialStore, biometrics: any BiometricCredentialPort, clock: any ClockPort,
    displays: any DisplayReadingPort, catalogRepository: CatalogRepository? = nil,
    catalogCloudSync: CatalogCloudSync? = nil,
    remoteDirectory: (any RemoteDirectoryPort)? = nil,
    webServer: (any WebAdministrationServerPort)? = nil
  ) {
    self.web = web
    self.presentation = presentation
    self.repository = repository
    self.catalogRepository = catalogRepository
    self.catalogCloudSync = catalogCloudSync
    self.remoteDirectory = remoteDirectory
    self.credentials = credentials
    self.biometrics = biometrics
    self.clock = clock
    self.displays = displays
    self.webServer = webServer
  }

  public func perform(_ effect: Effect) async -> Event? {
    if Task.isCancelled { return nil }
    switch effect.kind {
    case .openInformationPage(let page, let locale):
      await openInformationPage(page, locale: locale)
      return .informationPageOpenCompleted(effect.token)
    case .bootstrap:
      return await bootstrap(effect.token)
    case .prepareExternalScene:
      return await presentation.prepareExternalScene(effect.token)
        ? .externalScenePrepared(effect.token) : .externalScenePreparationFailed(effect.token)
    case .applyPresentation(let request):
      return await applyPresentation(request, token: effect.token)
    case .releasePresentation:
      presentation.release()
      return .presentationReleased(effect.token)
    case .createSurface(let mode, let interaction):
      web.create(effect.token, mode: mode, interaction: interaction)
      return .surfaceCreated(effect.token)
    case .releaseSurface:
      web.releaseSurface()
      return .surfaceReleased(effect.token)
    case .load(let address):
      return web.load(address, token: effect.token) ? nil : .webFailed(effect.token, .network)
    case .controlExternalWeb(let control):
      await web.control(control, token: effect.token)
      return nil
    case .captureExternalPointer:
      return .externalPointerCaptureCompleted(
        effect.token, succeeded: await presentation.capturePointer(effect.token))
    case .releaseExternalPointer:
      presentation.releasePointer()
      return nil
    case .confineNativePointer(let point):
      return presentation.confinePointer(point) ? nil : .nativePointerConstraintFailed
    case .scheduleIdle(let deadline), .scheduleRetry(let deadline),
      .scheduleUnlockTimeout(let deadline):
      do {
        try await Task.sleep(for: .seconds(Self.timerInterval(until: deadline, now: clock.now)))
      } catch { return nil }
      if Task.isCancelled { return nil }
      if case .scheduleIdle = effect.kind { return .idleDeadlineReached(effect.token) }
      if case .scheduleUnlockTimeout = effect.kind { return .unlockDeadlineReached(effect.token) }
      return .retryDeadlineReached(effect.token)
    case .scheduleRemotePairingDeadline(let deadline, let requestID):
      do {
        try await Task.sleep(for: .seconds(Self.timerInterval(until: deadline, now: clock.now)))
      } catch { return nil }
      return Task.isCancelled ? nil : .remotePairingDeadlineReached(effect.token, requestID)
    case .scheduleRemotePairingCodeExpiry(let deadline):
      do {
        try await Task.sleep(for: .seconds(Self.timerInterval(until: deadline, now: clock.now)))
      } catch { return nil }
      return Task.isCancelled ? nil : .remotePairingCodeExpired(effect.token)
    case .scheduleRemoteCommandDeadline(let deadline, let requestID):
      do {
        try await Task.sleep(for: .seconds(Self.timerInterval(until: deadline, now: clock.now)))
      } catch { return nil }
      return Task.isCancelled ? nil : .remoteCommandDeadlineReached(effect.token, requestID)
    case .verifyPasscode(let passcode):
      let succeeded = (try? await credentials.verify(passcode)) ?? false
      return .credentialVerified(effect.token, succeeded: succeeded)
    case .configurePasscode(let passcode):
      do {
        try await credentials.configure(passcode)
        return .credentialConfigured(effect.token, succeeded: true)
      } catch { return .credentialConfigured(effect.token, succeeded: false) }
    case .readBiometricStatus:
      return .biometricStatusRead(effect.token, biometrics.status())
    case .changeBiometricUnlock(let enabled):
      let (status, outcome) = await biometrics.changeEnabled(enabled, token: effect.token)
      return .biometricChangeCompleted(effect.token, status, outcome)
    case .performBiometricUnlock:
      let (status, outcome) = await biometrics.unlock(effect.token)
      return .biometricUnlockCompleted(effect.token, status, outcome)
    case .saveProfile(let profile):
      do {
        try await repository.save(profile)
        return .profileSaved(effect.token, profile)
      } catch { return .profileSaveFailed(effect.token) }
    case .recoverProfile(let profile):
      do {
        try await repository.recover(profile)
        return .profileSaved(effect.token, profile)
      } catch { return .profileSaveFailed(effect.token) }
    case .loadRemoteConfiguration:
      guard let remoteDirectory else { return .remoteLoadFailed(effect.token) }
      do { return try await .remoteLoaded(effect.token, remoteDirectory.load()) } catch {
        return .remoteLoadFailed(effect.token)
      }
    case .checkRemoteAccount:
      guard let remoteDirectory else { return .remoteAccountCheckFailed(effect.token) }
      do {
        return try await .remoteAccountChecked(effect.token, remoteDirectory.checkAccount())
      } catch { return .remoteAccountCheckFailed(effect.token) }
    case .startRemoteDirectory(let accountIdentifier, let installation):
      await remoteDirectory?.start(
        accountIdentifier: accountIdentifier, installation: installation, session: effect.token)
      return nil
    case .stopRemoteDirectory:
      await remoteDirectory?.stop(command: effect.token)
      return nil
    case .refreshRemoteDirectory:
      await remoteDirectory?.refresh(session: effect.token)
      return nil
    case .setRemoteEnabled(let enabled, let accountIdentifier):
      guard let remoteDirectory else { return .remotePreferenceUpdateFailed(effect.token) }
      do {
        return try await .remoteConfigurationUpdated(
          effect.token, remoteDirectory.setEnabled(enabled, accountIdentifier: accountIdentifier))
      } catch { return .remotePreferenceUpdateFailed(effect.token) }
    case .setRemoteVisibility(let id, let visible, let accountIdentifier):
      guard let remoteDirectory else { return .remotePreferenceUpdateFailed(effect.token) }
      do {
        return try await .remoteConfigurationUpdated(
          effect.token,
          remoteDirectory.setVisibility(
            id, visible: visible,
            accountIdentifier: accountIdentifier))
      } catch { return .remotePreferenceUpdateFailed(effect.token) }
    case .generateRemotePairingCode:
      do {
        return try .remotePairingCodeGenerated(
          effect.token, RemotePairingCodeGenerator.generate())
      } catch { return .remotePairingCodeGenerationFailed(effect.token) }
    case .sendRemotePairingRequest(
      let target, let code, let requestID,
      let accountIdentifier):
      guard let remoteDirectory else {
        return .remotePairingCloudFailed(effect.token, requestID)
      }
      do {
        try await remoteDirectory.sendPairingRequest(
          target: target, code: code, requestID: requestID,
          accountIdentifier: accountIdentifier, command: effect.token)
        return nil
      } catch { return .remotePairingCloudFailed(effect.token, requestID) }
    case .respondToRemotePairing(let proposal, let approved):
      guard let remoteDirectory else { return .remotePairingApprovalFailed(effect.token) }
      do {
        return try await .remotePairingApprovalStored(
          effect.token, remoteDirectory.respondToPairing(proposal, approved: approved))
      } catch { return .remotePairingApprovalFailed(effect.token) }
    case .saveRemoteTargetGrant(let grant, let requestID):
      guard let remoteDirectory else { return .remoteTargetGrantFailed(effect.token) }
      do {
        return try await .remoteTargetGrantStored(
          effect.token, remoteDirectory.saveTargetGrant(grant, requestID: requestID))
      } catch { return .remoteTargetGrantFailed(effect.token) }
    case .revokeRemoteController(let id, let accountIdentifier):
      guard let remoteDirectory else { return .remoteControllerRevokeFailed(effect.token) }
      do {
        return try await .remoteControllerRevoked(
          effect.token,
          remoteDirectory.revokeController(
            id, accountIdentifier: accountIdentifier))
      } catch { return .remoteControllerRevokeFailed(effect.token) }
    case .sendRemoteCommand(
      let target, let command, let requestID,
      let accountIdentifier):
      guard let remoteDirectory else {
        return .remoteCommandCloudFailed(effect.token, requestID)
      }
      do {
        try await remoteDirectory.sendCommand(
          target: target, command: command, requestID: requestID,
          accountIdentifier: accountIdentifier, operation: effect.token)
        return nil
      } catch { return .remoteCommandCloudFailed(effect.token, requestID) }
    case .claimRemoteCommand(let request):
      guard let remoteDirectory else { return .remoteCommandClaimFailed(effect.token) }
      do {
        return try await .remoteCommandClaimed(
          effect.token, remoteDirectory.claimCommand(request),
          processedAt: Int64(Date().timeIntervalSince1970))
      } catch { return .remoteCommandClaimFailed(effect.token) }
    case .sendRemoteCommandResult(let request, let outcome):
      guard let remoteDirectory else { return .remoteCommandResultFailed(effect.token) }
      do {
        try await remoteDirectory.sendResult(for: request, outcome: outcome)
        return .remoteCommandResultQueued(effect.token)
      } catch { return .remoteCommandResultFailed(effect.token) }
    case .rejectRemoteCommand(let request, let reason):
      try? await remoteDirectory?.sendResult(for: request, outcome: .rejected(reason))
      return nil
    case .reportRemoteCommandProgress(let request, let outcome):
      try? await remoteDirectory?.sendResult(for: request, outcome: outcome)
      return nil
    case .loadCatalog, .recoverCatalog, .saveCatalog, .checkCatalogAccount,
      .checkCatalogAccountAfterStopping,
      .startCatalogCloudSync, .stopCatalogCloudSync, .publishCatalogChanges,
      .prepareCatalogExport, .importCatalogFile:
      return await performCatalog(effect)
    case .startWebServer:
      guard let webServer else { return .webServerFailed(effect.token, .unavailable) }
      switch await webServer.start() {
      case .success(let endpoint): return .webServerStarted(effect.token, endpoint)
      case .failure(let failure): return .webServerFailed(effect.token, failure)
      }
    case .stopWebServer:
      webServer?.stop()
      return nil
    case .cancelOperation: return nil
    }
  }

  private func bootstrap(_ token: OperationToken) async -> Event {
    async let profile = repository.load()
    async let configured = credentials.isConfigured()
    let profileResult: Result<KioskProfile?, Error>
    do { profileResult = .success(try await profile) } catch { profileResult = .failure(error) }
    let credentialResult: Result<Bool, Error>
    do { credentialResult = .success(try await configured) } catch {
      credentialResult = .failure(error)
    }
    return Self.bootstrapEvent(
      token, profile: profileResult, credentials: credentialResult, displayCount: displays.count)
  }

  private func performCatalog(_ effect: Effect) async -> Event? {
    switch effect.kind {
    case .loadCatalog:
      guard let catalogRepository else { return .catalogLoadFailed(effect.token) }
      do {
        return try await .catalogLoaded(effect.token, catalogRepository.load())
      } catch CatalogRepository.Failure.corruptCatalog {
        return .catalogLoadCorrupt(effect.token)
      } catch { return .catalogLoadFailed(effect.token) }
    case .recoverCatalog:
      guard let catalogRepository else { return .catalogLoadFailed(effect.token) }
      do { return try await .catalogLoaded(effect.token, catalogRepository.recoverDamaged()) } catch
      { return .catalogLoadFailed(effect.token) }
    case .saveCatalog(let document):
      guard let catalogRepository else { return .catalogSaveFailed(effect.token) }
      do {
        try await catalogRepository.save(document)
        return .catalogSaved(effect.token, document)
      } catch { return .catalogSaveFailed(effect.token) }
    case .checkCatalogAccount:
      return await catalogAccountCheckResult(effect.token)
    case .checkCatalogAccountAfterStopping:
      await catalogCloudSync?.stop(command: effect.token)
      return await catalogAccountCheckResult(effect.token)
    case .startCatalogCloudSync(let accountID, let entries, let conflicts, let pendingDeletions):
      await catalogCloudSync?.start(
        accountIdentifier: accountID, entries: entries, conflicts: conflicts,
        pendingDeletions: pendingDeletions, session: effect.token)
      return nil
    case .stopCatalogCloudSync:
      await catalogCloudSync?.stop(command: effect.token)
      return nil
    case .publishCatalogChanges(let session, let resolvedConflicts, let saves, let deletions):
      await catalogCloudSync?.queue(
        command: effect.token, session: session, resolvedConflicts: resolvedConflicts,
        saves: saves, deletions: deletions)
      return nil
    case .prepareCatalogExport(let entries, let passphrase):
      do {
        return try await .catalogExportPrepared(
          effect.token, EncryptedCatalogFile.encrypt(entries: entries, passphrase: passphrase))
      } catch { return .catalogExportFailed(effect.token) }
    case .importCatalogFile(let url, let passphrase):
      do {
        let data = try await CatalogFileAccess.read(url)
        return try await .catalogImportPreviewReady(
          effect.token, EncryptedCatalogFile.decrypt(data, passphrase: passphrase))
      } catch { return .catalogImportFailed(effect.token) }
    default: return nil
    }
  }

  private func openInformationPage(_ page: InformationPage, locale: String) async {
    let language = L10n.languageCode(for: Locale(identifier: locale))
    let name = page == .privacy ? "privacy" : "support"
    var address = "https://shiftone-ai.github.io/plinth/\(language)/\(name).html"
    #if DEBUG
      if let testAddress = ProcessInfo.processInfo.environment["PLINTH_TEST_INFORMATION_PAGE_URL"] {
        address = testAddress
      }
    #endif
    guard !Task.isCancelled, let url = URL(string: address) else { return }
    #if os(macOS)
      _ = NSWorkspace.shared.open(url)
    #else
      _ = await UIApplication.shared.open(url)
    #endif
  }

  public nonisolated static func timerInterval(until deadline: Double, now: Double) -> Double {
    // Bound native timer conversion, not the logical deadline. Mediators rearm early notifications.
    min(86_400, max(0, deadline - now))
  }

  private func catalogAccountCheckResult(_ token: OperationToken) async -> Event {
    guard let catalogCloudSync else { return .catalogAccountCheckDeferred(token) }
    switch await catalogCloudSync.accountAvailability() {
    case .available(let id): return .catalogAccountChecked(token, id)
    case .unavailable: return .catalogAccountChecked(token, nil)
    case .transient: return .catalogAccountCheckDeferred(token)
    }
  }

  private func applyPresentation(_ request: PresentationRequest, token: OperationToken) async
    -> Event?
  {
    if request.usesExternalDisplay || request.externalDisplayMode != nil {
      let prepare: @Sendable () async -> Bool = { [self] in
        await prepareDisplayMode(request.externalDisplayMode, token: token)
      }
      let prepared = await withTaskGroup(of: Bool.self) { group in
        group.addTask(operation: prepare)
        group.addTask {
          do { try await Task.sleep(for: .seconds(10)) } catch { return false }
          return false
        }
        let result = await group.next() ?? false
        presentation.cancelDisplayModePreparation(token)
        group.cancelAll()
        return result
      }
      guard !Task.isCancelled else { return nil }
      guard prepared else { return .presentationFailed(token) }
    }
    return presentation.apply(request)
      ? .presentationApplied(token) : .presentationFailed(token)
  }

  private func prepareDisplayMode(_ mode: ExternalDisplayMode?, token: OperationToken) async -> Bool
  {
    guard !Task.isCancelled else { return false }
    return await presentation.prepareExternalDisplayMode(mode, token: token)
  }

  public func stop() {
    if let catalogCloudSync {
      cloudStopTask = Task { await catalogCloudSync.stop() }
    }
    if let remoteDirectory {
      remoteStopTask = Task { await remoteDirectory.stop(command: nil) }
    }
    biometrics.cancelAll()
    web.stop()
    presentation.release()
    presentation.releasePointer()
    webServer?.stop()
  }

  public func releasePointer() { presentation.releasePointer() }
  public func confinePointer(_ point: SurfacePoint) -> Bool { presentation.confinePointer(point) }
  public func stopWebServer() { webServer?.stop() }

  public func cancel(_ token: OperationToken) {
    biometrics.cancel(token)
    presentation.cancelScenePreparation(token)
    presentation.cancelDisplayModePreparation(token)
    presentation.cancelPointerCapture(token)
  }
}
