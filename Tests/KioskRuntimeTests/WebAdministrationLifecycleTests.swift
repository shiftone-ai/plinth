import KioskCore
import KioskRuntime
import Testing

@MainActor
struct WebAdministrationLifecycleTests {
  @Test func mobileBackgroundStopsAndForegroundRestartsWithoutEndingTheSession() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .mobileDisplaysChanged(
        .init(
          deviceAvailable: true, externalAvailable: false)), from: .platform)
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(
        profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let first = try #require(fixture.runtime.snapshot.root.webServerOperation)
    let endpoint = WebServerEndpoint(url: "http://192.0.2.1:47623/", origins: [])
    fixture.port.deliver(.webServerStarted(first, endpoint), source: .webAdministration)
    fixture.runtime.send(
      .webAuthenticationVerified(String(repeating: "a", count: 64)),
      from: .administration)
    let session = try #require(fixture.runtime.snapshot.root.webSession)

    fixture.runtime.send(.applicationDeactivated, from: .platform)
    #expect(!fixture.runtime.snapshot.root.webServerRunning)
    #expect(fixture.runtime.snapshot.root.webSession == session)
    #expect(fixture.port.effects.contains { $0.kind == .stopWebServer })
    fixture.runtime.send(.applicationActivated, from: .platform)
    let restart = try #require(fixture.runtime.snapshot.root.webServerOperation)
    #expect(restart != first)
    fixture.port.deliver(.webServerStarted(restart, endpoint), source: .webAdministration)
    #expect(fixture.runtime.snapshot.root.webServerRunning)
    #expect(fixture.runtime.snapshot.root.webSession == session)
  }

  @Test func macWakeRecreatesTheListenerWithoutEndingTheSession() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(
        profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let first = try #require(fixture.runtime.snapshot.root.webServerOperation)
    let endpoint = WebServerEndpoint(url: "http://192.0.2.1:47623/", origins: [])
    fixture.port.deliver(.webServerStarted(first, endpoint), source: .webAdministration)
    fixture.runtime.send(
      .webAuthenticationVerified(String(repeating: "b", count: 64)),
      from: .administration)
    let session = try #require(fixture.runtime.snapshot.root.webSession)

    fixture.runtime.send(.systemDidWake, from: .platform)
    let restart = try #require(fixture.runtime.snapshot.root.webServerOperation)
    #expect(restart != first)
    #expect(!fixture.runtime.snapshot.root.webServerRunning)
    #expect(fixture.port.effects.contains { $0.kind == .stopWebServer })
    fixture.port.deliver(.webServerStarted(restart, endpoint), source: .webAdministration)
    #expect(fixture.runtime.snapshot.root.webServerRunning)
    #expect(fixture.runtime.snapshot.root.webSession == session)
  }
}
