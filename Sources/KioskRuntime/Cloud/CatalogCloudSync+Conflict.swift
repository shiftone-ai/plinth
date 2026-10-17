import Foundation
import KioskCore

extension CatalogCloudSync {
  static func fetchedConflicts(
    saves: [CatalogEntry], disk: DiskState, resolvedConflicts: Set<UUID>
  ) -> [CatalogCloudChange] {
    saves.compactMap { entry in
      guard !disk.conflicts.contains(entry.id) else { return nil }
      return fetchedChangeConflictingWithSave(
        entry, serverEntries: disk.serverEntries, serverDeletions: disk.serverDeletions,
        resolvedConflicts: resolvedConflicts)
    }
  }

  static func fetchedChangeConflictingWithSave(
    _ entry: CatalogEntry, serverEntries: [UUID: CatalogEntry],
    serverDeletions: Set<UUID>, resolvedConflicts: Set<UUID>
  ) -> CatalogCloudChange? {
    if let remote = serverEntries[entry.id] {
      guard !entry.sameCloudContents(as: remote) else { return nil }
      if resolvedConflicts.contains(entry.id) {
        return remote.version >= entry.version ? .upsert(remote) : nil
      }
      return remote.version > (entry.syncedVersion ?? 0) ? .upsert(remote) : nil
    }
    if serverDeletions.contains(entry.id), entry.syncedVersion != nil,
      !resolvedConflicts.contains(entry.id)
    {
      return .delete(entry.id)
    }
    return nil
  }
}
