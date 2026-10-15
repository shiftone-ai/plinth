import KioskCore
import KioskPresentation
import Testing

struct ValidationMessagesTests {
  @Test func invalidDraftShowsTheReasonForDisabledSaveAndClearsAfterRepair() throws {
    let origin = try #require(Origin(urlString: "https://example.com"))
    let profile = KioskProfile(
      startURL: "https://example.com/home", navigation: .init(rules: [.init(id: 1, origin: origin)])
    )
    var root = RootState()
    root.mode = .administration
    var administration = AdministrationState()
    administration.draft = ProfileDraft(profile: profile)
    administration.draft?.rules[0].address = "https://"
    administration.draft?.idleTimeoutText = ""
    let invalid = Presenters.settings(root, administration)
    #expect(invalid.canSave == false)
    #expect(
      Set(invalid.validationMessages.map(\.id)).isSuperset(of: [
        .invalidNavigationRules, .invalidIdleTimeout,
      ]))
    administration.draft = ProfileDraft(profile: profile)
    let repaired = Presenters.settings(root, administration)
    #expect(repaired.canSave)
    #expect(repaired.validationMessages.isEmpty)
  }
}
