extension RootMediator {
  static func reduceExternalControl(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState>? {
    var next = state
    switch envelope.event {
    case .externalWebControlDeliveryFailed(let operation):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard operation.owner == .root, operation.ownerEpoch == state.epoch,
        operation.webGeneration == context.webGeneration,
        state.mode == .exhibiting, context.webAvailable
      else { return .reject(state, .staleOperation) }
      return hold(state, token: envelope.token(owner: .root, epoch: state.epoch))

    case .externalWebControlExecutionRequested(let operation):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard operation.owner == .root, operation.ownerEpoch == state.epoch,
        operation.webGeneration == context.webGeneration
      else { return .reject(state, .staleOperation) }
      guard state.mode == .exhibiting, context.webAvailable,
        state.activeProfile?.exhibitionDestination == .externalDisplay,
        state.mobileDisplays?.externalDisplayOnly == true,
        state.mobileDisplays?.externalAvailable == true
      else { return .reject(state, .invalidState) }
      return .handled(.init(state, reply: .accepted))

    case .externalWebControlRequested(let control, let generation):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      guard generation == context.webGeneration else { return .reject(state, .staleOperation) }
      guard state.mode == .exhibiting, context.webAvailable,
        state.activeProfile?.exhibitionDestination == .externalDisplay,
        state.mobileDisplays?.externalDisplayOnly == true,
        state.mobileDisplays?.externalAvailable == true, control.isValid
      else { return .reject(state, .invalidState) }
      if case .scroll = control, state.activeProfile?.interaction.allowsScroll != true {
        return .reject(state, .invalidState)
      }
      switch control {
      case .move(let point):
        if state.externalButtonDown, state.externalPressGeneration != generation {
          return .reject(state, .staleOperation)
        }
        if state.externalButtonDown, state.activeProfile?.interaction.allowsDrag != true {
          return .reject(state, .invalidState)
        }
        next.externalPointer = point
      case .press(let point):
        guard !state.externalButtonDown else { return .reject(state, .invalidState) }
        next.externalButtonDown = true
        next.externalPressGeneration = generation
        next.externalPointer = point
      case .release(let point):
        guard state.externalButtonDown, state.externalPressGeneration == generation else {
          return .reject(state, .invalidState)
        }
        next.externalButtonDown = false
        next.externalPressGeneration = nil
        next.externalPointer = point
      case .cancelPress:
        guard state.externalButtonDown else { return .handled(.init(state, reply: .accepted)) }
        next.externalButtonDown = false
        next.externalPressGeneration = nil
      case .activate(let point): next.externalPointer = point
      case .scroll: break
      }
      let operation = envelope.token(owner: .root, epoch: state.epoch, generation: generation)
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [Effect(operation, .controlExternalWeb(control))],
          childControls: [.init(.exhibition, .visitorActivity)]))

    default: return nil
    }
  }
}
