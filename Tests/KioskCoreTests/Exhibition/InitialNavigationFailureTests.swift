import KioskCore
import Testing

struct InitialNavigationFailureTests {
  @Test(arguments: [
    ("https://blocked.example.org", true, RejectionReason.urlBlocked),
    ("https://example.com/download", false, .unsupportedWindow),
  ])
  func rejectedInitialNavigationLeavesPreparingWithoutRetry(
    _ address: String, _ supported: Bool, _ reason: RejectionReason
  ) throws {
    let profile = try fixtureProfile()
    let activated = try #require(
      handled(ExhibitionMediator.reduce(.init(), envelope(.activateExhibition(profile)))))
    let create = try requireToken(activated.state.operation)
    let loading = try #require(
      handled(
        ExhibitionMediator.reduce(
          activated.state,
          envelope(.surfaceCreated(create), source: .webSurface, id: 2))))
    let denied = try #require(
      handled(
        ExhibitionMediator.reduce(
          loading.state,
          envelope(
            .navigationRequested(
              url: address, generation: loading.state.generation, mainFrame: true,
              newWindow: false, isGET: true, supportedContent: supported), source: .webSurface,
            id: 3))))
    #expect(denied.reply == .navigation(.cancel(reason)))
    #expect(denied.state.phase == .unavailable)
    #expect(denied.state.retryOperation == nil)
    #expect(denied.parentEvents == [.exhibitionUnavailable])
  }
}
