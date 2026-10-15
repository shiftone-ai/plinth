import KioskCore
import Testing

struct PageLoadTests {
  @Test func normalPageLoadIsSeparateFromForcedSurfaceRecovery() throws {
    let ready = try readyExhibition(profile: fixtureProfile())
    let token = try requireToken(ready.operation)
    let loading = try #require(
      handled(
        ExhibitionMediator.reduce(
          ready,
          envelope(.webNavigationBegan(token), source: .webSurface))))
    #expect(loading.state.phase == .ready)
    #expect(loading.state.pageLoad == .loading)
    #expect(loading.state.inputAvailable)
    #expect(loading.effects.isEmpty)
    let finished = try #require(
      handled(
        ExhibitionMediator.reduce(
          loading.state,
          envelope(.webFinished(token), source: .webSurface, id: 2))))
    #expect(finished.state.pageLoad == .settled)
    #expect(finished.state.phase == .ready)
    #expect(finished.parentEvents.isEmpty)
    let expired = OperationToken(
      owner: .exhibition, operationID: 999, webGeneration: ready.generation)
    let stale = try #require(
      handled(
        ExhibitionMediator.reduce(
          finished.state,
          envelope(.webNavigationBegan(expired), source: .webSurface, id: 3))))
    #expect(stale.reply == .rejected(.staleOperation))
    #expect(stale.state == finished.state)
  }
}
