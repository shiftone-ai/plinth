import KioskCore
import Testing

struct PointerSetupRecoveryTests {
  @Test func returningFromPointerSetupWaitsForTheOldSurfaceBeforeReentering() throws {
    var stopped = try external()
    stopped.mode = .safeHold
    stopped.pointerCaptureFailed = true
    stopped.externalMouseConnected = true
    let returning = try #require(
      handled(RootMediator.reduce(stopped, envelope(.applicationActivated, source: .platform))))
    #expect(returning.state.foregroundResume == .awaitingStop)
    #expect(returning.childControls == [.init(.exhibition, .stopExhibition)])
    #expect(returning.effects.isEmpty)
    let ready = try #require(
      handled(
        RootMediator.reduce(
          returning.state, envelope(.exhibitionStopped, source: .exhibition, id: 2))))
    #expect(ready.state.mode == .enteringKiosk)
    #expect(ready.state.foregroundResume == .none)
    #expect(ready.state.pointerCaptureFailed == false)
    #expect(ready.state.activeProfile == stopped.activeProfile)
    #expect(ready.state.presentationOperation != nil)
  }

  @Test(arguments: [false, true])
  func returningDoesNotRestartAnUnrelatedStopOrAuthentication(authenticating: Bool) throws {
    var stopped = try external()
    stopped.mode = authenticating ? .unlocking : .safeHold
    stopped.pointerCaptureFailed = authenticating
    let result = try #require(
      handled(RootMediator.reduce(stopped, envelope(.applicationActivated, source: .platform))))
    #expect(result.state == stopped)
    #expect(result.effects.isEmpty)
    #expect(result.childControls.isEmpty)
  }

  @Test func leavingAgainCancelsThePendingPointerSetupRetry() throws {
    var stopped = try external()
    stopped.mode = .safeHold
    stopped.pointerCaptureFailed = true
    stopped.foregroundResume = .awaitingStop
    let left = try #require(
      handled(RootMediator.reduce(stopped, envelope(.applicationDeactivated, source: .platform))))
    let released = try #require(
      handled(
        RootMediator.reduce(
          left.state, envelope(.exhibitionStopped, source: .exhibition, id: 2))))
    #expect(released.state.mode == .safeHold)
    #expect(released.state.foregroundResume != .awaitingStop)
    #expect(released.effects.isEmpty)
  }

  private func external() throws -> RootState {
    var state = RootState()
    state.mode = .exhibiting
    state.presentationAcquired = true
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    state.activeProfile = profile
    state.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true, externalDisplayOnly: true)
    return state
  }
}
