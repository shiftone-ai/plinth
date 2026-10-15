import KioskCore
import Testing

struct ExhibitionMediatorTests {
  @Test func stopDuringSurfaceCreationReleasesPotentiallyAcquiredSurface() throws {
    let started = try #require(
      handled(
        ExhibitionMediator.reduce(.init(), envelope(.activateExhibition(try fixtureProfile())))))
    let create = try requireToken(started.state.operation)
    let stopped = try #require(
      handled(ExhibitionMediator.reduce(started.state, envelope(.stopExhibition, id: 2))))
    #expect(stopped.state.phase == .quiescing)
    #expect(
      stopped.effects.map(\.kind) == [.cancelOperation(create), .releaseSurface(generation: 1)])
    #expect(stopped.parentEvents.isEmpty)
    let late = try #require(
      handled(
        ExhibitionMediator.reduce(
          stopped.state,
          envelope(.surfaceCreated(create), source: .webSurface, id: 3))))
    #expect(late.reply == .rejected(.staleOperation))
    let release = try requireToken(stopped.state.releaseOperation)
    let released = try #require(
      handled(
        ExhibitionMediator.reduce(
          stopped.state,
          envelope(.surfaceReleased(release), source: .webSurface, id: 4))))
    #expect(released.state.phase == .inactive)
    #expect(released.parentEvents == [.exhibitionStopped])
  }

  @Test func idleStartsWithFirstAcceptedInputAndReschedulesEarlyTimer() throws {
    let ready = try readyExhibition(profile: fixtureProfile())
    #expect(ready.idleDeadline == nil)
    let first = try #require(
      handled(ExhibitionMediator.reduce(ready, envelope(.visitorActivity, id: 4, now: 10))))
    #expect(first.state.idleDeadline == 130)
    #expect(first.effects.map(\.kind) == [.scheduleIdle(deadline: 130)])
    let second = try #require(
      handled(
        ExhibitionMediator.reduce(
          first.state,
          envelope(.visitorActivity, id: 5, now: 20))))
    #expect(second.state.idleDeadline == 140)
    #expect(second.effects.isEmpty)
    let early = try #require(
      handled(
        ExhibitionMediator.reduce(
          second.state,
          envelope(
            .idleDeadlineReached(try requireToken(second.state.idleOperation)), source: .idleClock,
            id: 6, now: 130))))
    #expect(early.effects.map(\.kind) == [.scheduleIdle(deadline: 140)])
    #expect(early.state.phase == .ready)
  }

  @Test func resetWaitsForReleaseAndAcceptsItsOldGenerationToken() throws {
    let ready = try readyExhibition(profile: fixtureProfile())
    let reset = try #require(
      handled(
        ExhibitionMediator.reduce(
          ready,
          envelope(.resetExhibition(.newVisitorSession), id: 4))))
    #expect(reset.state.phase == .quiescing)
    #expect(reset.state.generation == ready.generation + 1)
    #expect(reset.state.inputAvailable == false)
    #expect(
      reset.effects.map(\.kind) == [
        .cancelOperation(try requireToken(ready.operation)),
        .releaseSurface(generation: ready.generation),
      ])
    let late = try #require(
      handled(
        ExhibitionMediator.reduce(
          reset.state,
          envelope(.webFinished(try requireToken(ready.operation)), source: .webSurface, id: 5))))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.state == reset.state)
    let release = try requireToken(reset.state.releaseOperation)
    #expect(release.webGeneration == ready.generation)
    let released = try #require(
      handled(
        ExhibitionMediator.reduce(
          reset.state,
          envelope(.surfaceReleased(release), source: .webSurface, id: 6))))
    #expect(released.state.phase == .recreatingSurface)
    #expect(released.effects.map(\.kind) == [.createSurface(.newVisitorSession)])
    let created = try #require(
      handled(
        ExhibitionMediator.reduce(
          released.state,
          envelope(
            .surfaceCreated(try requireToken(released.state.operation)), source: .webSurface, id: 7)
        )))
    #expect(created.state.phase == .loadingHome)
    #expect(created.effects.map(\.kind) == [.load("https://example.com/home")])
    let finished = try #require(
      handled(
        ExhibitionMediator.reduce(
          created.state,
          envelope(
            .webFinished(try requireToken(created.state.operation)), source: .webSurface, id: 8))))
    #expect(finished.state.phase == .ready)
    #expect(finished.state.idleDeadline == nil)
    #expect(finished.state.idleOperation == nil)
  }

  @Test func recoveryWaitsForBothReleaseAndRetryDeadline() throws {
    let ready = try readyExhibition(profile: fixtureProfile())
    let failed = try #require(
      handled(
        ExhibitionMediator.reduce(
          ready,
          envelope(
            .webFailed(try requireToken(ready.operation), .network), source: .webSurface, id: 4,
            now: 10))))
    #expect(failed.state.phase == .recovering)
    let deadline = try #require(
      handled(
        ExhibitionMediator.reduce(
          failed.state,
          envelope(
            .retryDeadlineReached(try requireToken(failed.state.retryOperation)),
            source: .idleClock, id: 5, now: 12))))
    #expect(deadline.state.phase == .recovering)
    #expect(deadline.effects.isEmpty)
    let released = try #require(
      handled(
        ExhibitionMediator.reduce(
          deadline.state,
          envelope(
            .surfaceReleased(try requireToken(deadline.state.releaseOperation)),
            source: .webSurface, id: 6, now: 12))))
    #expect(released.state.phase == .preparing)
    #expect(released.effects.map(\.kind) == [.createSurface(.newVisitorSession)])
  }

  @Test(arguments: [WebFailure.tls, .policyDenied])
  func policyAndTLSFailuresDoNotRetry(_ failure: WebFailure) throws {
    let ready = try readyExhibition(profile: fixtureProfile())
    let result = try #require(
      handled(
        ExhibitionMediator.reduce(
          ready,
          envelope(
            .webFailed(try requireToken(ready.operation), failure), source: .webSurface, id: 4))))
    #expect(result.state.phase == .unavailable)
    #expect(result.parentEvents == [.exhibitionUnavailable])
    #expect(result.state.retryOperation == nil)
  }

  @Test func knownDisallowedNavigationStopsInsteadOfBubbling() throws {
    let value = try #require(
      handled(
        ExhibitionMediator.reduce(
          .init(),
          envelope(
            .navigationRequested(
              url: "https://example.com", generation: 0, mainFrame: true, newWindow: false,
              isGET: true),
            source: .webSurface))))
    #expect(value.reply == .navigation(.cancel(.staleOperation)))
    #expect(value.effects.isEmpty)
  }
}
