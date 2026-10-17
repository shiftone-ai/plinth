import CloudKit
import Foundation
import KioskCore

/// Owns CKSyncEngine state and server change tags for one Apple Account at a time.
public actor CatalogCloudSync: CKSyncEngineDelegate {
  private enum Failure: Error { case invalidPayload }
  public static let containerIdentifier = "iCloud.ai.shiftone.plinth"
  private static let zoneName = "SettingsCatalog"
  private static let recordType = "CatalogEntry"
  private static let payloadKey = "payload"

  struct DiskState: Codable {
    var accountIdentifier: String
    var engineState: CKSyncEngine.State.Serialization?
    var entries: [UUID: CatalogEntry]
    var serverEntries: [UUID: CatalogEntry]
    var serverDeletions: Set<UUID>
    var recordSystemFields: [UUID: Data]
    var conflicts: Set<UUID>
  }

  private let containerIdentifier: String
  private var container: CKContainer { CKContainer(identifier: containerIdentifier) }
  private let stateURL: URL
  private let sendEvent: @MainActor @Sendable (Event) -> Void
  private var engine: CKSyncEngine?
  private var disk: DiskState?
  private var active = false
  private var fetchFailed = false
  private var generation: UInt64 = 0
  private var session: OperationToken?
  private var lastCommandID: UInt64 = 0

  public init(
    stateURL: URL, containerIdentifier: String = CatalogCloudSync.containerIdentifier,
    sendEvent: @escaping @MainActor @Sendable (Event) -> Void
  ) {
    self.stateURL = stateURL
    self.containerIdentifier = containerIdentifier
    self.sendEvent = sendEvent
  }

  public func accountIdentifier() async -> String? {
    guard (try? await container.accountStatus()) == .available else { return nil }
    return try? await container.userRecordID().recordName
  }

  public func start(
    accountIdentifier: String, entries: [CatalogEntry], conflicts: [UUID],
    pendingDeletions: [CatalogPendingDeletion], session: OperationToken
  ) async {
    guard session.operationID > lastCommandID else { return }
    lastCommandID = session.operationID
    generation &+= 1
    let startedGeneration = generation
    self.session = session
    active = false
    let previous = engine
    engine = nil
    await previous?.cancelOperations()
    let currentAccount = await self.accountIdentifier()
    guard generation == startedGeneration, self.session == session, !Task.isCancelled else {
      return
    }
    guard currentAccount == accountIdentifier else {
      await sendEvent(.catalogCloudAccountChanged(session))
      return
    }
    do {
      let loaded = try Self.loadDisk(at: stateURL)
      disk =
        loaded?.accountIdentifier == accountIdentifier
        ? loaded
        : DiskState(
          accountIdentifier: accountIdentifier, engineState: nil, entries: [:],
          serverEntries: [:], serverDeletions: [], recordSystemFields: [:], conflicts: [])
      guard var disk else { return }
      disk.conflicts = Set(conflicts)
      let local = Dictionary(
        uniqueKeysWithValues: entries.compactMap { entry in
          entry.scope == .iCloud && entry.accountIdentifier == accountIdentifier
            ? (entry.id, entry) : nil
        })
      let prior = disk.entries
      let replay =
        disk.serverEntries.values.compactMap { remote -> CatalogCloudChange? in
          if let localEntry = local[remote.id], localEntry.syncedVersion == remote.version {
            return nil
          }
          if let deletion = pendingDeletions.first(where: { $0.id == remote.id }),
            deletion.baseVersion == remote.version
          {
            return nil
          }
          return .upsert(remote)
        }
        + disk.serverDeletions.compactMap { id -> CatalogCloudChange? in
          local[id] != nil || pendingDeletions.contains(where: { $0.id == id }) ? .delete(id) : nil
        }
      let replayIDs = Set(
        replay.map { change in
          switch change {
          case .upsert(let entry): entry.id
          case .delete(let id): id
          }
        })
      disk.entries = local
      self.disk = disk
      try persistDisk()
      var configuration = CKSyncEngine.Configuration(
        database: container.privateCloudDatabase,
        stateSerialization: disk.engineState, delegate: self)
      configuration.automaticallySync = true
      let created = CKSyncEngine(configuration)
      engine = created
      active = true
      fetchFailed = false
      if disk.engineState == nil {
        created.state.add(pendingDatabaseChanges: [
          .saveZone(CKRecordZone(zoneName: Self.zoneName))
        ])
      }
      let saves = local.values.filter { entry in
        guard !disk.conflicts.contains(entry.id), !replayIDs.contains(entry.id)
        else { return false }
        guard let previous = prior[entry.id] else { return entry.syncedVersion == nil }
        return !entry.sameCloudContents(as: previous)
          || entry.syncedVersion != entry.version
      }.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID($0.id)) }
      let deletions = pendingDeletions.filter {
        $0.accountIdentifier == accountIdentifier && !disk.conflicts.contains($0.id)
          && !replayIDs.contains($0.id)
      }.map(\.id)
        .map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(Self.recordID($0)) }
      created.state.add(pendingRecordZoneChanges: saves + deletions)
      await sendEvent(.catalogCloudStatus(session, .pending))
      if !replay.isEmpty {
        await sendEvent(.catalogCloudChanges(session, accountIdentifier, replay))
      }
    } catch {
      await sendEvent(.catalogCloudStatus(session, .failed))
    }
  }

  public func stop(command: OperationToken? = nil) async {
    if let command {
      guard command.operationID >= lastCommandID else { return }
      lastCommandID = command.operationID
    } else {
      lastCommandID = .max
    }
    generation &+= 1
    active = false
    session = nil
    let previous = engine
    engine = nil
    await previous?.cancelOperations()
  }

  public func queue(
    session requestedSession: OperationToken, resolvedConflicts: [UUID],
    saves: [CatalogEntry], deletions: [UUID]
  ) async {
    guard active, let engine, let session,
      session == requestedSession
    else { return }
    let queuedGeneration = generation
    let currentAccount = await accountIdentifier()
    guard generation == queuedGeneration, active, self.engine === engine,
      self.session == session, !Task.isCancelled
    else { return }
    guard var disk = self.disk else { return }
    guard currentAccount == disk.accountIdentifier else {
      await sendEvent(.catalogCloudAccountChanged(session))
      return
    }
    do {
      disk.conflicts.subtract(resolvedConflicts)
      let fetchedConflicts = Self.fetchedConflicts(
        saves: saves, disk: disk, resolvedConflicts: Set(resolvedConflicts))
      disk.conflicts.formUnion(fetchedConflicts.map(\.id))
      let permittedSaves = saves.filter { !disk.conflicts.contains($0.id) }
      let permittedDeletions = deletions.filter { !disk.conflicts.contains($0) }
      for entry in permittedSaves {
        guard entry.scope == .iCloud, entry.accountIdentifier == disk.accountIdentifier,
          CatalogCloudPayload.encoded(entry) != nil
        else { throw Failure.invalidPayload }
        disk.entries[entry.id] = entry
      }
      for id in permittedDeletions {
        disk.entries.removeValue(forKey: id)
      }
      self.disk = disk
      try persistDisk()
      engine.state.add(
        pendingRecordZoneChanges:
          permittedSaves.map { .saveRecord(Self.recordID($0.id)) }
          + permittedDeletions.map { .deleteRecord(Self.recordID($0)) })
      let pending =
        !engine.state.pendingRecordZoneChanges.isEmpty
        || !engine.state.pendingDatabaseChanges.isEmpty || !disk.conflicts.isEmpty
      if !fetchedConflicts.isEmpty {
        await sendEvent(.catalogCloudChanges(session, disk.accountIdentifier, fetchedConflicts))
      }
      await sendEvent(.catalogCloudStatus(session, pending ? .pending : .ready))
    } catch {
      await sendEvent(.catalogCloudStatus(session, .failed))
    }
  }

}

extension CatalogCloudSync {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard active, engine === syncEngine, var disk, let session else { return }
    switch event {
    case .stateUpdate(let update):
      disk.engineState = update.stateSerialization
      self.disk = disk
      do { try persistDisk() } catch { await sendEvent(.catalogCloudStatus(session, .failed)) }

    case .accountChange(let change):
      if case .signIn(let currentUser) = change.changeType,
        currentUser.recordName == disk.accountIdentifier
      {
        return
      }
      generation &+= 1
      active = false
      engine = nil
      self.session = nil
      await sendEvent(.catalogCloudAccountChanged(session))

    case .fetchedRecordZoneChanges(let update):
      await handleFetchedRecordZoneChanges(update, syncEngine: syncEngine, session: session)

    case .fetchedDatabaseChanges(let update):
      if update.deletions.contains(where: { $0.zoneID == Self.catalogZoneID }) {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { change in
          switch change {
          case .saveRecord(let id), .deleteRecord(let id):
            return id.zoneID == Self.catalogZoneID
          @unknown default: return false
          }
        }
        let completedDeletions = pending.compactMap { change -> UUID? in
          if case .deleteRecord(let id) = change { return Self.catalogID(from: id) }
          return nil
        }
        disk.serverEntries = [:]
        disk.serverDeletions = []
        disk.recordSystemFields = [:]
        self.disk = disk
        syncEngine.state.remove(pendingRecordZoneChanges: pending)
        syncEngine.state.add(pendingDatabaseChanges: [
          .saveZone(CKRecordZone(zoneID: Self.catalogZoneID))
        ])
        syncEngine.state.add(
          pendingRecordZoneChanges: disk.entries.values.filter {
            !disk.conflicts.contains($0.id)
          }.map { .saveRecord(Self.recordID($0.id)) })
        do { try persistDisk() } catch {
          await sendEvent(.catalogCloudStatus(session, .failed))
          return
        }
        await sendEvent(.catalogCloudStatus(session, .pending))
        if !completedDeletions.isEmpty {
          await sendEvent(
            .catalogCloudDeletionsAcknowledged(
              session, disk.accountIdentifier, completedDeletions))
        }
      }

    case .sentRecordZoneChanges(let update):
      await handleSentRecordZoneChanges(update, syncEngine: syncEngine, session: session)

    case .sentDatabaseChanges(let update):
      if update.failedZoneSaves.contains(where: { $0.zone.zoneID == Self.catalogZoneID })
        || update.failedZoneDeletes[Self.catalogZoneID] != nil
      {
        await sendEvent(.catalogCloudStatus(session, .failed))
      }

    case .willFetchChanges:
      fetchFailed = false

    case .didFetchRecordZoneChanges(let update):
      if update.zoneID == Self.catalogZoneID, let error = update.error {
        fetchFailed = true
        await sendEvent(.catalogCloudStatus(session, Self.isOffline(error) ? .offline : .failed))
      }

    case .didFetchChanges, .didSendChanges:
      if !fetchFailed && syncEngine.state.pendingRecordZoneChanges.isEmpty
        && syncEngine.state.pendingDatabaseChanges.isEmpty && disk.conflicts.isEmpty
      {
        await sendEvent(.catalogCloudStatus(session, .ready))
      }

    default: break
    }
  }

  private func handleFetchedRecordZoneChanges(
    _ update: CKSyncEngine.Event.FetchedRecordZoneChanges, syncEngine: CKSyncEngine,
    session: OperationToken
  ) async {
    guard var disk else { return }
    var changes: [CatalogCloudChange] = []
    for modification in update.modifications {
      let record = modification.record
      guard record.recordType == Self.recordType,
        let id = Self.catalogID(from: record.recordID),
        let payload = Self.entry(from: record, accountIdentifier: disk.accountIdentifier)
      else { continue }
      if syncEngine.state.pendingRecordZoneChanges.contains(.saveRecord(record.recordID)) {
        if disk.entries[id]?.sameCloudContents(as: payload) == true {
          syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
          disk.conflicts.remove(id)
        } else {
          disk.conflicts.insert(id)
          syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        }
      }
      if syncEngine.state.pendingRecordZoneChanges.contains(.deleteRecord(record.recordID)) {
        if let knownTag = disk.recordSystemFields[id].flatMap({
          Self.record(from: $0, matching: record.recordID)
        })?.recordChangeTag,
          knownTag == record.recordChangeTag
        {
          continue
        }
        disk.conflicts.insert(id)
        syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(record.recordID)])
      }
      disk.recordSystemFields[id] = Self.systemFields(record)
      disk.entries[id] = payload
      disk.serverEntries[id] = payload
      disk.serverDeletions.remove(id)
      changes.append(.upsert(payload))
    }
    for deletion in update.deletions {
      guard let id = Self.catalogID(from: deletion.recordID) else { continue }
      if syncEngine.state.pendingRecordZoneChanges.contains(.saveRecord(deletion.recordID)) {
        disk.conflicts.insert(id)
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(deletion.recordID)])
      }
      if syncEngine.state.pendingRecordZoneChanges.contains(.deleteRecord(deletion.recordID)) {
        syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(deletion.recordID)])
      }
      disk.entries.removeValue(forKey: id)
      disk.serverEntries.removeValue(forKey: id)
      disk.serverDeletions.insert(id)
      disk.recordSystemFields.removeValue(forKey: id)
      changes.append(.delete(id))
    }
    self.disk = disk
    do { try persistDisk() } catch {
      await sendEvent(.catalogCloudStatus(session, .failed))
      return
    }
    if !changes.isEmpty {
      await sendEvent(.catalogCloudChanges(session, disk.accountIdentifier, changes))
    }

  }

  private func handleSentRecordZoneChanges(
    _ update: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine,
    session: OperationToken
  ) async {
    guard var disk else { return }
    var acknowledged: [UUID: UInt64] = [:]
    var acknowledgedDeletions: [UUID] = []
    var conflicts: [CatalogCloudChange] = []
    var failureStatus: CatalogSyncStatus?
    for record in update.savedRecords {
      guard let id = Self.catalogID(from: record.recordID),
        let entry = Self.entry(from: record, accountIdentifier: disk.accountIdentifier)
      else { continue }
      disk.recordSystemFields[id] = Self.systemFields(record)
      disk.serverEntries[id] = entry
      disk.serverDeletions.remove(id)
      acknowledged[id] = entry.version
    }
    for id in update.deletedRecordIDs.compactMap(Self.catalogID(from:)) {
      disk.recordSystemFields.removeValue(forKey: id)
      disk.serverEntries.removeValue(forKey: id)
      disk.serverDeletions.insert(id)
      acknowledgedDeletions.append(id)
    }
    for failure in update.failedRecordSaves {
      guard let id = Self.catalogID(from: failure.record.recordID) else { continue }
      switch failure.error.code {
      case .serverRecordChanged:
        if let server = failure.error.serverRecord,
          Self.catalogID(from: server.recordID) == id
        {
          disk.recordSystemFields[id] = Self.systemFields(server)
          if let remote = Self.entry(from: server, accountIdentifier: disk.accountIdentifier) {
            disk.serverEntries[id] = remote
            disk.serverDeletions.remove(id)
            conflicts.append(.upsert(remote))
          }
        } else {
          failureStatus = .failed
        }
        disk.conflicts.insert(id)
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(Self.recordID(id))])
      case .unknownItem:
        disk.conflicts.insert(id)
        disk.serverEntries.removeValue(forKey: id)
        disk.serverDeletions.insert(id)
        conflicts.append(.delete(id))
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(Self.recordID(id))])
      case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
        .notAuthenticated, .operationCancelled:
        failureStatus = .offline
      default:
        failureStatus = .failed
      }
    }
    if !update.failedRecordDeletes.isEmpty {
      for (recordID, error) in update.failedRecordDeletes {
        guard let id = Self.catalogID(from: recordID) else { continue }
        if error.code == .serverRecordChanged, let server = error.serverRecord,
          let remote = Self.entry(from: server, accountIdentifier: disk.accountIdentifier)
        {
          disk.recordSystemFields[id] = Self.systemFields(server)
          disk.serverEntries[id] = remote
          disk.serverDeletions.remove(id)
          disk.conflicts.insert(id)
          syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(recordID)])
          conflicts.append(.upsert(remote))
        } else if error.code == .unknownItem {
          disk.recordSystemFields.removeValue(forKey: id)
          disk.serverEntries.removeValue(forKey: id)
          disk.serverDeletions.insert(id)
          syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(recordID)])
          acknowledgedDeletions.append(id)
        } else {
          failureStatus = .failed
        }
      }
    }
    self.disk = disk
    do { try persistDisk() } catch {
      await sendEvent(.catalogCloudStatus(session, .failed))
      return
    }
    if let failureStatus {
      await sendEvent(.catalogCloudStatus(session, failureStatus))
    }
    if !acknowledged.isEmpty {
      await sendEvent(.catalogCloudAcknowledged(session, disk.accountIdentifier, acknowledged))
    }
    if !acknowledgedDeletions.isEmpty {
      await sendEvent(
        .catalogCloudDeletionsAcknowledged(
          session, disk.accountIdentifier, acknowledgedDeletions))
    }
    if !conflicts.isEmpty {
      await sendEvent(.catalogCloudChanges(session, disk.accountIdentifier, conflicts))
    }

  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    guard active, engine === syncEngine, let session else { return nil }
    let batchGeneration = generation
    let currentAccount = await accountIdentifier()
    guard active, engine === syncEngine, generation == batchGeneration,
      self.session == session, !Task.isCancelled
    else { return nil }
    guard let disk = self.disk else { return nil }
    guard currentAccount == disk.accountIdentifier else {
      await sendEvent(.catalogCloudAccountChanged(session))
      return nil
    }
    let pending = syncEngine.state.pendingRecordZoneChanges.filter {
      context.options.scope.contains($0)
    }
    let entries = disk.entries
    let fields = disk.recordSystemFields
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
      guard let id = Self.catalogID(from: recordID), let entry = entries[id],
        let data = CatalogCloudPayload.encoded(entry)
      else { return nil }
      let record =
        fields[id].flatMap { Self.record(from: $0, matching: recordID) }
        ?? CKRecord(recordType: Self.recordType, recordID: recordID)
      record.encryptedValues[Self.payloadKey] = data
      return record
    }
  }

  static func loadDisk(at stateURL: URL) throws -> DiskState? {
    guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
    let data = try Data(contentsOf: stateURL)
    do {
      return try JSONDecoder().decode(DiskState.self, from: data)
    } catch is DecodingError {
      let quarantine = URL(fileURLWithPath: stateURL.path + ".invalid-" + UUID().uuidString)
      try FileManager.default.moveItem(at: stateURL, to: quarantine)
      return nil
    }
  }

  private func persistDisk() throws {
    guard let disk else { return }
    let directory = stateURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(disk).write(to: stateURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
  }

  private static func recordID(_ id: UUID) -> CKRecord.ID {
    CKRecord.ID(recordName: id.uuidString, zoneID: CKRecordZone.ID(zoneName: zoneName))
  }

  private static var catalogZoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName) }

  private static func catalogID(from recordID: CKRecord.ID) -> UUID? {
    guard recordID.zoneID == catalogZoneID else { return nil }
    return UUID(uuidString: recordID.recordName)
  }

  private static func isOffline(_ error: CKError) -> Bool {
    error.code == .networkUnavailable || error.code == .networkFailure
      || error.code == .serviceUnavailable || error.code == .zoneBusy
  }

  private static func entry(from record: CKRecord, accountIdentifier: String) -> CatalogEntry? {
    guard record.recordType == recordType,
      let id = catalogID(from: record.recordID),
      let data = record.encryptedValues[payloadKey] as? Data,
      data.count <= CatalogCloudPayload.maximumBytes,
      let payload = try? JSONDecoder().decode(CatalogCloudPayload.self, from: data)
    else { return nil }
    guard payload.formatVersion == 1 else { return nil }
    return CatalogEntry(
      id: id, name: payload.name, snapshot: payload.snapshot, version: payload.version,
      scope: .iCloud, isVisible: false, accountIdentifier: accountIdentifier,
      syncedVersion: payload.version)
  }

  private static func systemFields(_ record: CKRecord) -> Data {
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: coder)
    return coder.encodedData
  }

  private static func record(from data: Data) -> CKRecord? {
    guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
    coder.requiresSecureCoding = true
    return CKRecord(coder: coder)
  }

  private static func record(from data: Data, matching id: CKRecord.ID) -> CKRecord? {
    guard let record = record(from: data), record.recordID == id,
      record.recordType == recordType
    else { return nil }
    return record
  }
}
