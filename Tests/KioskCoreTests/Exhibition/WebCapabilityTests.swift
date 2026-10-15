import KioskCore
import Testing

struct WebCapabilityTests {
  @Test(arguments: [
    ("https://embedded.example.org", NavigationDecision.allow),
    ("about:blank", .allow), ("file:///tmp/private", .cancel(.invalidURL)),
    ("mailto:staff@example.com", .cancel(.invalidURL)),
    ("customapp://open", .cancel(.invalidURL)),
  ])
  func embeddedFramesAllowWebContentButCannotLaunchExternalSchemes(
    _ address: String, _ expected: NavigationDecision
  ) throws {
    let state = try readyExhibition(profile: fixtureProfile())
    let result = try #require(
      handled(
        ExhibitionMediator.reduce(
          state,
          envelope(
            .navigationRequested(
              url: address, generation: state.generation, mainFrame: false, newWindow: false,
              isGET: true), source: .webSurface))))
    #expect(result.reply == .navigation(expected))
    #expect(result.state == state)
    #expect(result.effects.isEmpty)
  }
  @Test(arguments: WebCapability.allCases)
  func restrictedWebFeaturesAreRejectedByExhibition(_ capability: WebCapability) throws {
    let state = try readyExhibition(profile: fixtureProfile())
    let result = try #require(
      handled(
        ExhibitionMediator.reduce(
          state,
          envelope(
            .webCapabilityRequested(capability, generation: state.generation), source: .webSurface))
      ))
    #expect(result.reply == .rejected(.unsupportedWindow))
    #expect(result.state == state)
    #expect(result.effects.isEmpty)
  }

  @Test func invalidOriginDraftIsRetainedButCannotBeSaved() throws {
    var draft = ProfileDraft(profile: try fixtureProfile())
    draft.rules[0].address = "https://"
    let result = try #require(
      handled(
        AdministrationMediator.reduce(
          .init(),
          envelope(.draftChanged(draft), source: .navigationRules), mode: .administration)))
    #expect(result.state.draft?.rules[0].address == "https://")
    #expect(result.state.draft?.validatedProfile == nil)
  }

  @Test func originRuleIdentityAllocationHandlesMaximumStoredID() throws {
    var state = AdministrationState()
    state.draft = ProfileDraft(profile: try fixtureProfile())
    state.draft?.rules = [.init(id: UInt64.max, address: "https://example.com")]
    let added = try #require(
      handled(
        AdministrationMediator.reduce(
          state,
          envelope(.addOriginRuleRequested, source: .navigationRules), mode: .administration)))
    #expect(added.state.draft?.rules.map(\.id) == [UInt64.max, 1])
    #expect(added.reply == .accepted)
  }
}
