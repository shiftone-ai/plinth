extension RootMediator {
  static func bootstrapCompleted(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    guard case .bootstrapped(let profile, let credentials, let displayCount) = envelope.event
    else { return .bubble }
    guard state.mode == .bootstrapping else { return .reject(state, .invalidState) }
    guard envelope.source == .root || envelope.source == .profileRepository else {
      return .reject(state, .wrongSource)
    }
    var next = state
    next.savedProfile = profile
    next.bootstrapOperation = nil
    next.bootstrapReadFailed = false
    next.credentialsConfigured = credentials
    next.displayCount = displayCount
    let biometricToken = envelope.token(owner: .credentials, epoch: state.epoch)
    next.biometricStatusOperation = biometricToken
    let statusEffect = Effect(biometricToken, .readBiometricStatus)
    if let profile {
      let waitsForMobileDisplay =
        profile.exhibitionDestination == .externalDisplay
        && next.mobileDisplays?.supportsExternalDisplay == true
      guard credentials, profile.validationIssues.isEmpty,
        next.canPresent(profile) || waitsForMobileDisplay
      else {
        next.mode = .safeHold
        return .handled(
          .init(
            next, effects: [statusEffect],
            childControls: [
              .init(.administration, .initializeWebDraft(profile))
            ]))
      }
      if case .handled(var transition) = enter(
        next, profile: profile, token: envelope.token(owner: .root, epoch: state.epoch))
      {
        transition.effects.append(statusEffect)
        transition.childControls.append(.init(.administration, .initializeWebDraft(profile)))
        return .handled(transition)
      }
    }
    if credentials {
      next.mode = .safeHold
      return .handled(.init(next, effects: [statusEffect]))
    }
    next.mode = .administration
    return .handled(
      .init(
        next, effects: [statusEffect],
        childControls: [.init(.administration, .openAdministration(nil))]))
  }
}
