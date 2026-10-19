import KioskCore
import KioskRuntime
import Testing

@MainActor
struct WebAdministrationLifecycleTests {
  @Test func lastMobileSceneDisconnectEndsWebAuthentication() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let start = try #require(fixture.runtime.snapshot.root.webServerOperation)
    fixture.port.deliver(
      .webServerStarted(
        start, WebServerEndpoint(url: "http://192.0.2.1:47623/", origins: [])),
      source: .webAdministration)
    let sessionToken = String(repeating: "a", count: 64)
    fixture.runtime.send(.webAuthenticationVerified(sessionToken), from: .administration)
    #expect(fixture.runtime.snapshot.root.webSession != nil)
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: false, externalAvailable: false)),
      from: .platform)
    fixture.runtime.send(.mobileLastSceneDisconnected, from: .platform)
    #expect(fixture.runtime.snapshot.root.webSession == nil)
    #expect(!fixture.runtime.snapshot.root.webServerRunning)
    #expect(fixture.port.effects.contains { $0.kind == .stopWebServer })
    #expect(
      fixture.runtime.send(
        .webSessionRequested(sessionToken, activity: true), from: .webAdministration
      ).reply == .rejected(.unauthenticated))
    #expect(
      fixture.runtime.send(.webAuthenticationVerified(sessionToken), from: .administration).reply
        == .rejected(.invalidState))
  }

  @Test func delayedBootstrapWhileBackgroundedWaitsForForeground() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    fixture.runtime.send(.applicationDeactivated, from: .platform)
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    #expect(fixture.runtime.snapshot.root.webServerOperation == nil)
    fixture.runtime.send(.applicationActivated, from: .platform)
    #expect(fixture.runtime.snapshot.root.webServerOperation != nil)
  }

  @Test func saveCompletingAfterBackgroundDoesNotRestartMobileServer() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let presentation = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationApplied(presentation), source: .platform)
    let create = try #require(fixture.runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.surfaceCreated(create), source: .webSurface)
    let load = try #require(fixture.runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.webCommitted(load, url: profile.startURL), source: .webSurface)
    fixture.port.deliver(.webFinished(load), source: .webSurface)
    #expect(fixture.runtime.snapshot.root.mode == .exhibiting)
    let start = try #require(fixture.runtime.snapshot.root.webServerOperation)
    fixture.port.deliver(
      .webServerStarted(
        start,
        WebServerEndpoint(url: "http://192.0.2.1:47623/", origins: [])), source: .webAdministration)
    #expect(
      fixture.runtime.send(
        .draftEdited(.startURL("https://example.com/next")), from: .webAdministration
      ).reply
        == .accepted)
    #expect(fixture.runtime.send(.saveDraftRequested, from: .webAdministration).reply == .accepted)
    let save = try #require(fixture.runtime.snapshot.root.saveOperation)
    let saved = try #require(fixture.runtime.snapshot.root.pendingProfile)
    fixture.runtime.send(.applicationDeactivated, from: .platform)
    fixture.port.deliver(.profileSaved(save, saved), source: .profileRepository)
    #expect(fixture.runtime.snapshot.root.webServerOperation == nil)
    #expect(!fixture.runtime.snapshot.root.webServerRunning)
    fixture.runtime.send(.applicationActivated, from: .platform)
    #expect(fixture.runtime.snapshot.root.webServerOperation != nil)
  }

  @Test func failedListenerAfterStartupRemovesItsURLAndAllowsRetry() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let start = try #require(fixture.runtime.snapshot.root.webServerOperation)
    fixture.port.deliver(
      .webServerStarted(
        start,
        WebServerEndpoint(url: "http://192.0.2.1:47623/", origins: [])), source: .webAdministration)
    #expect(fixture.runtime.snapshot.root.webServerRunning)
    fixture.port.deliver(.webServerStoppedUnexpectedly(.unavailable), source: .webAdministration)
    #expect(!fixture.runtime.snapshot.root.webServerRunning)
    #expect(fixture.runtime.snapshot.root.webServerURL == nil)
    #expect(fixture.runtime.snapshot.root.webServerFailure == .unavailable)
  }

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
