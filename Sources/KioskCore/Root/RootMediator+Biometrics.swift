extension RootMediator {
  static func reduceBiometric(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    var next = state
    let token = envelope.token(owner: .credentials, epoch: state.epoch)
    switch envelope.event {
    case .biometricStatusRequested:
      guard envelope.source == .settings || envelope.source == .platform,
        state.mode == .administration, state.biometricOperation == nil
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
