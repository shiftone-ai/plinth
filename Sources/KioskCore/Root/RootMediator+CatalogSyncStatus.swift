import Foundation

extension RootMediator {
  static func reduceCatalogCloudStatus(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    guard case .catalogCloudStatus(let session, let status) = envelope.event,
      envelope.source == .cloudCatalog, state.catalog.syncEnabled,
      state.catalog.accountIdentifier != nil, state.catalogCloudSessionOperation == session
    else { return .reject(state, .invalidState) }
    if state.catalogSaveOperation == nil && hasQueuedCloudFacts(state) {
      return .handled(.init(state))
    }
    var next = state
    if status == .ready, hasQueuedCloudFacts(state) {
      next.catalogSyncStatus = .pending
      next.catalogCloudReadyAfterSave = true
      return .handled(.init(next))
    }
    next.catalogCloudReadyAfterSave = false
    if status == .ready, let accountID = state.catalog.accountIdentifier,
      !state.catalog.conflictIDs(for: accountID).isEmpty
        || state.pendingCatalog?.conflictIDs(for: accountID).isEmpty == false
    {
      next.catalogSyncStatus = .pending
      return .handled(.init(next))
    }
    next.catalogSyncStatus = status
    return .handled(.init(next))
  }

  static func markCatalogCloudFactQueued(_ state: inout RootState) {
    state.catalogCloudReadyAfterSave = false
    if state.catalogSyncStatus == .ready { state.catalogSyncStatus = .pending }
  }

  static func finishCatalogCloudStatusAfterSave(
    _ state: inout RootState, previous: RootState, effects: [Effect]
  ) {
    defer { state.catalogCloudReadyAfterSave = false }
    guard previous.catalogCloudReadyAfterSave,
      state.catalogSyncStatus == .pending,
      state.catalogCloudSessionOperation == previous.catalogCloudSessionOperation,
      let accountID = state.catalog.accountIdentifier,
      state.catalog.conflictIDs(for: accountID).isEmpty,
      !effects.contains(where: {
        if case .publishCatalogChanges = $0.kind { return true }
        return false
      })
    else { return }
    state.catalogSyncStatus = .ready
  }
}
