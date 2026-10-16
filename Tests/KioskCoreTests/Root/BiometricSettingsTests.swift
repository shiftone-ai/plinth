import KioskCore
import Testing

struct BiometricSettingsTests {
  private let available = BiometricStatus(availability: .available(.touchID), enabled: false)

  @Test func enablingNeedsStoredPasswordAndAvailableBiometrics() throws {
    var state = RootState()
    state.mode = .administration
    state.biometricStatus = available
    let missingPassword = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.biometricChangeRequested(true), source: .settings))))
    #expect(missingPassword.reply == .rejected(.unauthenticated))
    state.credentialsConfigured = true
    state.biometricStatus = .init(availability: .unavailable(.notEnrolled), enabled: false)
    let unavailable = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.biometricChangeRequested(true), source: .settings))))
    #expect(unavailable.reply == .rejected(.invalidState))
    #expect(unavailable.effects.isEmpty)
  }

  @Test func enablingBlocksExhibitionAndCancellationRejectsLateSuccess() throws {
    var state = RootState()
    state.mode = .administration
    state.savedProfile = try fixtureProfile()
    state.credentialsConfigured = true
    state.biometricStatus = available
    let begin = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.biometricChangeRequested(true), source: .settings))))
    let operation = try requireToken(begin.state.biometricOperation)
    #expect(begin.effects == [.init(operation, .changeBiometricUnlock(true))])
    let start = try #require(
      handled(
        RootMediator.reduce(
          begin.state, envelope(.startExhibitionRequested, source: .settings, id: 2))))
    #expect(start.reply == .rejected(.unsavedDraft))
    let cancel = try #require(
      handled(
        RootMediator.reduce(
          begin.state, envelope(.biometricChangeCancelled, source: .settings, id: 3))))
    #expect(cancel.state.biometricOperation == nil)
    #expect(cancel.effects.first?.kind == .cancelOperation(operation))
    let late = try #require(
      handled(
        RootMediator.reduce(
          cancel.state,
          envelope(
            .biometricChangeCompleted(
              operation, .init(availability: .available(.touchID), enabled: true), .succeeded),
            source: .credentials, id: 4))))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.state.biometricStatus?.enabled == false)
  }

  @Test func successfulChangeUpdatesStateAndFailureKeepsItOff() throws {
    var state = RootState()
    state.mode = .administration
    state.credentialsConfigured = true
    state.biometricStatus = available
    let begin = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.biometricChangeRequested(true), source: .settings))))
    let operation = try requireToken(begin.state.biometricOperation)
    let failure = try #require(
      handled(
        RootMediator.reduce(
          begin.state,
          envelope(
            .biometricChangeCompleted(operation, available, .failed), source: .credentials,
            id: 2))))
    #expect(failure.state.biometricStatus?.enabled == false)
    #expect(failure.state.biometricChangeFailed)
    let retry = try #require(
      handled(
        RootMediator.reduce(
          failure.state, envelope(.biometricChangeRequested(true), source: .settings, id: 3))))
    let enabled = BiometricStatus(availability: .available(.touchID), enabled: true)
    let success = try #require(
      handled(
        RootMediator.reduce(
          retry.state,
          envelope(
            .biometricChangeCompleted(
              try requireToken(retry.state.biometricOperation), enabled, .succeeded),
            source: .credentials, id: 4))))
    #expect(success.state.biometricStatus == enabled)
    #expect(success.state.biometricChangeFailed == false)
  }

  @Test func userCancellationKeepsSettingOffWithoutAnError() throws {
    var state = RootState()
    state.mode = .administration
    state.credentialsConfigured = true
    state.biometricStatus = available
    let begin = try #require(
      handled(
        RootMediator.reduce(state, envelope(.biometricChangeRequested(true), source: .settings))))
    let operation = try requireToken(begin.state.biometricOperation)
    let cancelled = try #require(
      handled(
        RootMediator.reduce(
          begin.state,
          envelope(
            .biometricChangeCompleted(operation, available, .cancelled),
            source: .credentials, id: 2))))
    #expect(cancelled.state.biometricStatus?.enabled == false)
    #expect(cancelled.state.biometricChangeFailed == false)
  }

  @Test func anEarlierStatusReadCannotReplaceACompletedChange() throws {
    var state = RootState()
    state.mode = .administration
    state.credentialsConfigured = true
    state.biometricStatus = available
    let read = try #require(
      handled(
        RootMediator.reduce(state, envelope(.biometricStatusRequested, source: .settings))))
    let readToken = try requireToken(read.state.biometricStatusOperation)
    let begin = try #require(
      handled(
        RootMediator.reduce(
          read.state, envelope(.biometricChangeRequested(true), source: .settings, id: 2))))
    #expect(begin.state.biometricStatusOperation == nil)
    let activated = try #require(
      handled(
        RootMediator.reduce(
          begin.state, envelope(.applicationActivated, source: .platform, id: 3))))
    #expect(activated.effects.isEmpty)
    let stale = try #require(
      handled(
        RootMediator.reduce(
          begin.state,
          envelope(.biometricStatusRead(readToken, available), source: .credentials, id: 4))))
    #expect(stale.reply == .rejected(.staleOperation))
    let enabled = BiometricStatus(availability: .available(.touchID), enabled: true)
    let completed = try #require(
      handled(
        RootMediator.reduce(
          begin.state,
          envelope(
            .biometricChangeCompleted(
              try requireToken(begin.state.biometricOperation), enabled, .succeeded),
            source: .credentials, id: 5))))
    #expect(completed.state.biometricStatus == enabled)
  }
}
