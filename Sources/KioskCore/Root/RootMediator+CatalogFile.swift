import Foundation

extension RootMediator {
  static func reduceCatalogFile(_ state: RootState, _ envelope: EventEnvelope)
    -> Mediation<RootState>
  {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .catalogExportOperationRequested(let ids, let passphrase):
      guard envelope.source == .administration, state.mode == .administration,
        state.catalogLoaded, state.catalogSaveOperation == nil,
        state.catalogExportOperation == nil, state.catalogExportData == nil,
        state.catalogImportOperation == nil, state.catalogImportPreview == nil,
        Set(ids).count == ids.count
      else { return .reject(state, .invalidState) }
      let entries: [CatalogEntry]
      if ids.isEmpty {
        entries = state.catalog.entries.filter(state.catalogEntryAvailable)
      } else {
        entries = ids.compactMap { id in
          state.catalog.entries.first { $0.id == id && state.catalogEntryAvailable($0) }
        }
        guard entries.count == ids.count else { return .reject(state, .invalidState) }
      }
      guard !entries.isEmpty else { return .reject(state, .invalidState) }
      next.catalogExportOperation = token
      next.catalogExportData = nil
      next.catalogExportFailed = false
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [Effect(token, .prepareCatalogExport(entries, passphrase: passphrase))]))

    case .catalogExportPrepared(let completed, let data):
      guard envelope.source == .catalogRepository,
        state.catalogExportOperation == completed
      else { return .reject(state, .staleOperation) }
      next.catalogExportOperation = nil
      next.catalogExportData = data
      return .handled(
        .init(
          next,
          childControls: [.init(.administration, .catalogPassphraseCleared)]))

    case .catalogExportFailed(let completed):
      guard envelope.source == .catalogRepository,
        state.catalogExportOperation == completed
      else { return .reject(state, .staleOperation) }
      next.catalogExportOperation = nil
      next.catalogExportFailed = true
      return .handled(
        .init(
          next,
          childControls: [.init(.administration, .catalogPassphraseCleared)]))

    case .catalogExportDismissed:
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.catalogExportOperation = nil
      next.catalogExportData = nil
      let effects =
        state.catalogExportOperation.map {
          [Effect(token, .cancelOperation($0))]
        } ?? []
      return .handled(
        .init(
          next, reply: .accepted, effects: effects,
          childControls: [.init(.administration, .catalogPassphraseCleared)]))

    case .catalogFileExportCompleted(let succeeded):
      guard envelope.source == .settings, state.mode == .administration
      else { return .reject(state, .invalidState) }
      next.catalogExportData = nil
      next.catalogExportFailed = !succeeded
      return .handled(.init(next, reply: .accepted))

    case .catalogImportOperationRequested(let url, let passphrase):
      guard envelope.source == .administration, state.mode == .administration,
        state.catalogLoaded, state.catalogImportOperation == nil,
        state.catalogImportPreview == nil, state.catalogExportOperation == nil,
        state.catalogExportData == nil,
        state.catalogSaveOperation == nil, url.isFileURL
      else { return .reject(state, .invalidState) }
      next.catalogImportOperation = token
      next.catalogImportPreview = nil
      next.catalogImportFailed = false
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [Effect(token, .importCatalogFile(url, passphrase: passphrase))]))

    case .catalogImportPreviewReady(let completed, let entries):
      guard envelope.source == .catalogRepository,
        state.catalogImportOperation == completed,
        !entries.isEmpty && entries.allSatisfy({ $0.scope == .device })
      else { return .reject(state, .staleOperation) }
      next.catalogImportOperation = nil
      next.catalogImportPreview = entries
      return .handled(
        .init(
          next,
          childControls: [.init(.administration, .catalogPassphraseCleared)]))

    case .catalogImportFailed(let completed):
      guard envelope.source == .catalogRepository,
        state.catalogImportOperation == completed
      else { return .reject(state, .staleOperation) }
      next.catalogImportOperation = nil
      next.catalogImportFailed = true
      return .handled(
        .init(
          next,
          childControls: [.init(.administration, .catalogPassphraseCleared)]))

    case .catalogImportConfirmed(let replacementIDs):
      guard envelope.source == .settings, state.mode == .administration,
        state.catalogLoaded, state.catalogSaveOperation == nil,
        let preview = state.catalogImportPreview,
        replacementIDs.count == preview.count,
        Set(replacementIDs).count == replacementIDs.count
      else { return .reject(state, .invalidState) }
      var document = state.catalog
      var used = Set(document.entries.map(\.id))
      for (item, replacementID) in zip(preview, replacementIDs) {
        if let existing = document.entries.first(where: {
          $0.id == item.id && state.catalogEntryAvailable($0)
        }) ?? document.entries.first(where: { $0.id == item.id }) {
          if state.catalogEntryAvailable(existing), existing.name == item.name,
            existing.snapshot == item.snapshot
          {
            continue
          }
          guard !used.contains(replacementID),
            let replacement = CatalogEntry(
              id: replacementID, name: item.name, snapshot: item.snapshot,
              version: item.version)
          else { return .reject(state, .invalidProfile) }
          document.entries.append(replacement)
          used.insert(replacementID)
        } else {
          guard !used.contains(item.id) else { return .reject(state, .invalidProfile) }
          document.entries.append(item)
          used.insert(item.id)
        }
      }
      if document.entries == state.catalog.entries {
        next.catalogImportPreview = nil
        return .handled(.init(next, reply: .accepted))
      }
      var result = commitCatalog(state, document, token: token)
      if case .handled(var transition) = result {
        transition.state.pendingCatalogImport = true
        result = .handled(transition)
      }
      return result

    case .catalogImportCancelled:
      guard envelope.source == .settings, state.mode == .administration,
        !state.pendingCatalogImport
      else { return .reject(state, .invalidState) }
      next.catalogImportOperation = nil
      next.catalogImportPreview = nil
      next.catalogImportFailed = false
      let effects =
        state.catalogImportOperation.map {
          [Effect(token, .cancelOperation($0))]
        } ?? []
      return .handled(
        .init(
          next, reply: .accepted, effects: effects,
          childControls: [.init(.administration, .catalogPassphraseCleared)]))

    default: return .bubble
    }
  }
}
