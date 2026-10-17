import CloudKit
import Foundation
import KioskCore

private enum CatalogCloudDiskCodingKeys: String, CodingKey {
  case accountIdentifier, engineState, entries, serverEntries, serverDeletions,
    recordSystemFields, conflicts, opaqueRecordIDs
}

extension CatalogCloudSync {
  struct DiskState: Codable {
    var accountIdentifier: String
    var engineState: CKSyncEngine.State.Serialization?
    var entries: [UUID: CatalogEntry]
    var serverEntries: [UUID: CatalogEntry]
    var serverDeletions: Set<UUID>
    var recordSystemFields: [UUID: Data]
    var conflicts: Set<UUID>
    var opaqueRecordIDs: Set<UUID>

    init(
      accountIdentifier: String, engineState: CKSyncEngine.State.Serialization?,
      entries: [UUID: CatalogEntry], serverEntries: [UUID: CatalogEntry],
      serverDeletions: Set<UUID>, recordSystemFields: [UUID: Data],
      conflicts: Set<UUID>, opaqueRecordIDs: Set<UUID> = []
    ) {
      self.accountIdentifier = accountIdentifier
      self.engineState = engineState
      self.entries = entries
      self.serverEntries = serverEntries
      self.serverDeletions = serverDeletions
      self.recordSystemFields = recordSystemFields
      self.conflicts = conflicts
      self.opaqueRecordIDs = opaqueRecordIDs
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CatalogCloudDiskCodingKeys.self)
      accountIdentifier = try values.decode(String.self, forKey: .accountIdentifier)
      engineState = try values.decodeIfPresent(
        CKSyncEngine.State.Serialization.self, forKey: .engineState)
      entries = try values.decode([UUID: CatalogEntry].self, forKey: .entries)
      serverEntries = try values.decode([UUID: CatalogEntry].self, forKey: .serverEntries)
      serverDeletions = try values.decode(Set<UUID>.self, forKey: .serverDeletions)
      recordSystemFields = try values.decode([UUID: Data].self, forKey: .recordSystemFields)
      conflicts = try values.decode(Set<UUID>.self, forKey: .conflicts)
      opaqueRecordIDs =
        try values.decodeIfPresent(Set<UUID>.self, forKey: .opaqueRecordIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
      var values = encoder.container(keyedBy: CatalogCloudDiskCodingKeys.self)
      try values.encode(accountIdentifier, forKey: .accountIdentifier)
      try values.encodeIfPresent(engineState, forKey: .engineState)
      try values.encode(entries, forKey: .entries)
      try values.encode(serverEntries, forKey: .serverEntries)
      try values.encode(serverDeletions, forKey: .serverDeletions)
      try values.encode(recordSystemFields, forKey: .recordSystemFields)
      try values.encode(conflicts, forKey: .conflicts)
      try values.encode(opaqueRecordIDs, forKey: .opaqueRecordIDs)
    }
  }
}
