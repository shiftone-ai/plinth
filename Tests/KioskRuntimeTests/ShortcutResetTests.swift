import KioskCore
import KioskRuntime
import Testing

@MainActor
struct ShortcutResetTests {
  @Test(arguments: [ResetMode.retainWebsiteData, .newVisitorSession])
  func shortcutResetRecreatesExhibitionWithActiveMode(_ mode: ResetMode) throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting(resetMode: mode)
    let runtime = fixture.runtime
    let originalLoad = try #require(runtime.snapshot.exhibition.operation)
    let originalGeneration = runtime.snapshot.exhibition.generation
    let accepted = runtime.send(.shortcutResetRequested, from: .platform)
    #expect(accepted.reply == .accepted)
    #expect(accepted.handler == .root)
    #expect(runtime.snapshot.root.mode == .exhibiting)
    #expect(runtime.snapshot.exhibition.phase == .quiescing)
    #expect(runtime.webProps.props.acceptsInput == false)
    #expect(runtime.snapshot.exhibition.generation > originalGeneration)
    #expect(
      fixture.port.effects.contains { $0.kind == .releaseSurface(generation: originalGeneration) })
    let blockedInput = runtime.send(.nativeInput(.primaryDown, .web), from: .platform)
    guard case .input(let decision) = blockedInput.reply else {
      Issue.record("Expected synchronous input reply")
      return
    }
    #expect(decision.passes == false)
    fixture.port.deliver(.webFinished(originalLoad), source: .webSurface)
    #expect(runtime.snapshot.exhibition.phase == .quiescing)

    let release = try #require(runtime.snapshot.exhibition.releaseOperation)
    fixture.port.deliver(.surfaceReleased(release), source: .webSurface)
    #expect(fixture.port.effects.last?.kind == .createSurface(mode))
    let create = try #require(runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.surfaceCreated(create), source: .webSurface)
    #expect(fixture.port.effects.last?.kind == .load("https://example.com/home"))
    let load = try #require(runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.webFinished(load), source: .webSurface)
    #expect(runtime.snapshot.root.mode == .exhibiting)
    #expect(runtime.snapshot.root.administratorSession == false)
    #expect(runtime.snapshot.exhibition.phase == .ready)
  }

  @Test func shortcutResetRejectsNonExhibitionAndDuplicateRequests() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    #expect(
      runtime.send(.shortcutResetRequested, from: .platform).reply == .rejected(.invalidState))
    try fixture.startExhibiting()
    #expect(
      runtime.send(.shortcutResetRequested, from: .settings).reply == .rejected(.wrongSource))
    #expect(runtime.send(.shortcutResetRequested, from: .platform).reply == .accepted)
    let effectCount = fixture.port.effects.count
    #expect(
      runtime.send(.shortcutResetRequested, from: .platform).reply == .rejected(.invalidState))
    #expect(fixture.port.effects.count == effectCount)
    runtime.stop()
    #expect(
      runtime.send(.shortcutResetRequested, from: .platform).reply == .rejected(.invalidState))
  }

  @Test(arguments: [false, true])
  func shortcutFromShortcutsAppUsesForegroundResumeOnlyOnce(afterActivation: Bool) throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    try fixture.startExhibiting(resetMode: .retainWebsiteData)
    let initialGeneration = runtime.snapshot.exhibition.generation
    runtime.send(.applicationDeactivated, from: .platform)
    #expect(runtime.snapshot.root.mode == .safeHold)
    let release = try #require(runtime.snapshot.exhibition.releaseOperation)
    fixture.port.deliver(.surfaceReleased(release), source: .webSurface)
    #expect(runtime.snapshot.exhibition.phase == .inactive)

    if afterActivation { runtime.send(.applicationActivated, from: .platform) }
    #expect(runtime.send(.shortcutResetRequested, from: .platform).reply == .accepted)
    #expect(
      runtime.send(.shortcutResetRequested, from: .platform).reply == .rejected(.invalidState))
    if !afterActivation { runtime.send(.applicationActivated, from: .platform) }
    #expect(runtime.snapshot.root.mode == .enteringKiosk)
    #expect(runtime.snapshot.exhibition.phase == .inactive)
    #expect(runtime.snapshot.exhibition.generation > initialGeneration)
    #expect(
      runtime.send(.shortcutResetRequested, from: .platform).reply == .rejected(.invalidState))

    let presentation = try #require(runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationApplied(presentation), source: .platform)
    #expect(fixture.port.effects.last?.kind == .createSurface(.retainWebsiteData))
    let create = try #require(runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.surfaceCreated(create), source: .webSurface)
    #expect(fixture.port.effects.last?.kind == .load("https://example.com/home"))
    let load = try #require(runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.webFinished(load), source: .webSurface)
    #expect(runtime.snapshot.root.mode == .exhibiting)
    #expect(runtime.snapshot.exhibition.phase == .ready)
  }

  @Test func shortcutRejectsAfterLastMobileSceneDisconnects() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    try fixture.startExhibiting()
    runtime.send(.applicationDeactivated, from: .platform)
    #expect(runtime.snapshot.root.mobileExhibitionResumePending)
    runtime.send(.mobileLastSceneDisconnected, from: .platform)
    #expect(
      runtime.send(.shortcutResetRequested, from: .platform).reply == .rejected(.invalidState))
  }
}
