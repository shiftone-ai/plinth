import Foundation

public struct CatalogRenameCandidate: Equatable, Sendable {
  public let id: UUID
  public let name: String
  public init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}

public enum CatalogScope: String, Codable, Sendable {
  case device, iCloud
}

public enum CatalogSyncStatus: Equatable, Sendable {
  case disabled, checking, ready, pending, offline, signInRequired, accountChanged, failed
}

public enum CatalogCloudChange: Equatable, Sendable {
  case upsert(CatalogEntry)
  case delete(UUID)

  public var id: UUID {
    switch self {
    case .upsert(let entry): entry.id
    case .delete(let id): id
    }
  }
}

public struct CatalogConflict: Equatable, Codable, Sendable, Identifiable {
  public let id: UUID
  public let remote: CatalogEntry?
  public let accountIdentifier: String?
  public init(id: UUID, remote: CatalogEntry?, accountIdentifier: String? = nil) {
    self.id = id
    self.remote = remote
    self.accountIdentifier = accountIdentifier ?? remote?.accountIdentifier
  }
}

public struct CatalogPendingDeletion: Equatable, Codable, Sendable, Identifiable {
  public let id: UUID
  public let accountIdentifier: String
  public var attempt: UInt64
  public var baseVersion: UInt64?

  public init(
    id: UUID, accountIdentifier: String, attempt: UInt64 = 1, baseVersion: UInt64? = nil
  ) {
    self.id = id
    self.accountIdentifier = accountIdentifier
    self.attempt = attempt
    self.baseVersion = baseVersion
  }
}

public struct CatalogEntry: Equatable, Codable, Sendable, Identifiable {
  public let id: UUID
  public let formatVersion: Int
  public var name: String
  public var snapshot: CatalogSnapshot
  public var version: UInt64
  public var scope: CatalogScope
  public var isVisible: Bool
  public var accountIdentifier: String?
  public var syncedVersion: UInt64?

  public init?(
    id: UUID, name: String, snapshot: CatalogSnapshot, version: UInt64 = 1,
    scope: CatalogScope = .device, isVisible: Bool = true,
    accountIdentifier: String? = nil, syncedVersion: UInt64? = nil
  ) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard Self.validName(name), version > 0, snapshot.isValid,
      (scope == .device && accountIdentifier == nil)
        || (scope == .iCloud && !(accountIdentifier ?? "").isEmpty)
    else { return nil }
    self.id = id
    formatVersion = 1
    self.name = name
    self.snapshot = snapshot
    self.version = version
    self.scope = scope
    self.isVisible = isVisible
    self.accountIdentifier = accountIdentifier
    self.syncedVersion = syncedVersion
  }

  public func sameCloudContents(as other: CatalogEntry) -> Bool {
    id == other.id && formatVersion == other.formatVersion
      && name == other.name && snapshot == other.snapshot
      && version == other.version && scope == other.scope
      && accountIdentifier == other.accountIdentifier
  }

  public static func validName(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 120
      && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }
}

public struct CatalogCloudPayload: Codable, Sendable {
  public static let maximumBytes = 900_000

  public let name: String
  public let formatVersion: Int
  public let snapshot: CatalogSnapshot
  public let version: UInt64

  public init(_ entry: CatalogEntry) {
    name = entry.name
    formatVersion = entry.formatVersion
    snapshot = entry.snapshot
    version = entry.version
  }

  public static func encoded(_ entry: CatalogEntry) -> Data? {
    guard let data = try? JSONEncoder().encode(Self(entry)), data.count <= maximumBytes
    else { return nil }
    return data
  }
}

public struct SettingsCatalog: Equatable, Codable, Sendable {
  public let schemaVersion: Int
  public var revision: UInt64
  public var syncEnabled: Bool
  public var accountIdentifier: String?
  public var entries: [CatalogEntry]
  public var conflicts: [CatalogConflict]
  public var pendingDeletions: [CatalogPendingDeletion]

  public init(
    revision: UInt64 = 0, syncEnabled: Bool = false, accountIdentifier: String? = nil,
    entries: [CatalogEntry] = [], conflicts: [CatalogConflict] = [],
    pendingDeletions: [CatalogPendingDeletion] = []
  ) {
    schemaVersion = 1
    self.revision = revision
    self.syncEnabled = syncEnabled
    self.accountIdentifier = accountIdentifier
    self.entries = entries
    self.conflicts = conflicts
    self.pendingDeletions = pendingDeletions
  }

  public func conflictBelongsToAccount(
    _ conflict: CatalogConflict, accountIdentifier: String
  ) -> Bool {
    if let owner = conflictOwner(conflict), owner != accountIdentifier {
      return false
    }
    if let remote = conflict.remote,
      remote.scope != .iCloud || remote.accountIdentifier != accountIdentifier
    {
      return false
    }
    if let entry = entries.first(where: {
      $0.id == conflict.id && ($0.scope == .device || $0.accountIdentifier == accountIdentifier)
    }) {
      return (entry.scope == .device && conflict.remote != nil)
        || (entry.scope == .iCloud && entry.accountIdentifier == accountIdentifier)
    }
    return pendingDeletions.contains {
      $0.id == conflict.id && $0.accountIdentifier == accountIdentifier
    }
  }

  public func conflictIDs(for accountIdentifier: String) -> [UUID] {
    conflicts.filter { conflictBelongsToAccount($0, accountIdentifier: accountIdentifier) }
      .map(\.id)
  }

  private func conflictOwner(_ conflict: CatalogConflict) -> String? {
    conflict.accountIdentifier ?? conflict.remote?.accountIdentifier
      ?? entries.first(where: { $0.id == conflict.id && $0.scope == .iCloud })?.accountIdentifier
      ?? pendingDeletions.first(where: { $0.id == conflict.id })?.accountIdentifier
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, revision, syncEnabled, accountIdentifier, entries, conflicts,
      pendingDeletions
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    revision = try values.decode(UInt64.self, forKey: .revision)
    syncEnabled = try values.decode(Bool.self, forKey: .syncEnabled)
    accountIdentifier = try values.decodeIfPresent(String.self, forKey: .accountIdentifier)
    entries = try values.decode([CatalogEntry].self, forKey: .entries)
    conflicts = try values.decodeIfPresent([CatalogConflict].self, forKey: .conflicts) ?? []
    pendingDeletions =
      try values.decodeIfPresent(
        [CatalogPendingDeletion].self, forKey: .pendingDeletions) ?? []
  }

  public var isValid: Bool {
    let entriesByID = Dictionary(grouping: entries, by: \.id)
    let distinctEntries = entriesByID.values.allSatisfy { group in
      group.count == 1
        || (group.allSatisfy { $0.scope == .iCloud }
          && Set(group.compactMap(\.accountIdentifier)).count == group.count)
    }
    let conflictKeys = conflicts.map {
      CatalogAccountKey(id: $0.id, accountIdentifier: conflictOwner($0))
    }
    let deletionKeys = pendingDeletions.map {
      CatalogAccountKey(id: $0.id, accountIdentifier: $0.accountIdentifier)
    }
    let deletionSet = Set(deletionKeys)
    return schemaVersion == 1 && distinctEntries
      && Set(conflictKeys).count == conflicts.count
      && deletionSet.count == pendingDeletions.count
      && entries.allSatisfy { entry in
        !deletionSet.contains(
          CatalogAccountKey(id: entry.id, accountIdentifier: entry.accountIdentifier))
      }
      && entries.allSatisfy {
        $0.formatVersion == 1 && CatalogEntry.validName($0.name)
          && $0.version > 0 && $0.snapshot.isValid
          && (($0.scope == .device && $0.accountIdentifier == nil)
            || ($0.scope == .iCloud && !($0.accountIdentifier ?? "").isEmpty))
      }
      && conflicts.allSatisfy {
        $0.remote == nil
          || ($0.remote?.id == $0.id && $0.remote?.scope == .iCloud
            && ($0.accountIdentifier == nil
              || $0.accountIdentifier == $0.remote?.accountIdentifier))
      }
      && pendingDeletions.allSatisfy { !$0.accountIdentifier.isEmpty && $0.attempt > 0 }
  }
}

private struct CatalogAccountKey: Hashable {
  let id: UUID
  let accountIdentifier: String?
}
