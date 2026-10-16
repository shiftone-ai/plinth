import Foundation
import KioskCore
import Network
import Testing

@testable import KioskRuntime

@MainActor
struct WebAdministrationListenerLifecycleTests {
  @Test func cancellationWhileWaitingForPreviousListenerDoesNotRestart() async {
    let server = WebAdministrationServer(port: 0)
    defer { server.stop() }
    let previous = UUID()
    server.cancellationPending = previous
    let restarting = Task { await server.start() }
    while server.cancellationWaiterCount == 0 { await Task.yield() }
    restarting.cancel()
    server.stateChanged(.cancelled, generation: previous)
    guard case .failure = await restarting.value else {
      Issue.record("Cancelled restart opened a listener")
      return
    }
    #expect(server.listeningPort == nil)
  }

  @Test func failedReadyListenerReportsLossToRoot() async throws {
    let fixture = RuntimeFixture()
    let server = WebAdministrationServer(port: 0)
    server.attach(runtime: fixture.runtime, locale: { Locale(identifier: "en") })
    defer {
      server.stop()
      fixture.runtime.stop()
    }
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let operation = try #require(fixture.runtime.snapshot.root.webServerOperation)
    guard case .success(let endpoint) = await server.start() else {
      Issue.record("Listener did not start")
      return
    }
    fixture.port.deliver(.webServerStarted(operation, endpoint), source: .webAdministration)
    let generation = try #require(server.generation)
    server.stateChanged(.failed(.posix(.ECONNABORTED)), generation: generation)
    #expect(!fixture.runtime.snapshot.root.webServerRunning)
    #expect(fixture.runtime.snapshot.root.webServerURL == nil)
    #expect(fixture.runtime.snapshot.root.webServerFailure == .unavailable)
    #expect(server.listeningPort == nil)
  }
}
