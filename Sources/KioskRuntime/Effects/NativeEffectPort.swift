import Foundation
import KioskCore

@MainActor
public final class NativeEffectPort: EffectPort {
  public let web: any WebSurfacePort
  private let presentation: any PresentationPort
  private let repository: ProfileRepository
  private let catalogRepository: CatalogRepository?
  private let catalogCloudSync: CatalogCloudSync?
  private var cloudStopTask: Task<Void, Never>?
  private let credentials: CredentialStore
  private let biometrics: any BiometricCredentialPort
  private let clock: any ClockPort
  private let displays: any DisplayReadingPort
  public init(
    web: any WebSurfacePort, presentation: any PresentationPort, repository: ProfileRepository,
    credentials: CredentialStore, biometrics: any BiometricCredentialPort, clock: any ClockPort,
    displays: any DisplayReadingPort, catalogRepository: CatalogRepository? = nil,
    catalogCloudSync: CatalogCloudSync? = nil
  ) {
    self.web = web
    self.presentation = presentation
    self.repository = repository
    self.catalogRepository = catalogRepository
    self.catalogCloudSync = catalogCloudSync
    self.credentials = credentials
    self.biometrics = biometrics
    self.clock = clock
    self.displays = displays
  }

  public func perform(_ effect: Effect) async -> Event? {
    if Task.isCancelled { return nil }
    switch effect.kind {
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
    case .loadCatalog, .saveCatalog, .checkCatalogAccount, .checkCatalogAccountAfterStopping,
      .startCatalogCloudSync, .stopCatalogCloudSync, .publishCatalogChanges,
      .prepareCatalogExport, .importCatalogFile:
      return await performCatalog(effect)
    case .cancelOperation: return nil
    }
  }

  private func bootstrap(_ token: OperationToken) async -> Event {
    async let profile = repository.load()
    async let configured = credentials.isConfigured()
    let hasCredentials: Bool
    do { hasCredentials = try await configured } catch {
      return .bootstrapFailed(
        token, displayCount: displays.count, credentialsConfigured: false,
        profileCorrupt: false)
    }
    do {
      return try await .bootstrapped(
        profile: profile, credentialsConfigured: hasCredentials, displayCount: displays.count)
    } catch ProfileRepository.Failure.corruptProfile {
      return .bootstrapFailed(
        token, displayCount: displays.count, credentialsConfigured: hasCredentials,
        profileCorrupt: true)
    } catch {
      return .bootstrapFailed(
        token, displayCount: displays.count, credentialsConfigured: hasCredentials,
        profileCorrupt: false)
    }
  }

  private func performCatalog(_ effect: Effect) async -> Event? {
    switch effect.kind {
    case .loadCatalog:
      guard let catalogRepository else { return .catalogLoadFailed(effect.token) }
      do { return try await .catalogLoaded(effect.token, catalogRepository.load()) } catch {
        return .catalogLoadFailed(effect.token)
      }
    case .saveCatalog(let document):
      guard let catalogRepository else { return .catalogSaveFailed(effect.token) }
      do {
        try await catalogRepository.save(document)
        return .catalogSaved(effect.token, document)
      } catch { return .catalogSaveFailed(effect.token) }
    case .checkCatalogAccount:
      return .catalogAccountChecked(effect.token, await catalogCloudSync?.accountIdentifier())
    case .checkCatalogAccountAfterStopping:
      await catalogCloudSync?.stop(command: effect.token)
      return .catalogAccountChecked(effect.token, await catalogCloudSync?.accountIdentifier())
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
        session: session, resolvedConflicts: resolvedConflicts,
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

  public nonisolated static func timerInterval(until deadline: Double, now: Double) -> Double {
    // Bound native timer conversion, not the logical deadline. Mediators rearm early notifications.
    min(86_400, max(0, deadline - now))
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
    biometrics.cancelAll()
    web.stop()
    presentation.release()
    presentation.releasePointer()
  }

  public func releasePointer() { presentation.releasePointer() }
  public func confinePointer(_ point: SurfacePoint) -> Bool { presentation.confinePointer(point) }

  public func cancel(_ token: OperationToken) {
    biometrics.cancel(token)
    presentation.cancelScenePreparation(token)
    presentation.cancelDisplayModePreparation(token)
    presentation.cancelPointerCapture(token)
  }
}
