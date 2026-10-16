extension RootMediator {
  static func reduceBiometric(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    switch envelope.event {
    case .biometricStatusRequested, .biometricStatusRead:
      return reduceBiometricStatus(state, envelope)
    case .biometricUnlockRequested, .biometricUnlockCancelled, .biometricUnlockCompleted:
      return reduceBiometricUnlock(state, envelope)
    case .biometricChangeRequested, .biometricChangeCompleted, .biometricChangeCancelled:
      return reduceBiometricChange(state, envelope)
    default: return .bubble
    }
  }

  private static func reduceBiometricStatus(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .credentials, epoch: state.epoch)
    switch envelope.event {
    case .biometricStatusRequested:
      guard envelope.source == .settings || envelope.source == .platform,
        [.administration, .unlocking].contains(state.mode), state.biometricOperation == nil
      else {
        return .reject(state, .invalidState)
      }
      next.biometricStatusOperation = token
      return .handled(.init(next, reply: .accepted, effects: [Effect(token, .readBiometricStatus)]))

    case .biometricStatusRead(let completed, let status):
      guard envelope.source == .credentials else { return .reject(state, .wrongSource) }
      guard state.biometricStatusOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.biometricStatusOperation = nil
      next.biometricStatus = status
      return .handled(.init(next))

    default: return .bubble
    }
  }

  private static func reduceBiometricUnlock(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .credentials, epoch: state.epoch)
    switch envelope.event {
    case .biometricUnlockRequested:
      guard envelope.source == .unlock else { return .reject(state, .wrongSource) }
      guard state.mode == .unlocking, state.unlockID != nil,
        state.biometricUnlockOperation == nil, state.biometricStatusOperation == nil,
        state.biometricStatus?.enabled == true,
        state.credentialsConfigured
      else { return .reject(state, .invalidState) }
      guard case .available = state.biometricStatus?.availability else {
        return .reject(state, .invalidState)
      }
      next.biometricUnlockOperation = token
      next.biometricUnlockFailed = false
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [Effect(token, .performBiometricUnlock)]))

    case .biometricUnlockCancelled:
      guard envelope.source == .unlock else { return .reject(state, .wrongSource) }
      guard state.mode == .unlocking, let operation = state.biometricUnlockOperation else {
        return .reject(state, .invalidState)
      }
      next.biometricUnlockOperation = nil
      next.biometricUnlockFailed = false
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [Effect(token, .cancelOperation(operation))]))

    case .biometricUnlockCompleted(let completed, let status, let outcome):
      return completeBiometricUnlock(
        state, envelope, completed: completed, status: status, outcome: outcome)

    default: return .bubble
    }
  }

  private static func completeBiometricUnlock(
    _ state: RootState, _ envelope: EventEnvelope, completed: OperationToken,
    status: BiometricStatus, outcome: BiometricUnlockOutcome
  ) -> Mediation<RootState> {
    guard envelope.source == .credentials else { return .reject(state, .wrongSource) }
    guard state.mode == .unlocking, state.biometricUnlockOperation == completed,
      state.unlockID != nil
    else { return .reject(state, .staleOperation) }
    var next = state
    next.biometricUnlockOperation = nil
    next.biometricStatus = status
    switch outcome {
    case .succeeded:
      guard status.enabled else { return .reject(state, .staleOperation) }
      let token = envelope.token(owner: .credentials, epoch: state.epoch)
      return completeAuthentication(next, token: token)
    case .cancelled:
      next.biometricUnlockFailed = false
    case .failed:
      next.biometricUnlockFailed = true
    case .enrollmentChanged:
      next.biometricEnrollmentChanged = true
      next.biometricUnlockFailed = true
    }
    return .handled(.init(next))
  }

  private static func reduceBiometricChange(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    switch envelope.event {
    case .biometricChangeRequested(let enabled):
      return requestBiometricChange(state, envelope, enabled: enabled)

    case .biometricChangeCompleted(let completed, let status, let outcome):
      guard envelope.source == .credentials else { return .reject(state, .wrongSource) }
      guard state.biometricOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.biometricOperation = nil
      next.biometricStatusOperation = nil
      next.biometricStatus = status
      next.biometricChangeFailed = outcome == .failed
      if status.enabled { next.biometricEnrollmentChanged = false }
      return .handled(.init(next))

    case .biometricChangeCancelled:
      return cancelBiometricChange(state, envelope)

    default: return .bubble
    }
  }

  private static func requestBiometricChange(
    _ state: RootState, _ envelope: EventEnvelope, enabled: Bool
  ) -> Mediation<RootState> {
    guard envelope.source == .settings, state.mode == .administration else {
      return .reject(state, .invalidState)
    }
    guard state.credentialsConfigured else { return .reject(state, .unauthenticated) }
    guard state.biometricOperation == nil, let status = state.biometricStatus,
      status.enabled != enabled
    else { return .reject(state, .invalidState) }
    if enabled, case .unavailable = status.availability {
      return .reject(state, .invalidState)
    }
    var next = state
    let token = envelope.token(owner: .credentials, epoch: state.epoch)
    next.biometricOperation = token
    next.biometricStatusOperation = nil
    next.biometricChangeFailed = false
    return .handled(
      .init(next, reply: .accepted, effects: [Effect(token, .changeBiometricUnlock(enabled))]))
  }

  private static func cancelBiometricChange(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    guard envelope.source == .settings, state.mode == .administration else {
      return .reject(state, .invalidState)
    }
    guard let operation = state.biometricOperation else {
      return .reject(state, .invalidState)
    }
    var next = state
    let token = envelope.token(owner: .credentials, epoch: state.epoch)
    next.biometricOperation = nil
    next.biometricChangeFailed = false
    next.biometricStatusOperation = token
    return .handled(
      .init(
        next, reply: .accepted,
        effects: [Effect(token, .cancelOperation(operation)), Effect(token, .readBiometricStatus)]))
  }
}
