import KioskCore
import Testing

@MainActor
struct BiometricUnlockTests {
  private let enabled = BiometricStatus(availability: .available(.touchID), enabled: true)

  @Test func explicitRequestNeedsEnabledBiometricsAndUnlockMode() throws {
    var state = RootState()
    state.mode = .unlocking
    state.unlockID = 1
    state.credentialsConfigured = true
    state.biometricStatus = enabled
    let requested = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(requested.state.biometricUnlockOperation)
    #expect(requested.reply == .accepted)
    #expect(requested.effects == [Effect(operation, .performBiometricUnlock)])

    state.biometricStatus = .init(availability: .available(.touchID), enabled: false)
    #expect(
      handled(
        RootMediator.reduce(
          state,
          envelope(.biometricUnlockRequested, source: .unlock, id: 3)))?.reply
        == .rejected(.invalidState))
    state.biometricStatus = enabled
    state.mode = .paused
    #expect(
      handled(
        RootMediator.reduce(
          state,
          envelope(.biometricUnlockRequested, source: .unlock, id: 4)))?.reply
        == .rejected(.invalidState))
  }

  @Test func successOpensAdministrationOnlyAfterTheOriginalUnlockAndStopsExhibition() throws {
    let fixture = try state()
    let requested = try #require(
      handled(
        RootMediator.reduce(
          fixture,
          envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(requested.state.biometricUnlockOperation)
    let timeout = try requireToken(fixture.unlockTimeoutOperation)
    let completed = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 3))))
    #expect(completed.state.mode == .leavingKiosk)
    #expect(completed.state.administratorSession)
    #expect(completed.state.unlockID == nil)
    #expect(completed.childControls == [.init(.exhibition, .stopExhibition)])
    #expect(
      completed.effects.contains {
        $0.kind == .cancelOperation(timeout)
      })
  }

  @Test func cancellationRejectsLateSuccess() throws {
    let fixture = try state()
    let requested = try #require(
      handled(
        RootMediator.reduce(
          fixture,
          envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(requested.state.biometricUnlockOperation)
    let cancelled = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(.biometricUnlockCancelled, source: .unlock, id: 3))))
    #expect(
      cancelled.effects == [
        Effect(
          .init(owner: .credentials, ownerEpoch: fixture.epoch, operationID: 3),
          .cancelOperation(operation))
      ])
    #expect(
      handled(
        RootMediator.reduce(
          cancelled.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 4)))?.reply == .rejected(.staleOperation))
  }

  @Test func timeoutRejectsLateSuccess() throws {
    let fixture = try state()
    let requested = try #require(
      handled(
        RootMediator.reduce(
          fixture,
          envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(requested.state.biometricUnlockOperation)
    let timeout = try requireToken(fixture.unlockTimeoutOperation)
    let timeoutResult = RootMediator.reduce(
      requested.state,
      envelope(.unlockDeadlineReached(timeout), source: .idleClock, id: 5, now: 60))
    let timedOut = try #require(handled(timeoutResult))
    #expect(timedOut.state.mode == .paused)
    #expect(timedOut.effects.contains { $0.kind == .cancelOperation(operation) })
    #expect(
      handled(
        RootMediator.reduce(
          timedOut.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 6)))?.reply == .rejected(.staleOperation))
  }

  @Test func safeHoldRejectsLateSuccess() throws {
    let fixture = try state()
    let requested = try #require(
      handled(
        RootMediator.reduce(
          fixture,
          envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(requested.state.biometricUnlockOperation)
    let held = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(.systemWillSleep, source: .platform, id: 7))))
    #expect(held.state.mode == .safeHold)
    #expect(held.effects.contains { $0.kind == .cancelOperation(operation) })
    #expect(
      handled(
        RootMediator.reduce(
          held.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .succeeded),
            source: .credentials, id: 8)))?.reply == .rejected(.staleOperation))
  }

  @Test func failureLeavesPasswordAvailableAndEnrollmentChangeDisablesBiometrics() throws {
    let fixture = try state()
    let requested = try #require(
      handled(
        RootMediator.reduce(
          fixture,
          envelope(.biometricUnlockRequested, source: .unlock, id: 2))))
    let operation = try requireToken(requested.state.biometricUnlockOperation)
    let failed = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(
            .biometricUnlockCompleted(operation, enabled, .failed),
            source: .credentials, id: 3))))
    #expect(failed.state.mode == .unlocking)
    #expect(failed.state.biometricUnlockFailed)
    #expect(failed.state.administratorSession == false)

    let disabled = BiometricStatus(availability: .available(.touchID), enabled: false)
    let changed = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(
            .biometricUnlockCompleted(operation, disabled, .enrollmentChanged),
            source: .credentials, id: 4))))
    #expect(changed.state.biometricStatus == disabled)
    #expect(changed.state.biometricEnrollmentChanged)
    #expect(changed.state.mode == .unlocking)
  }

  private func state() throws -> RootState {
    var state = RootState()
    state.mode = .unlocking
    state.unlockID = 1
    state.unlockReturnMode = .paused
    state.unlockTimeoutOperation = .init(owner: .root, operationID: 1)
    state.unlockDeadline = 60
    state.credentialsConfigured = true
    state.biometricStatus = enabled
    return state
  }
}
