import KioskCore
import Testing

struct PasscodeSubmissionTests {
  @Test func fieldEditsPreserveOtherCurrentDraftFields() throws {
    let state = AdministrationState()
    let first = try #require(
      handled(
        AdministrationMediator.reduce(
          state, envelope(.draftEdited(.startURL("https://example.com/home")), source: .settings),
          mode: .administration)))
    let second = try #require(
      handled(
        AdministrationMediator.reduce(
          first.state, envelope(.draftEdited(.allowsHTTP(true)), source: .settings),
          mode: .administration)))
    #expect(second.state.draft?.profile.startURL == "https://example.com/home")
    #expect(second.state.draft?.profile.navigation.allowsHTTP == true)
    #expect(second.effects.isEmpty)
    #expect(second.reply == .accepted)
  }
  @Test func submissionUsesTheLatestEditedPasscode() throws {
    var state = AdministrationState()
    state.unlockID = 11
    state.passcode = "old-rendered-value"
    let edited = try #require(
      handled(
        AdministrationMediator.reduce(
          state,
          envelope(.passcodeEdited("current-input-value"), source: .unlock), mode: .unlocking)))
    let submitted = try #require(
      handled(
        AdministrationMediator.reduce(
          edited.state,
          envelope(.passcodeSubmitted, source: .unlock, id: 2), mode: .unlocking)))
    let token = try #require(submitted.state.verification)
    #expect(submitted.effects == [.init(token, .verifyPasscode("current-input-value"))])
    #expect(submitted.state.passcode.isEmpty)
  }

  @Test func configurationBubblesTheCurrentInputToRoot() throws {
    var state = AdministrationState()
    state.passcode = "current-admin-passcode"
    let requested = try #require(
      handled(
        AdministrationMediator.reduce(
          state,
          envelope(.configurePasscodeRequested, source: .settings), mode: .administration)))
    #expect(requested.parentEvents == [.credentialConfigurationRequested("current-admin-passcode")])
    #expect(requested.effects.isEmpty)
    #expect(requested.reply == .accepted)
  }
}
