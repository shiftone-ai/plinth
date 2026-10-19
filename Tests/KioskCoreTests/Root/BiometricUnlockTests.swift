import KioskCore
import Testing

struct BiometricUnlockTests {
  private let enabled = BiometricStatus(availability: .available(.touchID), enabled: true)

  @Test func explicitRequestAndSuccessfulKeychainReadOpenAdministration() throws {
    let state = unlockingState()
    let request = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(request.state.biometricUnlockOperation)
    #expect(request.reply == .accepted)
    #expect(request.effects == [.init(operation, .performBiometricUnlock)])

    let result = try #require(
      handled(
        RootMediator.reduce(
          request.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 3))))
    #expect(result.state.mode == .leavingKiosk)
    #expect(result.state.administratorSession)
    #expect(result.state.unlockID == nil)
    #expect(
      result.childControls == [
        .init(.administration, .biometricAuthenticationVerified),
        .init(.exhibition, .stopExhibition),
      ])
    #expect(
      result.effects == [
        .init(
          .init(owner: .root, ownerEpoch: state.epoch, operationID: 3),
          .cancelOperation(try requireToken(state.unlockTimeoutOperation)))
      ])

    var administration = AdministrationState()
    administration.failedAttempts = 2
    administration.cooldownUntil = 30
    administration.unlockID = state.unlockID
    let cleared = try #require(
      handled(
        AdministrationMediator.reduce(
          administration,
          envelope(.biometricAuthenticationVerified, source: .root, id: 4),
          mode: result.state.mode)))
    #expect(cleared.state.failedAttempts == 0)
    #expect(cleared.state.cooldownUntil == nil)
    #expect(cleared.state.unlockID == nil)
  }

  @Test func cancellationRejectsLateSuccess() throws {
    let request = try #require(
      handled(
        RootMediator.reduce(
          unlockingState(), envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(request.state.biometricUnlockOperation)
    let cancelled = try #require(
      handled(
        RootMediator.reduce(
          request.state, envelope(.biometricUnlockCancelled, source: .unlock, id: 3))))
    #expect(cancelled.reply == .accepted)
    #expect(
      cancelled.effects == [
        .init(
          .init(owner: .credentials, ownerEpoch: request.state.epoch, operationID: 3),
          .cancelOperation(operation))
      ])
    let late = try #require(
      handled(
        RootMediator.reduce(
          cancelled.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 4))))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.effects.isEmpty)
    #expect(late.state.mode == .unlocking)
  }

  @Test func deadlineAndSafeHoldCancelAuthenticationAndRejectLateSuccess() throws {
    let request = try #require(
      handled(
        RootMediator.reduce(
          unlockingState(), envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(request.state.biometricUnlockOperation)
    let timeout = try requireToken(request.state.unlockTimeoutOperation)
    let expired = try #require(
      handled(
        RootMediator.reduce(
          request.state,
          envelope(.unlockDeadlineReached(timeout), source: .idleClock, id: 3, now: 60))))
    #expect(expired.state.mode == .exhibiting)
    #expect(
      expired.effects.map(\.kind) == [
        .cancelOperation(timeout), .cancelOperation(operation),
      ])
    let lateAfterTimeout = try #require(
      handled(
        RootMediator.reduce(
          expired.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 4))))
    #expect(lateAfterTimeout.reply == .rejected(.staleOperation))

    let held = try #require(
      handled(
        RootMediator.reduce(
          request.state, envelope(.systemWillSleep, source: .platform, id: 5))))
    #expect(held.state.mode == .safeHold)
    #expect(
      held.effects.map(\.kind) == [
        .cancelOperation(timeout), .cancelOperation(operation),
      ])
    let lateAfterHold = try #require(
      handled(
        RootMediator.reduce(
          held.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 6))))
    #expect(lateAfterHold.reply == .rejected(.staleOperation))
  }

  @Test func passwordSuccessCancelsBiometricsAndLateSuccessCannotReopenAdministration() throws {
    let request = try #require(
      handled(
        RootMediator.reduce(
          unlockingState(), envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(request.state.biometricUnlockOperation)
    let password = try #require(
      handled(
        RootMediator.reduce(
          request.state,
          envelope(.authenticationVerified(unlockID: 1), source: .administration, id: 3))))
    #expect(password.state.mode == .leavingKiosk)
    #expect(
      password.effects.map(\.kind) == [
        .cancelOperation(try requireToken(request.state.unlockTimeoutOperation)),
        .cancelOperation(operation),
      ])
    let late = try #require(
      handled(
        RootMediator.reduce(
          password.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 4))))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.effects.isEmpty)
  }

  @Test func failureKeepsUnlockOpenWithoutChangingPasswordCooldown() throws {
    let request = try #require(
      handled(
        RootMediator.reduce(
          unlockingState(), envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(request.state.biometricUnlockOperation)
    let failure = try #require(
      handled(
        RootMediator.reduce(
          request.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .failed),
            source: .credentials, id: 3))))
    #expect(failure.state.mode == .unlocking)
    #expect(failure.state.biometricUnlockFailed)
    #expect(failure.childControls.isEmpty)
    #expect(failure.effects.isEmpty)

    var administration = AdministrationState()
    administration.failedAttempts = 2
    administration.unlockID = 1
    let next = AdministrationMediator.reduce(
      administration,
      envelope(
        .biometricUnlockCompleted(operation, enabled, .failed),
        source: .credentials, id: 3), mode: .unlocking)
    #expect(next == .bubble)
    #expect(administration.failedAttempts == 2)
    #expect(administration.cooldownUntil == nil)

    let disabled = BiometricStatus(availability: .available(.touchID), enabled: false)
    let changed = try #require(
      handled(
        RootMediator.reduce(
          request.state,
          envelope(
            .biometricUnlockCompleted(operation, disabled, .enrollmentChanged),
            source: .credentials, id: 4))))
    #expect(changed.state.biometricStatus == disabled)
    #expect(changed.state.biometricEnrollmentChanged)
    #expect(changed.state.mode == .unlocking)
    let password = try #require(
      handled(
        RootMediator.reduce(
          changed.state,
          envelope(.authenticationVerified(unlockID: 1), source: .administration, id: 5))))
    let stopped = try #require(
      handled(
        RootMediator.reduce(
          password.state, envelope(.exhibitionStopped, source: .exhibition, id: 6))))
    #expect(stopped.state.mode == .administration)
    #expect(stopped.state.biometricEnrollmentChanged)
  }

  private func unlockingState() -> RootState {
    var state = RootState()
    state.mode = .unlocking
    state.unlockID = 1
    state.unlockReturnMode = .exhibiting
    state.unlockTimeoutOperation = .init(owner: .root, operationID: 1)
    state.unlockDeadline = 60
    state.credentialsConfigured = true
    state.biometricStatus = enabled
    return state
  }
}
