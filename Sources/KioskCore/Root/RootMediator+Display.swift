extension RootMediator {
  static func reduceDisplay(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    switch envelope.event {
    case .prepareExternalSceneRequested, .externalScenePrepared, .externalScenePreparationFailed:
      return reduceExternalScene(state, envelope)
    case .mobileDisplaysChanged:
      return reduceMobileDisplay(state, envelope)
    case .macDisplaysChanged, .displayCountChanged:
      return reduceMacDisplay(state, envelope)
    default: return .bubble
    }
  }

  private static func reduceExternalScene(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .prepareExternalSceneRequested:
      guard envelope.source == .settings, state.mode == .administration,
        state.mobileDisplays?.canPrepareExhibitionWindow == true,
        state.externalSceneOperation == nil
      else { return .reject(state, .invalidState) }
      next.externalSceneOperation = token
      next.externalScenePreparationFailed = false
      return .handled(
        .init(next, reply: .accepted, effects: [Effect(token, .prepareExternalScene)]))

    case .externalScenePrepared(let completed), .externalScenePreparationFailed(let completed):
      guard envelope.source == .platform, state.externalSceneOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.externalSceneOperation = nil
      if case .externalScenePreparationFailed = envelope.event {
        next.externalScenePreparationFailed = true
      }
      return .handled(.init(next))

    default: return .bubble
    }
  }

  private static func reduceMobileDisplay(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .mobileDisplaysChanged(let availability):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      next.mobileDisplays = availability
      if state.activeProfile?.exhibitionDestination == .externalDisplay,
        !availability.externalConnected
      {
        next.foregroundResume = .none
      }
      if state.mode == .safeHold, next.foregroundResume == .awaitingDisplay,
        !state.administratorSession, let profile = state.activeProfile, next.canPresent(profile)
      {
        next.foregroundResume = .awaitingStop
        return .handled(.init(next, childControls: [.init(.exhibition, .stopExhibition)]))
      }
      guard requiresStableDisplay(state) else { return .handled(.init(next)) }
      if state.mode == .enteringKiosk, state.presentationOperation != nil,
        state.activeProfile?.exhibitionDestination == .externalDisplay,
        availability.deviceAvailable, availability.supportsExternalDisplay
      {
        // Preparing the display can replace its Scene. The owned native operation is bounded;
        // it reports failure if no usable Scene arrives. Once acquired, disconnects stop at once.
        return .handled(.init(next))
      }
      if state.activeProfile?.exhibitionDestination == .externalDisplay,
        state.mobileDisplays?.externalDisplayOnly != availability.externalDisplayOnly
      {
        return hold(next, token: token)
      }
      if let profile = state.activeProfile, !next.canPresent(profile) {
        return hold(next, token: token)
      }
      return .handled(.init(next))

    default: return .bubble
    }
  }

  private static func reduceMacDisplay(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .macDisplaysChanged(let displays):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      // Presentation options also post this notification without changing the output geometry.
      guard state.macDisplays != displays else { return .handled(.init(state)) }
      next.macDisplays = displays
      next.foregroundResume = .none
      next.displayCount = displays.count
      if requiresStableDisplay(state) {
        return hold(next, token: token)
      }
      return .handled(.init(next))

    case .displayCountChanged(let count):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      next.displayCount = count
      next.foregroundResume = .none
      if requiresStableDisplay(state) { return hold(next, token: token) }
      return .handled(.init(next))

    default: return .bubble
    }
  }

}
