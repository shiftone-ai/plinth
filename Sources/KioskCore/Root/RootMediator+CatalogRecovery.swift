import Foundation

extension RootMediator {
  static func reduceCatalogRecovery(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .catalogRecoveryRequested:
      guard envelope.source == .settings, state.mode == .administration,
        state.catalogLoadFailed, state.catalogCorrupt, state.catalogLoadOperation == nil
      else { return .reject(state, .invalidState) }
      next.catalogRecoveryPending = true
      return .handled(.init(next, reply: .accepted))

    case .catalogRecoveryCancelled:
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.catalogRecoveryPending = false
      return .handled(.init(next, reply: .accepted))

    case .catalogRecoveryConfirmed:
      guard envelope.source == .settings, state.mode == .administration,
        state.catalogRecoveryPending, state.catalogCorrupt, state.catalogLoadFailed,
        state.catalogLoadOperation == nil
      else { return .reject(state, .invalidState) }
      next.catalogRecoveryPending = false
      next.catalogLoadFailed = false
      next.catalogLoadOperation = token
      return .handled(.init(next, reply: .accepted, effects: [Effect(token, .recoverCatalog)]))

    case .catalogLoadCorrupt(let completed):
      guard envelope.source == .catalogRepository, state.catalogLoadOperation == completed
      else { return .reject(state, .staleOperation) }
      next.catalogLoadOperation = nil
      next.catalogLoadFailed = true
      next.catalogCorrupt = true
      return .handled(.init(next))

    default: return .bubble
    }
  }
}
