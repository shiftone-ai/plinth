import Foundation
import KioskCore

nonisolated struct CatalogInitialFetch: Sendable {
  struct Reconciliation {
    var changes: [CatalogCloudChange] = []
    var resumingSaves: [UUID] = []
  }

  private var missing: Set<UUID>
  private var unobservedOpaque: Set<UUID>

  init(
    entries: [UUID: CatalogEntry], pendingDeletions: [CatalogPendingDeletion],
    opaqueRecordIDs: Set<UUID>
  ) {
    let pending = Set(pendingDeletions.map(\.id))
    unobservedOpaque = opaqueRecordIDs
    missing = Set(
      entries.compactMap { id, entry in
        entry.syncedVersion != nil && !pending.contains(id)
          ? id : nil
      })
  }

  mutating func observe(_ id: UUID) {
    missing.remove(id)
    unobservedOpaque.remove(id)
  }

  func reconcile(_ disk: inout CatalogCloudSync.DiskState) -> Reconciliation {
    var result = Reconciliation()
    disk.opaqueRecordIDs.subtract(unobservedOpaque)
    for id in missing.union(unobservedOpaque).sorted(by: { $0.uuidString < $1.uuidString }) {
      if missing.contains(id) { disk.entries.removeValue(forKey: id) }
      disk.serverEntries.removeValue(forKey: id)
      disk.recordSystemFields.removeValue(forKey: id)
      if unobservedOpaque.contains(id), let local = disk.entries[id],
        local.syncedVersion == nil
      {
        disk.serverDeletions.remove(id)
        result.resumingSaves.append(id)
      } else {
        disk.serverDeletions.insert(id)
        result.changes.append(.delete(id))
      }
    }
    return result
  }
}
