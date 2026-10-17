import Foundation

extension RootMediator {
  static func reduceCatalogLocal(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .catalogLoadRequested:
      guard state.catalogLoadOperation == nil, !state.catalogLoaded,
        envelope.source == .root
          || (envelope.source == .settings && state.mode == .administration
            && state.catalogLoadFailed)
      else { return .reject(state, .invalidState) }
      next.catalogLoadOperation = token
      next.catalogLoadFailed = false
      return .handled(.init(next, reply: .accepted, effects: [Effect(token, .loadCatalog)]))

    case .catalogLoaded(let completed, let document):
      guard envelope.source == .catalogRepository, state.catalogLoadOperation == completed
      else { return .reject(state, .staleOperation) }
      guard document.isValid else { return .reject(state, .invalidProfile) }
      next.catalog = document
      next.catalogLoaded = true
      next.catalogLoadOperation = nil
      next.catalogCorrupt = false
      next.catalogRecoveryPending = false
      if document.syncEnabled {
        guard state.catalogCloudAvailable else {
          next.catalogSyncStatus = .offline
          return .handled(.init(next))
        }
        next.catalogSyncStatus = .checking
        next.catalogAccountCheckOperation = token
        return .handled(.init(next, effects: [Effect(token, .checkCatalogAccount)]))
      }
      return .handled(.init(next))

    case .catalogLoadFailed(let completed):
      guard envelope.source == .catalogRepository, state.catalogLoadOperation == completed
      else { return .reject(state, .staleOperation) }
      next.catalogLoadOperation = nil
      next.catalogLoadFailed = true
      return .handled(.init(next))

    case .catalogSelectRequested(let id):
      guard envelope.source == .settings, state.mode == .administration,
        state.catalogSaveOperation == nil,
        let entry = state.catalog.entries.first(where: {
          $0.id == id && $0.isVisible && state.catalogEntryAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      guard !context.hasUnsavedDraft else { return .reject(state, .unsavedDraft) }
      return .handled(
        .init(
          state, reply: .accepted,
          childControls: [.init(.administration, .catalogSelectionOpened(entry))]))

    case .catalogApplyRequested:
      guard envelope.source == .settings, state.mode == .administration,
        state.catalogSaveOperation == nil,
        !context.hasUnsavedDraft, let id = context.catalogSelectionID,
        let entry = state.catalog.entries.first(where: {
          $0.id == id && $0.isVisible && state.catalogEntryAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      return .handled(
        .init(
          state, reply: .accepted,
          childControls: [
            .init(
              .administration,
              .catalogSelectionApplied(entry))
          ]))

    case .catalogRenameRequested(let id, let name):
      guard canEditCatalog(state, envelope) else { return .reject(state, .invalidState) }
      guard
        let index = state.catalog.entries.firstIndex(where: {
          $0.id == id && state.catalogEntryAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      guard
        !state.catalog.conflicts.contains(where: {
          $0.id == id && state.catalogConflictAvailable($0)
        })
      else {
        return .reject(state, .invalidState)
      }
      let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard CatalogEntry.validName(name) else { return .reject(state, .invalidProfile) }
      guard name != state.catalog.entries[index].name else {
        return .handled(.init(state, reply: .accepted))
      }
      if state.catalog.entries[index].scope == .iCloud {
        next.catalogRenameCandidate = .init(id: id, name: name)
        return .handled(.init(next, reply: .accepted))
      }
      return renameCatalog(state, index: index, name: name, token: token)

    case .catalogRenameConfirmed(let id):
      guard canEditCatalog(state, envelope),
        let candidate = state.catalogRenameCandidate, candidate.id == id,
        let index = state.catalog.entries.firstIndex(where: {
          $0.id == id && $0.scope == .iCloud && state.catalogEntryAvailable($0)
        }),
        !state.catalog.conflicts.contains(where: {
          $0.id == id && state.catalogConflictAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      var result = renameCatalog(state, index: index, name: candidate.name, token: token)
      if case .handled(var transition) = result {
        transition.state.catalogRenameCandidate = nil
        result = .handled(transition)
      }
      return result

    case .catalogRenameCancelled:
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.catalogRenameCandidate = nil
      return .handled(.init(next, reply: .accepted))

    case .catalogUpdateRequested(let id):
      guard canEditCatalog(state, envelope), !context.hasUnsavedDraft,
        let profile = state.savedProfile, let snapshot = CatalogSnapshot(profile),
        let index = state.catalog.entries.firstIndex(where: {
          $0.id == id && state.catalogEntryAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      guard
        !state.catalog.conflicts.contains(where: {
          $0.id == id && state.catalogConflictAvailable($0)
        })
      else {
        return .reject(state, .invalidState)
      }
      guard snapshot != state.catalog.entries[index].snapshot else {
        return .handled(.init(state, reply: .accepted))
      }
      if state.catalog.entries[index].scope == .iCloud {
        next.catalogUpdateCandidateID = id
        return .handled(.init(next, reply: .accepted))
      }
      return updateCatalog(state, index: index, snapshot: snapshot, token: token)

    case .catalogUpdateConfirmed(let id):
      guard canEditCatalog(state, envelope), !context.hasUnsavedDraft,
        state.catalogUpdateCandidateID == id,
        let profile = state.savedProfile, let snapshot = CatalogSnapshot(profile),
        let index = state.catalog.entries.firstIndex(where: {
          $0.id == id && $0.scope == .iCloud && state.catalogEntryAvailable($0)
        }),
        !state.catalog.conflicts.contains(where: {
          $0.id == id && state.catalogConflictAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      var result = updateCatalog(state, index: index, snapshot: snapshot, token: token)
      if case .handled(var transition) = result {
        transition.state.catalogUpdateCandidateID = nil
        result = .handled(transition)
      }
      return result

    case .catalogUpdateCancelled:
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.catalogUpdateCandidateID = nil
      return .handled(.init(next, reply: .accepted))

    case .catalogVisibilityRequested(let id, let visible):
      guard canEditCatalog(state, envelope),
        let index = state.catalog.entries.firstIndex(where: {
          $0.id == id && state.catalogEntryAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      guard state.catalog.entries[index].isVisible != visible else {
        return .handled(.init(state, reply: .accepted))
      }
      var document = state.catalog
      document.entries[index].isVisible = visible
      return commitCatalog(state, document, token: token)

    case .catalogRemovePromptRequested(let id):
      guard canEditCatalog(state, envelope),
        state.catalog.entries.contains(where: { $0.id == id && state.catalogEntryAvailable($0) }),
        !state.catalog.conflicts.contains(where: {
          $0.id == id && state.catalogConflictAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      next.catalogRemovalCandidateID = id
      return .handled(.init(next, reply: .accepted))

    case .catalogRemovePromptCancelled:
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.catalogRemovalCandidateID = nil
      return .handled(.init(next, reply: .accepted))

    case .catalogRemoveConfirmed(let id):
      guard canEditCatalog(state, envelope),
        state.catalogRemovalCandidateID == id,
        state.catalog.entries.contains(where: { $0.id == id && state.catalogEntryAvailable($0) }),
        !state.catalog.conflicts.contains(where: {
          $0.id == id && state.catalogConflictAvailable($0)
        })
      else { return .reject(state, .invalidState) }
      var document = state.catalog
      if let removed = document.entries.first(where: {
        $0.id == id && state.catalogEntryAvailable($0)
      }),
        removed.scope == .iCloud, let accountID = removed.accountIdentifier
      {
        document.pendingDeletions.append(
          .init(id: id, accountIdentifier: accountID, baseVersion: removed.syncedVersion))
      }
      document.entries.removeAll { $0.id == id && state.catalogEntryAvailable($0) }
      var result = commitCatalog(state, document, token: token)
      if case .handled(var transition) = result {
        transition.state.catalogRemovalCandidateID = nil
        result = .handled(transition)
      }
      return result

    case .catalogSaved(let completed, let document):
      guard envelope.source == .catalogRepository, state.catalogSaveOperation == completed,
        state.pendingCatalog == document
      else { return .reject(state, .staleOperation) }
      next.catalog = document
      next.catalogSaveOperation = nil
      next.pendingCatalog = nil
      next.catalogQueuedReconcileAttempted = false
      if state.pendingCatalogImport { next.catalogImportPreview = nil }
      next.pendingCatalogImport = false
      let registrationID = next.pendingCatalogRegistrationID
      next.pendingCatalogRegistrationID = nil
      var effects: [Effect] = []
      if state.catalog.syncEnabled && !document.syncEnabled {
        next.catalogSyncStatus = .disabled
        next.catalogCloudSessionOperation = nil
        effects.append(Effect(token, .stopCatalogCloudSync))
      }
      if state.catalogCheckAfterSave && document.syncEnabled {
        next.catalogSyncStatus = .checking
        next.catalogAccountCheckOperation = token
        effects.append(Effect(token, .checkCatalogAccount))
      }
      if state.catalogStartAfterSave, document.syncEnabled,
        let accountID = document.accountIdentifier
      {
        next.catalogSyncStatus = .pending
        next.catalogCloudSessionOperation = token
        effects.append(
          Effect(
            token,
            .startCatalogCloudSync(
              accountID, entries: document.entries,
              conflicts: document.conflictIDs(for: accountID),
              pendingDeletions: document.pendingDeletions)))
      }
      next.catalogCheckAfterSave = false
      next.catalogStartAfterSave = false
      if state.pendingCatalogPublishes, document.syncEnabled,
        let accountID = document.accountIdentifier
      {
        let queuedIDs = Set(state.queuedCatalogCloudChanges.map(\.id))
        let resolvedConflicts = Set(
          state.catalog.conflicts.filter {
            state.catalog.conflictBelongsToAccount($0, accountIdentifier: accountID)
          }.map(\.id)
        ).subtracting(
          document.conflicts.filter {
            document.conflictBelongsToAccount($0, accountIdentifier: accountID)
          }.map(\.id)
        )
        .subtracting(queuedIDs)
        let oldShared = Dictionary(
          uniqueKeysWithValues: state.catalog.entries.compactMap { entry in
            entry.scope == .iCloud && entry.accountIdentifier == accountID
              ? (entry.id, entry) : nil
          })
        let newShared = Dictionary(
          uniqueKeysWithValues: document.entries.compactMap { entry in
            entry.scope == .iCloud && entry.accountIdentifier == accountID
              ? (entry.id, entry) : nil
          })
        let saves = newShared.values.filter {
          guard !queuedIDs.contains($0.id) else { return false }
          if resolvedConflicts.contains($0.id) { return true }
          guard let previous = oldShared[$0.id] else { return true }
          return !$0.sameCloudContents(as: previous)
        }
        let oldDeletions = Dictionary(
          uniqueKeysWithValues:
            state.catalog.pendingDeletions.filter { $0.accountIdentifier == accountID }
            .map { ($0.id, $0.attempt) })
        let deletions = document.pendingDeletions.filter {
          $0.accountIdentifier == accountID && oldDeletions[$0.id] != $0.attempt
            && !queuedIDs.contains($0.id)
        }
        if !saves.isEmpty || !deletions.isEmpty || !resolvedConflicts.isEmpty,
          let session = next.catalogCloudSessionOperation
        {
          next.catalogSyncStatus = .pending
          effects.append(
            Effect(
              token,
              .publishCatalogChanges(
                session: session, resolvedConflicts: Array(resolvedConflicts),
                saves: saves, deletions: deletions)))
        }
      }
      next.pendingCatalogPublishes = true
      let controls: [ChildControl] =
        registrationID.map {
          [.init(.administration, .catalogRegistrationSucceeded($0))]
        } ?? []
      let followup = reconcileQueuedCloudFacts(state, into: document)
      if followup != document {
        next.queuedCatalogCloudChanges = []
        next.queuedCatalogAcknowledgements = [:]
        next.queuedCatalogDeletionAcknowledgements = []
        if case .handled(var transition) = commitCatalog(
          next, followup, token: token, publish: false)
        {
          transition.effects.insert(contentsOf: effects, at: 0)
          transition.childControls.append(contentsOf: controls)
          return .handled(transition)
        }
      }
      next.queuedCatalogCloudChanges = []
      next.queuedCatalogAcknowledgements = [:]
      next.queuedCatalogDeletionAcknowledgements = []
      return .handled(.init(next, effects: effects, childControls: controls))

    case .catalogSaveFailed(let completed):
      guard envelope.source == .catalogRepository, state.catalogSaveOperation == completed
      else { return .reject(state, .staleOperation) }
      let recheckAccount = state.catalogCheckAfterSave && state.catalog.syncEnabled
      next.catalogSaveOperation = nil
      next.pendingCatalog = nil
      next.pendingCatalogRegistrationID = nil
      next.pendingCatalogImport = false
      next.catalogSaveFailed = true
      next.catalogCheckAfterSave = false
      next.catalogStartAfterSave = false
      if hasQueuedCloudFacts(state), !state.catalogQueuedReconcileAttempted {
        let followup = reconcileQueuedCloudFacts(state, into: state.catalog)
        if followup != state.catalog,
          case .handled(var transition) = commitCatalog(
            next, followup, token: token, publish: false)
        {
          transition.state.catalogQueuedReconcileAttempted = true
          transition.state.catalogCheckAfterSave = recheckAccount
          transition.state.catalogSaveFailed = true
          return .handled(transition)
        }
      }
      if hasQueuedCloudFacts(state) { next.catalogSyncStatus = .failed }
      if recheckAccount {
        next.catalogSyncStatus = .checking
        next.catalogAccountCheckOperation = token
        return .handled(.init(next, effects: [Effect(token, .checkCatalogAccount)]))
      }
      return .handled(.init(next))

    default: return .bubble
    }
  }

}
