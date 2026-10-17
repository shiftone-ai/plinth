import Foundation

extension RootMediator {
  static func reduceCatalogCloud(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .catalogSyncEnableRequested:
      guard canEditCatalog(state, envelope), !state.catalog.syncEnabled else {
        return .reject(state, .invalidState)
      }
      next.catalogSyncConsentPending = true
      return .handled(.init(next, reply: .accepted))

    case .catalogSyncEnableCancelled:
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.catalogSyncConsentPending = false
      return .handled(.init(next, reply: .accepted))

    case .catalogSyncEnableConfirmed:
      guard canEditCatalog(state, envelope), state.catalogSyncConsentPending else {
        return .reject(state, .invalidState)
      }
      var document = state.catalog
      document.syncEnabled = true
      var result = commitCatalog(state, document, token: token, publish: false)
      if case .handled(var transition) = result {
        transition.state.catalogSyncConsentPending = false
        transition.state.catalogCheckAfterSave = true
        result = .handled(transition)
      }
      return result

    case .catalogSyncDisableRequested:
      guard canEditCatalog(state, envelope), state.catalog.syncEnabled else {
        return .reject(state, .invalidState)
      }
      var document = state.catalog
      document.syncEnabled = false
      return commitCatalog(state, document, token: token, publish: false)

    case .catalogSyncRetryRequested:
      guard canEditCatalog(state, envelope), state.catalog.syncEnabled,
        state.catalogSyncStatus == .signInRequired,
        state.catalogAccountCheckOperation == nil, state.catalogCloudSessionOperation == nil
      else { return .reject(state, .invalidState) }
      next.catalogSyncStatus = .checking
      next.catalogAccountCheckOperation = token
      return .handled(
        .init(next, reply: .accepted, effects: [Effect(token, .checkCatalogAccount)]))

    case .catalogAccountChecked(let completed, let accountID):
      guard envelope.source == .cloudCatalog,
        state.catalogAccountCheckOperation == completed
      else { return .reject(state, .staleOperation) }
      next.catalogAccountCheckOperation = nil
      if state.catalogSaveOperation != nil {
        next.catalogCheckAfterSave = true
        return .handled(.init(next))
      }
      guard state.catalog.syncEnabled else { return .handled(.init(next)) }
      guard let accountID, !accountID.isEmpty else {
        next.catalogSyncStatus = .signInRequired
        return .handled(.init(next))
      }
      if let previous = state.catalog.accountIdentifier, previous != accountID {
        next.catalogSyncStatus = .accountChanged
        var document = state.catalog
        document.syncEnabled = false
        document.accountIdentifier = accountID
        return commitCatalog(next, document, token: token, publish: false)
      }
      if state.catalog.accountIdentifier == nil {
        var document = state.catalog
        document.accountIdentifier = accountID
        var result = commitCatalog(next, document, token: token, publish: false)
        if case .handled(var transition) = result {
          transition.state.catalogStartAfterSave = true
          result = .handled(transition)
        }
        return result
      }
      next.catalogSyncStatus = .pending
      next.catalogCloudSessionOperation = token
      return .handled(
        .init(
          next,
          effects: [
            Effect(
              token,
              .startCatalogCloudSync(
                accountID, entries: state.catalog.entries,
                conflicts: state.catalog.conflicts.map(\.id),
                pendingDeletions: state.catalog.pendingDeletions))
          ]))

    case .catalogCloudAccountChanged(let session):
      guard envelope.source == .cloudCatalog, state.catalog.syncEnabled,
        state.catalogCloudSessionOperation == session
      else {
        return .reject(state, .invalidState)
      }
      next.catalogSyncStatus = .checking
      next.catalogCloudSessionOperation = nil
      next.catalogAccountCheckOperation = token
      return .handled(
        .init(
          next,
          effects: [Effect(token, .checkCatalogAccountAfterStopping)]))

    case .catalogCloudStatus(let session, let status):
      guard envelope.source == .cloudCatalog, state.catalog.syncEnabled,
        state.catalog.accountIdentifier != nil, state.catalogCloudSessionOperation == session
      else { return .reject(state, .invalidState) }
      next.catalogSyncStatus = status
      return .handled(.init(next))

    case .catalogCloudChanges(let session, let accountID, let changes):
      guard envelope.source == .cloudCatalog, state.catalog.syncEnabled,
        state.catalog.accountIdentifier == accountID,
        state.catalogCloudSessionOperation == session, !changes.isEmpty
      else { return .reject(state, .invalidState) }
      if state.catalogSaveOperation != nil {
        next.queuedCatalogCloudChanges.append(contentsOf: changes)
        return .handled(.init(next))
      }
      guard let document = receiveCloudChanges(changes, into: state.catalog, accountID: accountID)
      else { return .handled(.init(state)) }
      return commitCatalog(state, document, token: token, publish: false)

    case .catalogCloudAcknowledged(let session, let accountID, let versions):
      guard envelope.source == .cloudCatalog, state.catalog.syncEnabled,
        state.catalog.accountIdentifier == accountID,
        state.catalogCloudSessionOperation == session
      else { return .reject(state, .invalidState) }
      if state.catalogSaveOperation != nil {
        next.queuedCatalogAcknowledgements.merge(versions) { _, newer in newer }
        return .handled(.init(next))
      }
      var document = state.catalog
      var changed = false
      for index in document.entries.indices {
        let entry = document.entries[index]
        if let version = versions[entry.id], entry.version == version,
          entry.syncedVersion != version
        {
          document.entries[index].syncedVersion = version
          changed = true
        }
      }
      guard changed else { return .handled(.init(state)) }
      next.catalogSyncStatus = .ready
      return commitCatalog(next, document, token: token, publish: false)

    case .catalogCloudDeletionsAcknowledged(let session, let accountID, let ids):
      guard envelope.source == .cloudCatalog, state.catalog.syncEnabled,
        state.catalog.accountIdentifier == accountID,
        state.catalogCloudSessionOperation == session
      else { return .reject(state, .invalidState) }
      if state.catalogSaveOperation != nil {
        next.queuedCatalogDeletionAcknowledgements.formUnion(ids)
        return .handled(.init(next))
      }
      var document = state.catalog
      document.pendingDeletions.removeAll {
        $0.accountIdentifier == accountID && ids.contains($0.id)
      }
      guard document != state.catalog else { return .handled(.init(state)) }
      return commitCatalog(state, document, token: token, publish: false)

    case .catalogSharePromptRequested(let id):
      guard canEditCatalog(state, envelope), state.catalog.syncEnabled,
        state.catalog.accountIdentifier != nil,
        state.catalog.entries.contains(where: { $0.id == id && $0.scope == .device })
      else { return .reject(state, .invalidState) }
      next.catalogShareCandidateID = id
      return .handled(.init(next, reply: .accepted))

    case .catalogSharePromptCancelled:
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.catalogShareCandidateID = nil
      return .handled(.init(next, reply: .accepted))

    case .catalogShareConfirmed(let id):
      guard canEditCatalog(state, envelope), state.catalog.syncEnabled,
        state.catalogShareCandidateID == id, let accountID = state.catalog.accountIdentifier,
        let index = state.catalog.entries.firstIndex(where: { $0.id == id && $0.scope == .device })
      else { return .reject(state, .invalidState) }
      var document = state.catalog
      document.entries[index].scope = .iCloud
      document.entries[index].accountIdentifier = accountID
      var result = commitCatalog(state, document, token: token)
      if case .handled(var transition) = result {
        transition.state.catalogShareCandidateID = nil
        result = .handled(transition)
      }
      return result

    case .catalogConflictResolved(let id, let useRemote):
      guard canEditCatalog(state, envelope),
        let conflict = state.catalog.conflicts.first(where: { $0.id == id }),
        state.catalogConflictAvailable(conflict),
        let accountID = state.catalog.accountIdentifier
      else { return .reject(state, .invalidState) }
      var document = state.catalog
      document.conflicts.removeAll { $0.id == id }
      if useRemote {
        let wasVisible = document.entries.first(where: { $0.id == id })?.isVisible ?? false
        document.entries.removeAll { $0.id == id }
        document.pendingDeletions.removeAll { $0.id == id }
        if var remote = conflict.remote {
          remote.isVisible = wasVisible
          document.entries.append(remote)
        }
      } else if let index = document.entries.firstIndex(where: { $0.id == id }) {
        guard
          let nextVersion = ProfileRevision.next(
            after: max(
              document.entries[index].version, conflict.remote?.version ?? 0))
        else { return .reject(state, .invalidProfile) }
        document.entries[index].version = nextVersion
        document.entries[index].accountIdentifier = accountID
      } else if let index = document.pendingDeletions.firstIndex(where: { $0.id == id }) {
        guard
          let nextAttempt = ProfileRevision.next(after: document.pendingDeletions[index].attempt)
        else { return .reject(state, .invalidProfile) }
        document.pendingDeletions[index].attempt = nextAttempt
        document.pendingDeletions[index].baseVersion = conflict.remote?.version
      }
      return commitCatalog(state, document, token: token)

    default: return .bubble
    }
  }
}
