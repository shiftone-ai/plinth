import KioskCore
import Testing

struct ProfileRevisionTests {
  @Test func exhaustedRevisionIsRejectedWithoutTrappingOrEnteringSave() throws {
    var profile = try fixtureProfile()
    profile.revision = UInt64.max
    #expect(profile.validationIssues.isEmpty)
    var administration = AdministrationState()
    administration.savedProfile = profile
    var draft = ProfileDraft(profile: profile)
    draft.profile.interaction.allowsScroll = true
    administration.draft = draft
    let save = try #require(
      handled(
        AdministrationMediator.reduce(
          administration,
          envelope(.saveDraftRequested, source: .settings), mode: .administration)))
    #expect(save.reply == .rejected(.invalidProfile))
    #expect(save.state.saving == false)
    #expect(save.effects.isEmpty)
    var root = RootState()
    root.mode = .administration
    root.savedProfile = profile
    var candidate = profile
    candidate.revision = 1
    let commit = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.profileCommitRequested(candidate), source: .administration))))
    #expect(commit.reply == .rejected(.invalidProfile))
    #expect(commit.effects.isEmpty)
  }
}
