#if DEBUG && os(iOS)
  import KioskCore
  import KioskRuntime

  /// Changes only the in-memory timeout during an explicitly requested device test.
  @MainActor
  final class MobileTestEffectPort: EffectPort {
    private let base: any EffectPort
    private let idleTimeout: Double

    init(base: any EffectPort, idleTimeout: Double) {
      self.base = base
      self.idleTimeout = idleTimeout
    }

    func perform(_ effect: Effect) async -> Event? {
      let result = await base.perform(effect)
      guard case .bootstrapped(var profile?, let configured, let count) = result else {
        return result
      }
      profile.idleTimeout = idleTimeout
      return .bootstrapped(profile: profile, credentialsConfigured: configured, displayCount: count)
    }

    func cancel(_ token: OperationToken) { base.cancel(token) }
    func stop() { base.stop() }
    func releasePointer() { base.releasePointer() }
  }
#endif
