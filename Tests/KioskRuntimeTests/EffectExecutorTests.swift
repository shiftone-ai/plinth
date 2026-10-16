import KioskCore
import KioskMacApp
import KioskRuntime
import Testing

@MainActor
private final class ScriptedEffectPort: EffectPort {
  private(set) var performed: [Effect] = []
  private(set) var stopCount = 0
  private var loadToken: OperationToken?
  private var loadWaiter: CheckedContinuation<OperationToken, Never>?

  func perform(_ effect: Effect) async -> Event? {
    performed.append(effect)
    switch effect.kind {
    case .applyPresentation: return .presentationApplied(effect.token)
    case .createSurface: return .surfaceCreated(effect.token)
    case .load:
      loadToken = effect.token
      let waiter = loadWaiter
      loadWaiter = nil
      waiter?.resume(returning: effect.token)
      return .webFinished(effect.token)
    default: return nil
    }
  }

  func waitForLoad() async -> OperationToken {
    if let loadToken { return loadToken }
    return await withCheckedContinuation { loadWaiter = $0 }
  }

  func stop() { stopCount += 1 }
}

@MainActor
struct EffectExecutorTests {
  @Test func asyncEffectsRouteValueResultsThroughOwnedNodesAndStopPort() async throws {
    let origin = try #require(Origin(urlString: "https://example.com"))
    let profile = KioskProfile(
      startURL: "https://example.com/home", navigation: .init(rules: [.init(id: 1, origin: origin)])
    )
    let port = ScriptedEffectPort()
    let executor = EffectExecutor(port: port)
    let runtime = RootRuntime(clock: FakeClock(), executor: executor)
    defer { runtime.stop() }
    runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let loadToken = await port.waitForLoad()
    await executor.registry.waitForOperation(loadToken)
    #expect(runtime.snapshot.root.mode == .exhibiting)
    #expect(runtime.snapshot.exhibition.phase == .ready)
    #expect(
      port.performed.map(\.kind).filter { $0 != .readBiometricStatus } == [
        .applyPresentation(.init()), .createSurface(.newVisitorSession), .load(profile.startURL),
      ])
    #expect(runtime.reports.contains { $0.source == .platform && $0.handler == .root })
    #expect(runtime.reports.contains { $0.source == .webSurface && $0.handler == .exhibition })
    #expect(executor.registry.pendingCount == 0)
    runtime.stop()
    runtime.stop()
    #expect(port.stopCount == 1)
  }
}
