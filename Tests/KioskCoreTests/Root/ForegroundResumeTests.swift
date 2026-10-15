import KioskCore
import Testing

struct ForegroundResumeTests {
  @Test(arguments: [ExhibitionDestination.device, .externalDisplay])
  func returningAfterAnInterruptionWaitsForTheOldSurface(destination: ExhibitionDestination) throws
  {
    let state = try exhibiting(destination: destination)
    let left = try step(state, .applicationDeactivated, id: 1)
    #expect(left.state.mode == .safeHold)
    let backgrounded = try step(left.state, .applicationDeactivated, id: 2)
    let returning = try step(backgrounded.state, .applicationActivated, id: 3)
    #expect(returning.state.mode == .safeHold)
    #expect(returning.effects.isEmpty)
    #expect(returning.childControls == [.init(.exhibition, .stopExhibition)])
    let resumed = try step(returning.state, .exhibitionStopped, source: .exhibition, id: 4)
    #expect(resumed.state.mode == .enteringKiosk)
    #expect(resumed.state.activeProfile == state.activeProfile)
    #expect(resumed.effects.count == 1)
    #expect(resumed.state.administratorSession == false)
  }

  @Test(arguments: [Event.systemWillSleep, .displayCountChanged(0)])
  func aDifferentStopCancelsResumption(_ event: Event) throws {
    let left = try step(exhibiting(), .applicationDeactivated, id: 1)
    let stopped = try step(left.state, event, id: 2)
    let returning = try step(stopped.state, .applicationActivated, id: 3)
    let completed = try step(returning.state, .exhibitionStopped, source: .exhibition, id: 4)
    #expect(completed.state.mode == .safeHold)
    #expect(completed.effects.isEmpty)
  }

  @Test func disconnectWhileAwayDoesNotResumeAfterReconnect() throws {
    let state = try exhibiting(destination: .externalDisplay)
    let left = try step(state, .applicationDeactivated, id: 1)
    let disconnected = try step(
      left.state,
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)), id: 2)
    let reconnected = try step(
      disconnected.state, .mobileDisplaysChanged(try #require(state.mobileDisplays)), id: 3)
    let returning = try step(reconnected.state, .applicationActivated, id: 4)
    let completed = try step(returning.state, .exhibitionStopped, source: .exhibition, id: 5)
    #expect(completed.state.mode == .safeHold)
    #expect(completed.effects.isEmpty)
  }

  @Test func openingAuthenticationCancelsAutomaticResumption() throws {
    let left = try step(exhibiting(), .applicationDeactivated, id: 1)
    let unlocking = try step(left.state, .unlockRequested, id: 2)
    let returning = try step(unlocking.state, .applicationActivated, id: 3)
    #expect(returning.state.mode == .unlocking)
    let cancelled = try step(returning.state, .unlockCancelled, id: 4)
    let active = try step(cancelled.state, .applicationActivated, id: 5)
    let completed = try step(active.state, .exhibitionStopped, source: .exhibition, id: 6)
    #expect(completed.state.mode == .safeHold)
    #expect(completed.effects.isEmpty)
  }

  @Test(arguments: [false, true])
  func externalSceneCanBecomeReadyAfterActivation(leavesAgain: Bool) throws {
    let state = try exhibiting(destination: .externalDisplay)
    let left = try step(state, .applicationDeactivated, id: 1)
    let unavailable = try step(
      left.state,
      .mobileDisplaysChanged(
        .init(deviceAvailable: true, externalAvailable: false, externalConnected: true)), id: 2)
    let active = try step(unavailable.state, .applicationActivated, id: 3)
    #expect(active.childControls.isEmpty)
    let waiting =
      leavesAgain ? try step(active.state, .applicationDeactivated, id: 4).state : active.state
    let ready = try step(
      waiting, .mobileDisplaysChanged(try #require(state.mobileDisplays)), id: 5)
    #expect(
      ready.childControls == (leavesAgain ? [] : [.init(.exhibition, .stopExhibition)]))
    if !leavesAgain {
      let resumed = try step(ready.state, .exhibitionStopped, source: .exhibition, id: 6)
      #expect(resumed.state.mode == .enteringKiosk)
      #expect(resumed.state.activeProfile == state.activeProfile)
    }
  }

  @Test func physicalDisconnectCancelsWaitingForAnExternalScene() throws {
    let state = try exhibiting(destination: .externalDisplay)
    let left = try step(state, .applicationDeactivated, id: 1)
    let unavailable = try step(
      left.state,
      .mobileDisplaysChanged(
        .init(deviceAvailable: true, externalAvailable: false, externalConnected: true)), id: 2)
    let active = try step(unavailable.state, .applicationActivated, id: 3)
    let disconnected = try step(
      active.state,
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)), id: 4)
    let reconnected = try step(
      disconnected.state, .mobileDisplaysChanged(try #require(state.mobileDisplays)), id: 5)
    #expect(reconnected.state.foregroundResume == .none)
    #expect(reconnected.childControls.isEmpty)
  }

  private func exhibiting(destination: ExhibitionDestination = .device) throws -> RootState {
    var state = RootState()
    var profile = try fixtureProfile()
    profile.exhibitionDestination = destination
    state.activeProfile = profile
    state.credentialsConfigured = true
    state.mode = .exhibiting
    state.presentationAcquired = true
    state.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true, externalDisplayOnly: true)
    return state
  }

  private func step(
    _ state: RootState, _ event: Event, source: NodeID = .platform, id: UInt64
  ) throws -> Transition<RootState> {
    try #require(handled(RootMediator.reduce(state, envelope(event, source: source, id: id))))
  }
}
