import KioskCore
import KioskRuntime
import Testing

@MainActor
struct WebExhibitionRestartTests {
  @Test func exhibitionSaveKeepsTheActiveProfileUntilRestartAndNeverOpensAdministration()
    throws
  {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    let oldURL = try #require(fixture.runtime.snapshot.root.activeProfile?.startURL)
    #expect(fixture.runtime.snapshot.administration.draft?.profile.startURL == oldURL)
    #expect(
      fixture.runtime.send(
        .draftEdited(.startURL("https://example.com/next")), from: .webAdministration
      ).reply == .accepted)
    #expect(
      fixture.runtime.send(
        .webRestartExhibitionRequested,
        from: .webAdministration
      ).reply == .rejected(.unsavedDraft))

    #expect(
      fixture.runtime.send(.saveDraftRequested, from: .webAdministration).reply
        == .accepted)
    let save = try #require(
      fixture.port.effects.last { effect in
        if case .saveProfile = effect.kind { return true }
        return false
      })
    guard case .saveProfile(let profile) = save.kind else { return }
    #expect(fixture.runtime.snapshot.root.activeProfile?.startURL == oldURL)
    fixture.port.deliver(.profileSaved(save.token, profile), source: .profileRepository)
    #expect(
      fixture.runtime.snapshot.root.savedProfile?.startURL
        == "https://example.com/next")
    #expect(fixture.runtime.snapshot.root.activeProfile?.startURL == oldURL)

    #expect(
      fixture.runtime.send(
        .webRestartExhibitionRequested,
        from: .webAdministration
      ).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.mode == .leavingKiosk)
    let release = try #require(fixture.runtime.snapshot.exhibition.releaseOperation)
    fixture.port.deliver(.surfaceReleased(release), source: .webSurface)
    #expect(fixture.runtime.snapshot.root.mode == .leavingKiosk)
    let presentationRelease = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationReleased(presentationRelease), source: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .enteringKiosk)
    #expect(
      fixture.runtime.snapshot.root.activeProfile?.startURL
        == "https://example.com/next")
    try finishEnteringExhibition(fixture, expectedURL: "https://example.com/next")
    #expect(fixture.runtime.snapshot.root.mode == .exhibiting)
    #expect(!fixture.runtime.snapshot.root.webRestartFailed)
    #expect(!fixture.runtime.snapshot.root.administratorSession)
  }

  private func finishEnteringExhibition(
    _ fixture: RuntimeFixture, expectedURL: String
  ) throws {
    let presentation = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationApplied(presentation), source: .platform)
    let create = try #require(fixture.runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.surfaceCreated(create), source: .webSurface)
    let load = try #require(fixture.runtime.snapshot.exhibition.operation)
    fixture.port.deliver(
      .webCommitted(load, url: expectedURL),
      source: .webSurface)
    fixture.port.deliver(.webFinished(load), source: .webSurface)
  }

  @Test func restartRefusesUnlockAndSafeHoldAndReportsPresentationFailure() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    fixture.runtime.send(.unlockRequested, from: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .unlocking)
    #expect(
      fixture.runtime.send(
        .webRestartExhibitionRequested,
        from: .webAdministration
      ).reply == .rejected(.invalidState))
    fixture.runtime.send(.unlockCancelled, from: .unlock)
    #expect(fixture.runtime.snapshot.root.mode == .exhibiting)
    #expect(
      fixture.runtime.send(
        .webRestartExhibitionRequested,
        from: .webAdministration
      ).reply == .accepted)
    let release = try #require(fixture.runtime.snapshot.exhibition.releaseOperation)
    fixture.port.deliver(.surfaceReleased(release), source: .webSurface)
    let presentationRelease = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationReleased(presentationRelease), source: .platform)
    let presentation = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationFailed(presentation), source: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .safeHold)
    #expect(fixture.runtime.snapshot.root.webRestartFailed)
    #expect(
      fixture.runtime.send(
        .webRestartExhibitionRequested,
        from: .webAdministration
      ).reply == .rejected(.invalidState))
  }

  @Test func stopShowsPausedStateAndLocalUnlockStillRequiresAuthentication() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    #expect(
      fixture.runtime.send(
        .webStopExhibitionRequested,
        from: .webAdministration
      ).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.mode == .leavingKiosk)
    let release = try #require(fixture.runtime.snapshot.exhibition.releaseOperation)
    fixture.port.deliver(.surfaceReleased(release), source: .webSurface)
    #expect(fixture.runtime.snapshot.root.mode == .paused)
    #expect(fixture.runtime.snapshot.root.presentationAcquired)
    #expect(fixture.runtime.snapshot.exhibition.phase == .inactive)
    #expect(fixture.runtime.rootProps.props.showsAdministration == false)
    #expect(fixture.runtime.rootProps.props.showsUnlock == false)
    #expect(fixture.runtime.webAdministrationProps.props.mode == .paused)

    #expect(fixture.runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.mode == .unlocking)
    #expect(fixture.runtime.rootProps.props.showsAdministration == false)
    fixture.runtime.send(.unlockCancelled, from: .unlock)
    #expect(fixture.runtime.snapshot.root.mode == .paused)
    #expect(
      fixture.runtime.send(
        .webResumeExhibitionRequested,
        from: .webAdministration
      ).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.mode == .leavingKiosk)
    let presentation = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationReleased(presentation), source: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .enteringKiosk)
    #expect(fixture.runtime.rootProps.props.showsAdministration == false)
  }

  @Test func resumeRejectsUnsavedDraftAndSafeHoldCanTryAgain() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    fixture.runtime.send(.webStopExhibitionRequested, from: .webAdministration)
    let release = try #require(fixture.runtime.snapshot.exhibition.releaseOperation)
    fixture.port.deliver(.surfaceReleased(release), source: .webSurface)
    #expect(fixture.runtime.snapshot.root.mode == .paused)
    fixture.runtime.send(
      .draftEdited(.startURL("https://example.com/next")),
      from: .webAdministration)
    #expect(
      fixture.runtime.send(
        .webResumeExhibitionRequested,
        from: .webAdministration
      ).reply == .rejected(.unsavedDraft))
    fixture.runtime.send(.discardDraftRequested, from: .webAdministration)
    #expect(
      fixture.runtime.send(
        .webResumeExhibitionRequested,
        from: .webAdministration
      ).reply == .accepted)
    let presentationRelease = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationReleased(presentationRelease), source: .platform)
    let presentation = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationFailed(presentation), source: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .safeHold)
    #expect(fixture.runtime.webAdministrationProps.props.webRestartFailed)
    #expect(
      fixture.runtime.send(
        .webResumeExhibitionRequested,
        from: .webAdministration
      ).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.mode == .enteringKiosk)
    #expect(fixture.runtime.rootProps.props.showsAdministration == false)
  }
}
