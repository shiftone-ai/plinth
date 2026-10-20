import KioskCore
import KioskMacApp
import KioskRuntime
import Testing

@MainActor
final class FakeClock: ClockPort {
  private(set) var now: Double = 0
  func advance(by seconds: Double) {
    precondition(seconds >= 0)
    now += seconds
  }
}

@MainActor
final class ScriptedWebPort: EffectExecuting {
  var resultSink: (@MainActor (Event, NodeID) -> Void)?
  private(set) var effects: [Effect] = []
  var onExecute: (@MainActor (Effect) -> Void)?
  private(set) var stopped = false
  func execute(_ effect: Effect) {
    effects.append(effect)
    onExecute?(effect)
  }
  func stop() {
    stopped = true
    resultSink = nil
    onExecute = nil
  }
  func deliver(_ event: Event, source: NodeID) { resultSink?(event, source) }
}

@MainActor
struct RuntimeFixture {
  let clock: FakeClock
  let port: ScriptedWebPort
  let runtime: RootRuntime
  init() {
    let clock = FakeClock()
    let port = ScriptedWebPort()
    self.clock = clock
    self.port = port
    self.runtime = RootRuntime(clock: clock, executor: port)
  }

  func profile() throws -> KioskProfile {
    let origin = try #require(Origin(urlString: "https://example.com"))
    return KioskProfile(
      startURL: "https://example.com/home", navigation: .init(rules: [.init(id: 1, origin: origin)])
    )
  }

  func startExhibiting(resetMode: ResetMode = .newVisitorSession) throws {
    var profile = try profile()
    profile.resetMode = resetMode
    runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1),
      from: .root)
    let presentation = try #require(runtime.snapshot.root.presentationOperation)
    port.deliver(.presentationApplied(presentation), source: .platform)
    let create = try #require(runtime.snapshot.exhibition.operation)
    port.deliver(.surfaceCreated(create), source: .webSurface)
    let load = try #require(runtime.snapshot.exhibition.operation)
    port.deliver(.webCommitted(load, url: "https://example.com/home"), source: .webSurface)
    port.deliver(.webFinished(load), source: .webSurface)
    try #require(runtime.snapshot.root.mode == .exhibiting)
  }
}
