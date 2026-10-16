import KioskCore
import Testing

struct AdministrationMediatorTests {
  @Test func openingLocalAdministrationPreservesUnsavedWebDraft() throws {
    let profile = try fixtureProfile()
    var state = AdministrationState()
    state.savedProfile = profile
    state.draft = ProfileDraft(profile: profile)
    let changed = try #require(
      handled(
        AdministrationMediator.reduce(
          state,
          envelope(
            .draftEdited(.startURL("https://example.com/unsaved")),
            source: .webAdministration), mode: .exhibiting, webEnabled: true)))
    let opened = try #require(
      handled(
        AdministrationMediator.reduce(
          changed.state, envelope(.openAdministration(profile), source: .root, id: 2),
          mode: .administration, webEnabled: true)))
    #expect(opened.state.draft?.profile.startURL == "https://example.com/unsaved")
    #expect(opened.state.hasUnsavedDraft)
  }

  @Test(arguments: ["", "-", "NaN", "inf", "0", "-1", "1e309"])
  func retainsInvalidIntermediateDraftInput(_ text: String) throws {
    var draft = ProfileDraft(profile: try fixtureProfile())
    draft.idleTimeoutText = text
    let edited = try #require(
      handled(
        AdministrationMediator.reduce(
          .init(),
          envelope(.draftChanged(draft), source: .settings), mode: .administration)))
    #expect(edited.state.draft?.idleTimeoutText == text)
    #expect(edited.state.draft?.validatedProfile == nil)
    let save = try #require(
      handled(
        AdministrationMediator.reduce(
          edited.state,
          envelope(.saveDraftRequested, source: .settings, id: 2), mode: .administration)))
    #expect(save.reply == .rejected(.invalidProfile))
    #expect(save.parentEvents.isEmpty)
  }

  @Test func cancellationInvalidatesLateCredentialSuccess() throws {
    let open = try #require(
      handled(
        AdministrationMediator.reduce(
          .init(),
          envelope(.openUnlock(unlockID: 10)), mode: .unlocking)))
    let edited = try #require(
      handled(
        AdministrationMediator.reduce(
          open.state,
          envelope(.passcodeEdited("fixture"), source: .unlock), mode: .unlocking)))
    let pending = try #require(
      handled(
        AdministrationMediator.reduce(
          edited.state,
          envelope(.passcodeSubmitted, source: .unlock, id: 2), mode: .unlocking)))
    let token = try requireToken(pending.state.verification)
    let cancelled = try #require(
      handled(
        AdministrationMediator.reduce(
          pending.state,
          envelope(.cancelAuthentication, source: .unlock, id: 3), mode: .unlocking)))
    #expect(cancelled.effects.map(\.kind) == [.cancelOperation(token)])
    #expect(cancelled.parentEvents == [.unlockCancelled])
    let late = try #require(
      handled(
        AdministrationMediator.reduce(
          cancelled.state,
          envelope(.credentialVerified(token, succeeded: true), source: .credentials, id: 4),
          mode: .unlocking)))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.parentEvents.isEmpty)
  }

  @Test func repeatedFailuresRequireCooldownWithoutAuthenticating() throws {
    var state = try #require(
      handled(
        AdministrationMediator.reduce(
          .init(),
          envelope(.openUnlock(unlockID: 10)), mode: .unlocking))
    ).state
    for index in 1...3 {
      state.passcode = "fixture"
      state = try #require(
        handled(
          AdministrationMediator.reduce(
            state,
            envelope(.passcodeSubmitted, source: .unlock, id: UInt64(index * 2)),
            mode: .unlocking))
      ).state
      let failure = try #require(
        handled(
          AdministrationMediator.reduce(
            state,
            envelope(
              .credentialVerified(try requireToken(state.verification), succeeded: false),
              source: .credentials, id: UInt64(index * 2 + 1)), mode: .unlocking)))
      #expect(failure.parentEvents.isEmpty)
      state = failure.state
    }
    state.passcode = "fixture"
    let blocked = try #require(
      handled(
        AdministrationMediator.reduce(
          state,
          envelope(.passcodeSubmitted, source: .unlock, id: 8, now: 29), mode: .unlocking
        )))
    #expect(blocked.reply == .rejected(.cooldown))
    #expect(blocked.effects.isEmpty)
    let retry = try #require(
      handled(
        AdministrationMediator.reduce(
          state,
          envelope(.passcodeSubmitted, source: .unlock, id: 9, now: 30), mode: .unlocking
        )))
    #expect(retry.reply == .accepted)
    #expect(retry.state.failedAttempts == 0)
  }
}
