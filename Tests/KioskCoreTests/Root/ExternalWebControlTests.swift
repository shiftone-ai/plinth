import KioskCore
import Testing

struct ExternalWebControlTests {
  private func root() throws -> RootState {
    var state = RootState()
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    profile.interaction.allowsScroll = true
    state.mode = .exhibiting
    state.activeProfile = profile
    state.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true,
      supportsExhibitionWindow: false, externalDisplayOnly: true)
    return state
  }

  @Test func controlUsesCurrentGenerationAndRecordsVisitorActivity() throws {
    let state = try root()
    let point = SurfacePoint(x: 0.3, y: 0.7)
    let context = ReadonlyContext(webAvailable: true, webGeneration: 4)
    let request = envelope(
      .externalWebControlRequested(.activate(point), generation: 4), source: .platform)
    let result = try #require(handled(RootMediator.reduce(state, request, context: context)))
    #expect(result.reply == .accepted)
    #expect(result.state.externalPointer == point)
    #expect(result.childControls == [.init(.exhibition, .visitorActivity)])
    let effect = try #require(result.effects.first)
    #expect(effect.token.webGeneration == 4)
    #expect(effect.kind == .controlExternalWeb(.activate(point)))
    let accepted = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.externalWebControlExecutionRequested(effect.token), source: .webSurface),
          context: context)))
    #expect(accepted.reply == .accepted)
    #expect(accepted.effects.isEmpty)
    var unlocking = state
    unlocking.mode = .unlocking
    let delayed = try #require(
      handled(
        RootMediator.reduce(
          unlocking,
          envelope(.externalWebControlExecutionRequested(effect.token), source: .webSurface),
          context: context)))
    #expect(delayed.reply == .rejected(.invalidState))
  }

  @Test(arguments: [AppMode.administration, .safeHold, .enteringKiosk, .unlocking, .leavingKiosk])
  func inputIsRejectedOutsideExhibition(_ mode: AppMode) throws {
    var state = try root()
    state.mode = mode
    let result = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(
            .externalWebControlRequested(.activate(.init(x: 0.5, y: 0.5)), generation: 2),
            source: .platform),
          context: .init(webAvailable: true, webGeneration: 2))))
    #expect(result.reply == .rejected(.invalidState))
    #expect(result.effects.isEmpty)
    #expect(result.childControls.isEmpty)
  }

  @Test func staleGenerationInvalidCoordinatesAndDisallowedScrollAreRejected() throws {
    var state = try root()
    let context = ReadonlyContext(webAvailable: true, webGeneration: 2)
    let stale = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(
            .externalWebControlRequested(.activate(.init(x: 0.5, y: 0.5)), generation: 1),
            source: .platform), context: context)))
    #expect(stale.reply == .rejected(.staleOperation))
    for point in [SurfacePoint(x: .nan, y: 0), .init(x: 1.1, y: 0), .init(x: 0, y: -.infinity)] {
      let invalid = try #require(
        handled(
          RootMediator.reduce(
            state,
            envelope(.externalWebControlRequested(.move(point), generation: 2), source: .platform),
            context: context)))
      #expect(invalid.reply == .rejected(.invalidState))
      #expect(invalid.effects.isEmpty)
    }
    state.activeProfile?.interaction.allowsScroll = false
    let denied = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(
            .externalWebControlRequested(.scroll(dx: 0, dy: 0.1), generation: 2), source: .platform),
          context: context)))
    #expect(denied.reply == .rejected(.invalidState))
    #expect(denied.effects.isEmpty)
  }

  @Test(arguments: [
    (40.0, 120.0, true), (-0.25, -35.5, true),
    (Double.nan, 10.0, false), (0.0, Double.infinity, false),
  ])
  func scrollUsesFinitePixelDeltas(dx: Double, dy: Double, accepted: Bool) throws {
    let control = ExternalWebControl.scroll(dx: dx, dy: dy)
    let result = try #require(
      handled(
        RootMediator.reduce(
          try root(),
          envelope(.externalWebControlRequested(control, generation: 2), source: .platform),
          context: .init(webAvailable: true, webGeneration: 2))))
    #expect(result.reply == (accepted ? .accepted : .rejected(.invalidState)))
    #expect(result.effects.map(\.kind) == (accepted ? [.controlExternalWeb(control)] : []))
  }
}
