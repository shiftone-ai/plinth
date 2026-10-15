import KioskCore

@MainActor
public final class EffectExecutor: EffectExecuting {
  public var resultSink: (@MainActor (Event, NodeID) -> Void)?
  public let registry = EffectTaskRegistry()
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
    if case .cancelOperation(let token) = effect.kind {
      registry.cancel(token)
      port.cancel(token)
      return
    }
    let source: NodeID
    switch effect.kind {
    case .applyPresentation, .releasePresentation, .prepareExternalScene, .captureExternalPointer:
      source = .platform
    case .releaseExternalPointer, .confineNativePointer: return
    case .createSurface, .releaseSurface, .load, .controlExternalWeb: source = .webSurface
    case .scheduleIdle, .scheduleRetry, .scheduleUnlockTimeout: source = .idleClock
    case .verifyPasscode, .configurePasscode: source = .credentials
    case .saveProfile, .bootstrap: source = .profileRepository
    case .cancelOperation: return
    }
    registry.start(
      effect.token, operation: { [port] in await port.perform(effect) },
      completion: { [weak self] event in self?.resultSink?(event, source) })
  }

  public func stop() {
    registry.cancelAll()
    resultSink = nil
    port.stop()
  }
}
