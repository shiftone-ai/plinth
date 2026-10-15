import KioskCore
import Testing

struct PointerCaptureTests {
  @Test func failedCaptureRecordsTheSetupIssueAndReleasesResources() throws {
    let requested = try #require(
      handled(
        RootMediator.reduce(
          try external(), envelope(.externalMouseAvailabilityChanged(true), source: .platform))))
    let operation = try #require(requested.state.pointerCaptureOperation)
    let failed = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(
            .externalPointerCaptureCompleted(operation, succeeded: false), source: .platform,
            id: 2))))
    #expect(failed.state.mode == .safeHold)
    #expect(failed.state.pointerCaptureFailed)
    #expect(failed.state.pointerCaptureOperation == nil)
    #expect(!failed.state.externalPointerLocked)
    #expect(failed.state.activeProfile == requested.state.activeProfile)
    #expect(failed.childControls.contains(.init(.exhibition, .stopExhibition)))
    var corrected = failed.state
    corrected.mode = .administration
    corrected.credentialsConfigured = true
    corrected.savedProfile = corrected.activeProfile
    let restarted = try #require(
      handled(
        RootMediator.reduce(
          corrected, envelope(.startExhibitionRequested, source: .settings, id: 3))))
    #expect(!restarted.state.pointerCaptureFailed)
  }

  private func external() throws -> RootState {
    var state = RootState()
    state.mode = .exhibiting
    state.presentationAcquired = true
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    profile.interaction.allowsDrag = true
    state.activeProfile = profile
    state.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true, externalDisplayOnly: true)
    return state
  }

  @Test func mouseConnectionAcquiresLockBeforeAcceptingRawInput() throws {
    let state = try external()
    let requested = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.externalMouseAvailabilityChanged(true), source: .platform))))
    #expect(requested.state.mode == .enteringKiosk)
    #expect(requested.effects.map(\.kind) == [.captureExternalPointer])
    let operation = try #require(requested.state.pointerCaptureOperation)
    let locked = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(
            .externalPointerCaptureCompleted(operation, succeeded: true), source: .platform, id: 2))
      ))
    #expect(locked.state.mode == .exhibiting)
    #expect(locked.state.externalPointerLocked)
    let moved = try #require(
      handled(
        RootMediator.reduce(
          locked.state,
          envelope(
            .externalMouseInput(.move(dx: 20, dy: -20), generation: 4), source: .platform, id: 3),
          context: .init(webAvailable: true, webGeneration: 4))))
    #expect(moved.state.externalPointer == .init(x: 1, y: 0))
    #expect(moved.effects.map(\.kind) == [.controlExternalWeb(.move(.init(x: 1, y: 0)))])
  }

  @Test func cancelledCaptureCannotRelockAuthenticationOrReplaceItsDeadline() throws {
    let requested = try #require(
      handled(
        RootMediator.reduce(
          try external(),
          envelope(.externalMouseAvailabilityChanged(true), source: .platform))))
    let capture = try #require(requested.state.pointerCaptureOperation)
    let unlocked = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(.unlockRequested, source: .platform, id: 2))))
    #expect(unlocked.state.mode == .unlocking)
    #expect(unlocked.state.pointerCaptureOperation == nil)
    #expect(unlocked.effects.map(\.kind).contains(.cancelOperation(capture)))
    #expect(unlocked.effects.map(\.kind).contains(.releaseExternalPointer))
    #expect(unlocked.state.unlockTimeoutOperation != nil)
    let late = try #require(
      handled(
        RootMediator.reduce(
          unlocked.state,
          envelope(
            .externalPointerCaptureCompleted(capture, succeeded: true), source: .platform, id: 3))))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.state == unlocked.state)
  }

  @Test func lostPointerLockStopsWebAndReleasesCapture() throws {
    var state = try external()
    state.externalMouseConnected = true
    state.externalPointerLocked = true
    let lost = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.externalPointerCaptureChanged(locked: false), source: .platform))))
    #expect(lost.state.mode == .safeHold)
    #expect(lost.state.pointerCaptureFailed)
    #expect(!lost.state.externalPointerLocked)
    #expect(lost.effects.map(\.kind).contains(.releaseExternalPointer))
    #expect(lost.childControls.contains(.init(.exhibition, .stopExhibition)))
  }

  @Test func pressMoveReleaseHonorsDragPolicyAndWebGeneration() throws {
    let context = ReadonlyContext(webAvailable: true, webGeneration: 4)
    let state = try external()
    let point = SurfacePoint(x: 0.5, y: 0.5)
    let down = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.externalWebControlRequested(.press(point), generation: 4), source: .platform),
          context: context)))
    #expect(down.state.externalButtonDown)
    var denied = down.state
    denied.activeProfile?.interaction.allowsDrag = false
    #expect(
      handled(
        RootMediator.reduce(
          denied,
          envelope(
            .externalWebControlRequested(.move(.init(x: 0.7, y: 0.5)), generation: 4),
            source: .platform),
          context: context))?.reply == .rejected(.invalidState))
    let up = try #require(
      handled(
        RootMediator.reduce(
          down.state,
          envelope(
            .externalWebControlRequested(.release(point), generation: 4), source: .platform, id: 2),
          context: context)))
    #expect(!up.state.externalButtonDown)
    #expect(up.effects.map(\.kind) == [.controlExternalWeb(.release(point))])
    #expect(
      handled(
        RootMediator.reduce(
          down.state,
          envelope(.externalWebControlRequested(.release(point), generation: 5), source: .platform),
          context: .init(webAvailable: true, webGeneration: 5)))?.reply == .rejected(.invalidState))
  }

  @Test func nativeCursorOutsideFixedOutputIsClampedOnlyWhilePresenting() throws {
    var state = RootState()
    state.mode = .exhibiting
    state.presentationAcquired = true
    state.macDisplays = [.init(id: "display-8", name: "Projector", builtIn: false)]
    state.activeProfile = try fixtureProfile()
    let request = envelope(.nativePointerMoved(.init(x: -0.1, y: 1.2)), source: .platform)
    let clamped = try #require(handled(RootMediator.reduce(state, request)))
    #expect(clamped.effects.map(\.kind) == [.confineNativePointer(.init(x: 0, y: 1))])
    state.activeProfile?.macOutput = .init(mode: .projectionWindow)
    #expect(handled(RootMediator.reduce(state, request))?.effects.isEmpty == true)
    state.mode = .administration
    #expect(handled(RootMediator.reduce(state, request))?.effects.isEmpty == true)
  }
  @Test func cancelledUnlockReacquiresPointerAfterTheReplacementPageIsReady() throws {
    var state = try external()
    state.externalMouseConnected = true
    state.externalPointerLocked = true
    let requested = try #require(
      handled(RootMediator.reduce(state, envelope(.unlockRequested, source: .platform))))
    let cancelled = try #require(
      handled(
        RootMediator.reduce(requested.state, envelope(.unlockCancelled, source: .unlock, id: 2))))
    #expect(!cancelled.state.externalPointerLocked)
    let ready = try #require(
      handled(
        RootMediator.reduce(cancelled.state, envelope(.exhibitionReady, source: .exhibition, id: 3))
      ))
    #expect(ready.state.mode == .enteringKiosk)
    #expect(ready.effects.map(\.kind) == [.captureExternalPointer])
  }

  @Test func mouseDisconnectCancelsTheBrowserPressWithoutStoppingTouchControls() throws {
    var state = try external()
    state.externalMouseConnected = true
    state.externalPointerLocked = true
    state.externalButtonDown = true
    state.externalPressGeneration = 4
    let result = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.externalMouseAvailabilityChanged(false), source: .platform),
          context: .init(webAvailable: true, webGeneration: 4))))
    #expect(result.state.mode == .exhibiting)
    #expect(!result.state.externalButtonDown)
    #expect(
      result.effects.map(\.kind) == [.releaseExternalPointer, .controlExternalWeb(.cancelPress)])
  }

  @Test func inputQueueFailureStopsOnlyItsCurrentExhibition() throws {
    let state = try external()
    let operation = OperationToken(owner: .root, operationID: 3, webGeneration: 4)
    let context = ReadonlyContext(webAvailable: true, webGeneration: 4)
    let failed = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.externalWebControlDeliveryFailed(operation), source: .webSurface),
          context: context)))
    #expect(failed.state.mode == .safeHold)
    #expect(failed.childControls.contains(.init(.exhibition, .stopExhibition)))
    var authenticating = state
    authenticating.mode = .unlocking
    authenticating.unlockID = 20
    let late = try #require(
      handled(
        RootMediator.reduce(
          authenticating,
          envelope(.externalWebControlDeliveryFailed(operation), source: .webSurface),
          context: context)))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.state == authenticating)
  }

}
