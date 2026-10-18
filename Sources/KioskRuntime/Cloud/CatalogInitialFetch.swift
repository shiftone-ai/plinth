import Foundation
import KioskCore

nonisolated struct CatalogInitialFetch: Sendable {
  private var missing: Set<UUID>
  private let pendingDeletionVersions: [UUID: UInt64]

  init(
    entries: [UUID: CatalogEntry], pendingDeletions: [CatalogPendingDeletion],
    opaqueRecordIDs: Set<UUID>
  ) {
    let pending = Set(pendingDeletions.map(\.id))
    pendingDeletionVersions = Dictionary(
      uniqueKeysWithValues: pendingDeletions.compactMap { deletion in
        deletion.baseVersion.map { (deletion.id, $0) }
      })
    missing = Set(
      entries.compactMap { id, entry in
        entry.syncedVersion != nil && !pending.contains(id) && !opaqueRecordIDs.contains(id)
          ? id : nil
      })
  }

  func pendingDeletionVersion(for id: UUID) -> UInt64? { pendingDeletionVersions[id] }

  mutating func observe(_ id: UUID) { missing.remove(id) }

  func reconcile(_ disk: inout CatalogCloudSync.DiskState) -> [CatalogCloudChange] {
    missing.sorted { $0.uuidString < $1.uuidString }.map { id in
      disk.entries.removeValue(forKey: id)
      disk.serverEntries.removeValue(forKey: id)
      disk.serverDeletions.insert(id)
      disk.recordSystemFields.removeValue(forKey: id)
      return .delete(id)
    }
  }
}
