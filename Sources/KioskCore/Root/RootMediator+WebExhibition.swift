extension RootMediator {
  static func reduceWebExhibition(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    switch envelope.event {
    case .webRestartExhibitionRequested:
      return restartWebExhibition(state, envelope, context: context)
    case .webStopExhibitionRequested:
      return stopWebExhibition(state, envelope)
    case .webResumeExhibitionRequested:
      return resumeWebExhibition(state, envelope, context: context)
    default: return .bubble
    }
  }

  private static func restartWebExhibition(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    guard [.webAdministration, .cloudRemote].contains(envelope.source) else {
      return .reject(state, .wrongSource)
    }
    guard state.mode == .exhibiting else { return .reject(state, .invalidState) }
    if let reason = webStartRejectionReason(state, context: context) {
      return .reject(state, reason)
    }
    var next = state
    next.mode = .leavingKiosk
    next.webExitDestination = .restart
    next.webRestartInProgress = true
    next.webRestartFailed = false
    next.input = .init()
    let pointerEffects = releasePointer(
      &next, token: envelope.token(owner: .root, epoch: state.epoch))
    return .handled(
      .init(
        next, reply: .accepted,
        effects: pointerEffects,
        childControls: [.init(.exhibition, .stopExhibition)]))
  }

  private static func stopWebExhibition(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    guard [.webAdministration, .cloudRemote].contains(envelope.source) else {
      return .reject(state, .wrongSource)
    }
    guard state.mode == .exhibiting else { return .reject(state, .invalidState) }
    var next = state
    next.mode = .leavingKiosk
    next.webExitDestination = .paused
    next.input = .init()
    let pointerEffects = releasePointer(
      &next, token: envelope.token(owner: .root, epoch: state.epoch))
    return .handled(
      .init(
        next, reply: .accepted,
        effects: pointerEffects,
        childControls: [.init(.exhibition, .stopExhibition)]))
  }

  private static func resumeWebExhibition(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    guard [.webAdministration, .cloudRemote].contains(envelope.source) else {
      return .reject(state, .wrongSource)
    }
    guard [.paused, .safeHold].contains(state.mode) else {
      return .reject(state, .invalidState)
    }
    if let reason = webStartRejectionReason(state, context: context) {
      return .reject(state, reason)
    }
    guard let profile = state.savedProfile else { return .reject(state, .invalidProfile) }
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    next.webRestartFailed = false
    next.webRestartInProgress = true
    next.mode = .leavingKiosk
    next.webExitDestination = .restart
    if state.mode == .paused {
      if state.presentationAcquired || state.presentationAcquisition != nil {
        next.presentationOperation = token
        return .handled(
          .init(
            next, reply: .accepted,
            effects: [Effect(token, .releasePresentation)]))
      }
      return enter(next, profile: profile, token: token, reply: .accepted)
    }
    return .handled(
      .init(
        next, reply: .accepted,
        childControls: [.init(.exhibition, .stopExhibition)]))
  }

  private static func webStartRejectionReason(
    _ state: RootState, context: ReadonlyContext
  ) -> RejectionReason? {
    guard !context.hasUnsavedDraft, state.saveOperation == nil else {
      return .unsavedDraft
    }
    guard let profile = state.savedProfile, profile.validationIssues.isEmpty else {
      return .invalidProfile
    }
    guard state.canPresent(profile) else { return .unsupportedDisplays }
    return nil
  }
}
