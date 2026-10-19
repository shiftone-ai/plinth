import Foundation

extension RootMediator {
  static func reduceCatalogRegistration(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    guard case .catalogRegistrationRequested(let id, let name, let profile) = envelope.event
    else { return .bubble }
    guard envelope.source == .administration else { return .reject(state, .wrongSource) }
    guard state.mode == .administration, state.catalogLoaded,
      state.catalogSaveOperation == nil, state.saveOperation == nil,
      state.savedProfile == profile
    else { return .reject(state, .invalidState) }
    guard !state.catalog.entries.contains(where: { $0.id == id }),
      let snapshot = CatalogSnapshot(profile),
      let entry = CatalogEntry(id: id, name: name, snapshot: snapshot),
      let revision = ProfileRevision.next(after: state.catalog.revision)
    else { return .reject(state, .invalidProfile) }
    var document = state.catalog
    document.revision = revision
    document.entries.append(entry)
    let token = envelope.token(owner: .root, epoch: state.epoch)
    var next = state
    next.pendingCatalog = document
    next.pendingCatalogRegistrationID = id
    next.catalogSaveOperation = token
    next.catalogSaveFailed = false
    return .handled(
      .init(next, reply: .accepted, effects: [Effect(token, .saveCatalog(document))]))
  }
}
