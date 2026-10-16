import AppKit
import Foundation
import KioskCore
import KioskMacApp
import Testing

@testable import KioskRuntime

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_SOAK_TESTS"] == "1"))
@MainActor
struct ExhibitionSoakTests {
  @Test(.timeLimit(.minutes(30)))
  func oneWeekOfAcceleratedIdleResetsUsesRealWebKitAndKeepsResourcesBounded() async throws {
    guard #available(macOS 15.0, *) else { throw SoakFailure.load }
    FileHandle.standardError.write(Data("SOAK_STARTED\n".utf8))
    NSApplication.shared.setActivationPolicy(.regular)
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let clock = SoakClock()
    let web = WebKitAdapter()
    web.host.frame = CGRect(x: 0, y: 0, width: 720, height: 480)
    let window = NSWindow(
      contentRect: web.host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = web.host
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate()
    defer { window.close() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-soak-\(UUID())")
    let displays = SoakDisplay()
    let port = NativeEffectPort(
      web: web,
      presentation: PresentationAdapter(window: window, preview: true, displays: displays),
      repository: ProfileRepository(fileURL: directory.appendingPathComponent("profile.json")),
      credentials: CredentialStore(service: "ai.shiftone.plinth.tests.\(UUID())"),
      biometrics: BiometricCredentialAdapter(service: "ai.shiftone.plinth.tests.\(UUID())") {
        "Enable administrator unlock with biometrics"
      },
      clock: clock,
      displays: displays)
    let executor = EffectExecutor(port: port)
    let runtime = RootRuntime(clock: clock, executor: executor)
    defer { runtime.stop() }
    let stream = AsyncStream<Event>.makeStream()
    defer { stream.continuation.finish() }
    web.send = { [weak runtime] event in
      let reply = runtime?.send(event, from: .webSurface).reply
      stream.continuation.yield(event)
      return reply
    }
    let profile = KioskProfile(
      startURL: server.origin + "/home",
      navigation: .init(
        rules: [.init(id: 1, origin: try #require(Origin(urlString: server.origin)))],
        allowsHTTP: true),
      idleTimeout: 120, resetMode: .retainWebsiteData)
    var events = stream.stream.makeAsyncIterator()
    runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    func finished() async throws {
      while let event = await events.next(isolation: MainActor.shared) {
        if case .webFinished = event { return }
        if case .webFailed = event { throw SoakFailure.load }
      }
      throw SoakFailure.load
    }
    try await finished()
    let started = ContinuousClock.now
    for cycle in 1...5040 {
      if cycle <= 3 { FileHandle.standardError.write(Data("SOAK_CYCLE_START=\(cycle)\n".utf8)) }
      let old = try #require(web.webView)
      runtime.send(.nativeInput(.primaryDown, .web), from: .platform)
      runtime.send(.nativeInput(.primaryUp, .web), from: .platform)
      let deadline = try #require(runtime.snapshot.exhibition.idleOperation)
      clock.now += 120
      runtime.send(.idleDeadlineReached(deadline), from: .idleClock)
      try await finished()
      if cycle <= 3 { FileHandle.standardError.write(Data("SOAK_CYCLE_FINISHED=\(cycle)\n".utf8)) }
      try #require(runtime.snapshot.root.mode == .exhibiting)
      try #require(web.webView !== old)
      try #require(old.superview == nil && old.navigationDelegate == nil)
      try #require(web.host.subviews.count == 1)
      try #require(runtime.reports.count <= 256)
      try #require(executor.registry.pendingCount <= 4)
      try #require(runtime.snapshot.exhibition.idleOperation == nil)
      if cycle % 100 == 0 {
        FileHandle.standardError.write(
          Data("SOAK_CYCLES=\(cycle) elapsed=\(started.duration(to: .now))\n".utf8))
      }
    }
    #expect(clock.now == 7 * 24 * 60 * 60)
    #expect(runtime.snapshot.exhibition.generation == 5041)
    FileHandle.standardError.write(
      Data(
        "SOAK_PASSED cycles=5040 simulatedSeconds=604800 elapsed=\(started.duration(to: .now))\n"
          .utf8))
  }
  private enum SoakFailure: Error { case load }
}

@MainActor
private final class SoakClock: ClockPort { var now: Double = 0 }

@MainActor
private final class SoakDisplay: DisplayReadingPort {
  let count = 1
  let exhibitionFrame: CGRect? = CGRect(x: 0, y: 0, width: 720, height: 480)
}
