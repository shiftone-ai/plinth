import KioskCore
import Testing

struct WebPointerLifecycleTests {
  @Test(arguments: [false, true])
  func webExitReleasesPointerBeforeStoppingExhibition(restart: Bool) throws {
    let state = try lockedExternal()
    let event: Event = restart ? .webRestartExhibitionRequested : .webStopExhibitionRequested
    let exit = try #require(
      handled(RootMediator.reduce(state, envelope(event, source: .webAdministration))))
    #expect(exit.reply == .accepted)
    #expect(exit.state.mode == .leavingKiosk)
    #expect(!exit.state.externalPointerLocked)
    #expect(exit.effects.map(\.kind).contains(.releaseExternalPointer))
    #expect(exit.childControls.contains(.init(.exhibition, .stopExhibition)))
  }

  @Test func webResumeCapturesPointerAgainAfterPause() throws {
    let state = try lockedExternal()
    let stopping = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.webStopExhibitionRequested, source: .webAdministration))))
    let paused = try #require(
      handled(
        RootMediator.reduce(
          stopping.state, envelope(.exhibitionStopped, source: .exhibition, id: 2))))
    #expect(paused.state.mode == .paused)
    #expect(!paused.state.externalPointerLocked)
    let resuming = try #require(
      handled(
        RootMediator.reduce(
          paused.state, envelope(.webResumeExhibitionRequested, source: .webAdministration, id: 3)))
    )
    let release = try #require(resuming.state.presentationOperation)
    let released = try #require(
      handled(
        RootMediator.reduce(
          resuming.state, envelope(.presentationReleased(release), source: .platform, id: 4))))
    let presentation = try #require(released.state.presentationOperation)
    let applied = try #require(
      handled(
        RootMediator.reduce(
          released.state, envelope(.presentationApplied(presentation), source: .platform, id: 5))))
    let ready = try #require(
      handled(
        RootMediator.reduce(
          applied.state, envelope(.exhibitionReady, source: .exhibition, id: 6))))
    #expect(ready.state.pointerCaptureOperation != nil)
    #expect(ready.effects.map(\.kind).contains(.captureExternalPointer))
  }

  private func lockedExternal() throws -> RootState {
    var state = RootState()
    state.mode = .exhibiting
    state.presentationAcquired = true
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    state.activeProfile = profile
    state.savedProfile = profile
    state.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true, externalDisplayOnly: true)
    state.externalMouseConnected = true
    state.externalPointerLocked = true
    return state
  }
}
