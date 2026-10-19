import Foundation
import KioskCore

nonisolated struct CatalogPublication: Sendable {
  let command: OperationToken
  let session: OperationToken
  let resolvedConflicts: [UUID]
  let saves: [CatalogEntry]
  let deletions: [CatalogPendingDeletion]
}

/// Keeps publication deltas while CloudKit starts and ignores late older edits of the same entry.
nonisolated struct CatalogPublicationBuffer {
  private var pending: [CatalogPublication] = []
  private var latestCommandByID: [UUID: UInt64] = [:]

  mutating func append(_ publication: CatalogPublication) { pending.append(publication) }

  var hasPending: Bool { !pending.isEmpty }

  mutating func reset(for session: OperationToken?) {
    pending.removeAll { $0.session != session }
    latestCommandByID = [:]
  }

  mutating func takeNext(for session: OperationToken) -> CatalogPublication? {
    while !pending.isEmpty {
      pending.sort { $0.command.operationID < $1.command.operationID }
      let current = pending.removeFirst()
      guard current.session == session else { continue }
      func isFresh(_ id: UUID) -> Bool {
        current.command.operationID > (latestCommandByID[id] ?? 0)
      }
      let resolved = current.resolvedConflicts.filter(isFresh)
      let saves = current.saves.filter { isFresh($0.id) }
      let deletions = current.deletions.filter { isFresh($0.id) }
      for id in resolved + saves.map(\.id) + deletions.map(\.id) {
        latestCommandByID[id] = current.command.operationID
      }
      if !resolved.isEmpty || !saves.isEmpty || !deletions.isEmpty {
        return CatalogPublication(
          command: current.command, session: current.session,
          resolvedConflicts: resolved, saves: saves, deletions: deletions)
      }
    }
    return nil
  }
}
