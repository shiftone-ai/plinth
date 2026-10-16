import KioskCore
import Testing

struct WebAdministrationAuthenticationTests {
  @Test func webFailuresShareTheLocalUnlockCooldown() throws {
    var state = AdministrationState()
    for attempt in 1...3 {
      let candidate = String(repeating: String(attempt), count: 64)
      let request = try #require(
        handled(
          AdministrationMediator.reduce(
            state,
            envelope(
              .webLoginRequested(password: "wrong", candidate: candidate),
              source: .webAdministration, id: UInt64(attempt * 2)),
            mode: .exhibiting, webEnabled: true)))
      #expect(request.reply == .accepted)
      let token = try requireToken(request.state.webVerification)
      let rejected = try #require(
        handled(
          AdministrationMediator.reduce(
            request.state,
            envelope(
              .credentialVerified(token, succeeded: false),
              source: .credentials, id: UInt64(attempt * 2 + 1)),
            mode: .exhibiting, webEnabled: true)))
      #expect(rejected.parentEvents.isEmpty)
      state = rejected.state
    }
    #expect(state.failedAttempts == 3)
    #expect(state.cooldownUntil == 30)
    let opened = try #require(
      handled(
        AdministrationMediator.reduce(
          state, envelope(.openUnlock(unlockID: 9)), mode: .unlocking, webEnabled: true)))
    var unlock = opened.state
    unlock.passcode = "correct"
    let local = try #require(
      handled(
        AdministrationMediator.reduce(
          unlock, envelope(.passcodeSubmitted, source: .unlock, now: 29),
          mode: .unlocking, webEnabled: true)))
    #expect(local.reply == .rejected(.cooldown))
    let remote = try #require(
      handled(
        AdministrationMediator.reduce(
          state,
          envelope(
            .webLoginRequested(password: "correct", candidate: String(repeating: "a", count: 64)),
            source: .webAdministration, now: 29),
          mode: .exhibiting, webEnabled: true)))
    #expect(remote.reply == .rejected(.cooldown))
  }

  @Test func sessionExpiresAndNewLoginReplacesTheOldToken() throws {
    var profile = try fixtureProfile()
    profile.webAdministrationEnabled = true
    var root = RootState()
    root.savedProfile = profile
    root.credentialsConfigured = true
    root.mode = .exhibiting
    let first = String(repeating: "a", count: 64)
    let second = String(repeating: "b", count: 64)
    root = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.webAuthenticationVerified(first), source: .administration, now: 1)))
    ).state
    #expect(root.webSession?.token == first)
    let used = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(
            .webSessionRequested(first, activity: true), source: .webAdministration,
            now: 899))))
    #expect(used.reply == .accepted)
    root = used.state
    let replaced = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.webAuthenticationVerified(second), source: .administration, now: 900))))
    root = replaced.state
    #expect(
      handled(
        RootMediator.reduce(
          root,
          envelope(
            .webSessionRequested(first, activity: false), source: .webAdministration,
            now: 901)))?.reply
        == .rejected(.unauthenticated))
    #expect(
      handled(
        RootMediator.reduce(
          root,
          envelope(
            .webSessionRequested(second, activity: false), source: .webAdministration,
            now: 1800)))?.reply
        == .rejected(.unauthenticated))
    #expect(
      WebAdministrationSession(token: second, createdAt: 0)
        .isValid(at: 8 * 60 * 60) == false)
  }

  @Test func statePollingDoesNotExtendTheIdleDeadline() throws {
    var profile = try fixtureProfile()
    profile.webAdministrationEnabled = true
    var root = RootState()
    root.savedProfile = profile
    root.credentialsConfigured = true
    root.mode = .exhibiting
    let token = String(repeating: "c", count: 64)
    root = try #require(
      handled(
        RootMediator.reduce(
          root, envelope(.webAuthenticationVerified(token), source: .administration, now: 1)
        ))
    ).state
    for time in stride(from: 100.0, through: 899.0, by: 100.0) {
      let poll = try #require(
        handled(
          RootMediator.reduce(
            root,
            envelope(
              .webSessionRequested(token, activity: false),
              source: .webAdministration, now: time)
          )))
      #expect(poll.reply == .accepted)
      root = poll.state
    }
    #expect(root.webSession?.lastActivityAt == 1)
    #expect(
      handled(
        RootMediator.reduce(
          root,
          envelope(
            .webSessionRequested(token, activity: false),
            source: .webAdministration, now: 901)
        ))?.reply == .rejected(.unauthenticated))
  }
}
