import KioskCore
import Testing

struct WebAdministrationDraftTests {
  @Test func remoteEditsUseTheNativeDraftAndSaveRequest() throws {
    var state = AdministrationState()
    state.draft = ProfileDraft(profile: try profile())

    let edited = try #require(
      AdministrationMediator.reduce(
        state,
        envelope(
          .draftEdited(.startURL("https://example.com/next")),
          source: .webAdministration), mode: .administration
      ).transition)
    #expect(edited.reply == .accepted)
    #expect(edited.state.draft?.profile.startURL == "https://example.com/next")

    let saving = try #require(
      AdministrationMediator.reduce(
        edited.state, envelope(.saveDraftRequested, source: .webAdministration),
        mode: .administration
      ).transition)
    #expect(saving.reply == .accepted)
    #expect(saving.state.saving)
    #expect(saving.parentEvents.count == 1)
    guard case .profileCommitRequested(let profile) = saving.parentEvents[0] else {
      Issue.record("Expected the same Root commit request as native settings")
      return
    }
    #expect(profile.startURL == "https://example.com/next")
    #expect(
      AdministrationMediator.reduce(
        saving.state,
        envelope(
          .draftEdited(.startURL("https://example.com/later")),
          source: .webAdministration), mode: .administration
      ).transition?.reply
        == .rejected(.invalidState))
  }

  @Test func remoteCannotReplaceTheWholeDraftOrChangeWebPermissionOrEditDuringUnlock()
    throws
  {
    var state = AdministrationState()
    state.draft = ProfileDraft(profile: try profile())
    #expect(
      AdministrationMediator.reduce(
        state, envelope(.draftChanged(state.draft!), source: .webAdministration),
        mode: .administration
      ).transition?.reply == .rejected(.wrongSource))
    #expect(
      AdministrationMediator.reduce(
        state,
        envelope(
          .draftEdited(.webAdministrationEnabled(false)),
          source: .webAdministration), mode: .administration
      ).transition?.reply
        == .rejected(.wrongSource))
    #expect(
      AdministrationMediator.reduce(
        state,
        envelope(
          .draftEdited(.startURL("https://example.com/next")),
          source: .webAdministration), mode: .unlocking
      ).transition?.reply
        == .rejected(.invalidState))
    #expect(
      AdministrationMediator.reduce(
        state, envelope(.saveDraftRequested, source: .webAdministration),
        mode: .unlocking
      ).transition?.reply == .rejected(.invalidState))
  }

  @Test func remoteMacOutputRequiresAConnectedDisplay() throws {
    var state = AdministrationState()
    state.draft = ProfileDraft(profile: try profile())
    let displays = [DisplayDescriptor(id: "screen-1", name: "Display", builtIn: true)]
    let mac = WebOutputOptions(macDisplays: displays)
    #expect(
      AdministrationMediator.reduce(
        state,
        envelope(.draftEdited(.macDisplayID("missing")), source: .webAdministration),
        mode: .administration, webOutputOptions: mac
      ).transition?.reply
        == .rejected(.unsupportedDisplays))
    #expect(
      AdministrationMediator.reduce(
        state,
        envelope(.draftEdited(.macDisplayID("screen-1")), source: .webAdministration),
        mode: .administration, webOutputOptions: mac
      ).transition?.reply == .accepted)

  }

  @Test func remoteMobileOutputRequiresAnAvailableMode() throws {
    var state = AdministrationState()
    state.draft = ProfileDraft(profile: try profile())
    let resolution = ExternalDisplayMode(width: 1920, height: 1080)
    let mobile = WebOutputOptions(
      mobileDisplays: .init(
        deviceAvailable: true, externalAvailable: true, supportsExternalDisplay: true,
        displayModes: [resolution]))
    let destination = try #require(
      AdministrationMediator.reduce(
        state,
        envelope(
          .draftEdited(.exhibitionDestination(.externalDisplay)),
          source: .webAdministration), mode: .administration,
        webOutputOptions: mobile
      ).transition)
    #expect(destination.reply == .accepted)
    #expect(
      AdministrationMediator.reduce(
        destination.state,
        envelope(
          .draftEdited(.externalDisplayMode(.init(width: 1280, height: 720))),
          source: .webAdministration), mode: .administration,
        webOutputOptions: mobile
      ).transition?.reply == .rejected(.unsupportedDisplays))
    #expect(
      AdministrationMediator.reduce(
        destination.state,
        envelope(.draftEdited(.externalDisplayMode(resolution)), source: .webAdministration),
        mode: .administration, webOutputOptions: mobile
      ).transition?.reply == .accepted)
    #expect(
      AdministrationMediator.reduce(
        state,
        envelope(
          .draftEdited(.macOutputMode(.projectionWindow)),
          source: .webAdministration), mode: .administration,
        webOutputOptions: mobile
      ).transition?.reply == .rejected(.unsupportedDisplays))
  }

  private func profile() throws -> KioskProfile {
    let origin = try #require(Origin(urlString: "https://example.com"))
    return KioskProfile(
      startURL: "https://example.com/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)]),
      webAdministrationEnabled: true)
  }
}

extension Mediation {
  fileprivate var transition: Transition<State>? {
    if case .handled(let value) = self { return value }
    return nil
  }
}
