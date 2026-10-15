import Foundation
import KioskCore

@MainActor
public final class NativeEffectPort: EffectPort {
  public let web: any WebSurfacePort
  private let presentation: any PresentationPort
  private let repository: ProfileRepository
  private let credentials: CredentialStore
  private let clock: any ClockPort
  private let displays: any DisplayReadingPort
  public init(
    web: any WebSurfacePort, presentation: any PresentationPort, repository: ProfileRepository,
    credentials: CredentialStore, clock: any ClockPort,
    displays: any DisplayReadingPort
  ) {
    self.web = web
    self.presentation = presentation
    self.repository = repository
    self.credentials = credentials
    self.clock = clock
    self.displays = displays
  }

  public func perform(_ effect: Effect) async -> Event? {
    if Task.isCancelled { return nil }
    switch effect.kind {
    case .bootstrap:
      do {
        async let profile = repository.load()
        async let configured = credentials.isConfigured()
        return try await .bootstrapped(
          profile: profile, credentialsConfigured: configured, displayCount: displays.count)
      } catch { return .bootstrapFailed(effect.token, displayCount: displays.count) }
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
    case .saveProfile(let profile):
      do {
        try await repository.save(profile)
        return .profileSaved(effect.token, profile)
      } catch { return .profileSaveFailed(effect.token) }
    case .cancelOperation: return nil
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
    web.stop()
    presentation.release()
    presentation.releasePointer()
  }

  public func releasePointer() { presentation.releasePointer() }
  public func confinePointer(_ point: SurfacePoint) -> Bool { presentation.confinePointer(point) }

  public func cancel(_ token: OperationToken) {
    presentation.cancelScenePreparation(token)
    presentation.cancelDisplayModePreparation(token)
    presentation.cancelPointerCapture(token)
  }
}
