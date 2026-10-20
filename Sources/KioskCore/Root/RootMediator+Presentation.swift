extension RootMediator {
  static func reducePresentation(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    switch envelope.event {
    case .presentationApplied, .presentationFailed:
      return reducePresentationApplication(state, envelope)
    case .exhibitionReady, .exhibitionUnavailable:
      return reduceExhibitionStatus(state, envelope)
    case .exhibitionStopped, .presentationReleased:
      return reduceExhibitionExit(state, envelope)
    default: return .bubble
    }
  }

  private static func reducePresentationApplication(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    switch envelope.event {
    case .presentationApplied(let completed):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      if state.presentationAcquisition == completed && state.mode != .enteringKiosk {
        next.presentationAcquisition = nil
        next.presentationAcquired = true
        return .handled(.init(next))
      }
      guard state.mode == .enteringKiosk, state.presentationOperation == completed,
        let profile = state.activeProfile
      else { return .reject(state, .staleOperation) }
      next.presentationAcquired = true
      next.presentationOperation = nil
      next.presentationAcquisition = nil
      return .handled(
        .init(next, childControls: [.init(.exhibition, .activateExhibition(profile))]))

    case .presentationFailed(let completed):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      guard state.mode == .enteringKiosk, state.presentationOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.presentationOperation = nil
      next.presentationAcquisition = nil
      next.mode = .safeHold
      next.mobileExhibitionResumePending = false
      next.shortcutResetAcceptedDuringResume = false
      if state.webRestartInProgress {
        next.webRestartInProgress = false
        next.webRestartFailed = true
      }
      return .handled(.init(next))

    default: return .bubble
    }
  }

  private static func reduceExhibitionStatus(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .exhibitionReady:
      guard envelope.source == .exhibition else { return .reject(state, .wrongSource) }
      if state.mode == .unlocking { return .handled(.init(state)) }
      guard state.mode == .enteringKiosk || state.mode == .exhibiting else {
        return .reject(state, .invalidState)
      }
      next.mode = .exhibiting
      next.mobileExhibitionResumePending = false
      next.shortcutResetAcceptedDuringResume = false
      next.webRestartInProgress = false
      next.webRestartFailed = false
      next.externalButtonDown = false
      next.externalPressGeneration = nil
      if needsPointerCapture(next), !next.externalPointerLocked {
        guard state.pointerCaptureOperation == nil else { return .handled(.init(state)) }
        return capturePointer(next, token: token)
      }
      return .handled(.init(next))

    case .exhibitionUnavailable:
      guard envelope.source == .exhibition else { return .reject(state, .wrongSource) }
      guard [.enteringKiosk, .exhibiting, .unlocking].contains(state.mode) else {
        return .reject(state, .invalidState)
      }
      return hold(state, token: token)

    default: return .bubble
    }
  }

  private static func reduceExhibitionExit(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    switch envelope.event {
    case .exhibitionStopped: return exhibitionStopped(state, envelope)
    case .presentationReleased(let completed):
      return presentationReleased(state, envelope, completed: completed)
    default: return .bubble
    }
  }

  private static func exhibitionStopped(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    guard envelope.source == .exhibition else { return .reject(state, .wrongSource) }
    if state.mode == .safeHold && state.foregroundResume == .awaitingStop {
      next.foregroundResume = .none
      guard !state.administratorSession,
        let profile = state.activeProfile, state.canPresent(profile)
      else { return .handled(.init(next)) }
      return enter(next, profile: profile, token: token)
    }
    if state.mode == .safeHold { return .handled(.init(state)) }
    guard state.mode == .leavingKiosk || state.mode == .terminating else {
      return .reject(state, .invalidState)
    }
    if state.webExitDestination == .paused { return pause(next) }
    if state.presentationAcquired || state.presentationAcquisition != nil {
      next.presentationOperation = token
      return .handled(.init(next, effects: [Effect(token, .releasePresentation)]))
    }
    if state.mode == .terminating { return .handled(.init(next)) }
    if state.webExitDestination == .restart, let profile = state.savedProfile {
      return enter(next, profile: profile, token: token)
    }
    return administration(next, token: token)

  }

  private static func presentationReleased(
    _ state: RootState, _ envelope: EventEnvelope, completed: OperationToken
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    guard envelope.source == .platform else { return .reject(state, .wrongSource) }
    guard [.leavingKiosk, .terminating].contains(state.mode),
      state.presentationOperation == completed
    else {
      return .reject(state, .staleOperation)
    }
    next.presentationAcquired = false
    next.presentationOperation = nil
    next.presentationAcquisition = nil
    if state.mode == .terminating { return .handled(.init(next)) }
    if state.webExitDestination == .restart, let profile = state.savedProfile {
      return enter(next, profile: profile, token: token)
    }
    if state.webExitDestination == .paused { return pause(next) }
    return administration(next, token: token)

  }

}
