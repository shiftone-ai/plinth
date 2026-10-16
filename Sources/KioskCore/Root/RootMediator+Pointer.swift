extension RootMediator {
  static func reducePointer(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState>? {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .externalMouseAvailabilityChanged(let connected):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      next.externalMouseConnected = connected
      if !connected, state.externalPointerLocked || state.pointerCaptureOperation != nil {
        var effects = releasePointer(&next, token: token)
        if state.externalButtonDown, context.webAvailable {
          let operation = envelope.token(
            owner: .root, epoch: state.epoch, generation: context.webGeneration)
          effects.append(Effect(operation, .controlExternalWeb(.cancelPress)))
        }
        if state.mode == .enteringKiosk, state.pointerCaptureOperation != nil {
          next.mode = .exhibiting
        }
        return .handled(.init(next, effects: effects))
      }
      if state.mode == .exhibiting, needsPointerCapture(next), !state.externalPointerLocked {
        return capturePointer(next, token: token)
      }
      return .handled(.init(next))

    case .externalPointerCaptureCompleted(let completed, let succeeded):
      guard envelope.source == .platform, state.pointerCaptureOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.pointerCaptureOperation = nil
      guard succeeded else {
        next.pointerCaptureFailed = true
        return hold(next, token: token)
      }
      next.externalPointerLocked = true
      next.externalPointer = next.externalPointer ?? .init(x: 0.5, y: 0.5)
      next.mode = .exhibiting
      return .handled(.init(next))

    case .externalPointerCaptureChanged(let locked):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      if state.externalPointerLocked, !locked, needsPointerCapture(state) {
        next.pointerCaptureFailed = true
        return hold(next, token: token)
      }
      return .handled(.init(state))

    case .externalMouseInput(let input, let generation):
      guard envelope.source == .platform, state.externalPointerLocked,
        state.mode == .exhibiting, generation == context.webGeneration
      else { return .reject(state, .invalidState) }
      let point = state.externalPointer ?? .init(x: 0.5, y: 0.5)
      let event: Event
      switch input {
      case .move(let dx, let dy):
        guard dx.isFinite, dy.isFinite else { return .reject(state, .invalidState) }
        event = .externalWebControlRequested(
          .move(.init(x: min(1, max(0, point.x + dx)), y: min(1, max(0, point.y + dy)))),
          generation: generation)
      case .primaryButton(let pressed):
        event = .externalWebControlRequested(
          pressed ? .press(point) : .release(point), generation: generation)
      case .unlock: event = .unlockRequested
      }
      if case .unlockRequested = event { return requestUnlock(state, envelope, token: token) }
      return reduceExternalControl(
        state,
        .init(
          eventID: envelope.eventID, source: envelope.source, timestamp: envelope.timestamp,
          event: event),
        context: context)

    case .nativePointerMoved(let point):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      guard point.x.isFinite, point.y.isFinite else { return .reject(state, .invalidState) }
      guard state.macDisplays != nil, state.presentationAcquired,
        state.activeProfile?.macOutput?.mode != .projectionWindow,
        [.enteringKiosk, .exhibiting, .unlocking].contains(state.mode)
      else { return .handled(.init(state)) }
      guard !point.isValid else { return .handled(.init(state)) }
      let clamped = SurfacePoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
      return .handled(.init(state, effects: [Effect(token, .confineNativePointer(clamped))]))

    case .nativePointerConstraintFailed:
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      return hold(state, token: token)

    case .unlockRequested: return requestUnlock(state, envelope, token: token)
    default: return reduceExternalControl(state, envelope, context: context)
    }
  }

  private static func requestUnlock(
    _ state: RootState, _ envelope: EventEnvelope, token: OperationToken
  ) -> Mediation<RootState> {
    var next = state
    guard envelope.source == .platform else { return .reject(state, .wrongSource) }
    guard
      state.mode == .exhibiting || state.mode == .safeHold
        || (state.mode == .enteringKiosk && state.presentationAcquired)
    else {
      return .reject(state, .invalidState)
    }
    next.unlockReturnMode = state.mode == .enteringKiosk ? .exhibiting : state.mode
    next.foregroundResume = .none
    next.externalPointer = nil
    next.externalButtonDown = false
    next.externalPressGeneration = nil
    next.input = .init()
    next.unlockID = envelope.eventID
    next.unlockTimeoutOperation = token
    next.unlockDeadline = envelope.timestamp + 60
    next.biometricUnlockOperation = nil
    next.biometricUnlockFailed = false
    next.mode = .unlocking
    let statusToken = envelope.token(owner: .credentials, epoch: state.epoch)
    next.biometricStatusOperation = statusToken
    let pointerEffects = releasePointer(&next, token: token)
    return .handled(
      .init(
        next, reply: .accepted,
        effects: pointerEffects + [
          Effect(token, .scheduleUnlockTimeout(deadline: envelope.timestamp + 60)),
          Effect(statusToken, .readBiometricStatus),
        ],
        childControls: [
          .init(.administration, .openUnlock(unlockID: envelope.eventID))
        ]))

  }

  static func needsPointerCapture(_ state: RootState) -> Bool {
    state.externalMouseConnected && state.mobileDisplays?.externalDisplayOnly == true
      && state.activeProfile?.exhibitionDestination == .externalDisplay
  }

  static func capturePointer(_ state: RootState, token: OperationToken) -> Mediation<
    RootState
  > {
    var next = state
    next.pointerCaptureFailed = false
    next.pointerCaptureOperation = token
    next.mode = .enteringKiosk
    return .handled(.init(next, effects: [Effect(token, .captureExternalPointer)]))
  }

  static func releasePointer(_ state: inout RootState, token: OperationToken) -> [Effect] {
    let operation = state.pointerCaptureOperation
    let acquired = state.externalPointerLocked
    state.pointerCaptureOperation = nil
    state.externalPointerLocked = false
    state.externalButtonDown = false
    state.externalPressGeneration = nil
    guard acquired || operation != nil else { return [] }
    return (operation.map { [Effect(token, .cancelOperation($0))] } ?? [])
      + [Effect(token, .releaseExternalPointer)]
  }

}
