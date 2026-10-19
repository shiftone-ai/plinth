import CloudKit
import Foundation
import KioskCore

/// Owns CKSyncEngine state and server change tags for one Apple Account at a time.
public actor CatalogCloudSync: CKSyncEngineDelegate {
  private enum Failure: Error { case invalidPayload }
  struct SendFailures {
    private(set) var hasNonretryable = false
    private var hasTransient = false

    mutating func record(_ status: CatalogSyncStatus) {
      if status == .failed { hasNonretryable = true }
      if status == .offline { hasTransient = true }
    }

    var status: CatalogSyncStatus? {
      if hasNonretryable { return .failed }
      return hasTransient ? .offline : nil
    }
  }
  public enum AccountAvailability: Equatable, Sendable {
    case available(String)
    case unavailable, transient
  }
  enum FetchedCatalogRecord: Equatable {
    case valid(UUID, CatalogEntry)
    case opaque(UUID)
    case unrelated
  }
  public static let containerIdentifier = "iCloud.ai.shiftone.plinth"
  private static let zoneName = "SettingsCatalog"
  private static let recordType = "CatalogEntry"
  private static let payloadKey = "payload"

  private let containerIdentifier: String
  private var container: CKContainer { CKContainer(identifier: containerIdentifier) }
  private let stateURL: URL
  private let sendEvent: @MainActor @Sendable (Event) -> Void
  private var engine: CKSyncEngine?
  private var disk: DiskState?
  private var active = false
  private var fetchFailed = false
  private var sendFailed = false
  private var persistenceFailed = false
  private var generation: UInt64 = 0
  private var session: OperationToken?
  private var lastCommandID: UInt64 = 0
  private var publications = CatalogPublicationBuffer()
  private var processingPublications = false
  private var retryPublicationsAfterProcessing = false
  private var initializingGeneration: UInt64?
  private var initialFetch: CatalogInitialFetch?
  private var pendingDeletionByID: [UUID: CatalogPendingDeletion] = [:]
  private var deferredEngineState: CKSyncEngine.State.Serialization?

  public init(
    stateURL: URL, containerIdentifier: String = CatalogCloudSync.containerIdentifier,
    sendEvent: @escaping @MainActor @Sendable (Event) -> Void
  ) {
    self.stateURL = stateURL
    self.containerIdentifier = containerIdentifier
    self.sendEvent = sendEvent
  }

  public func accountAvailability() async -> AccountAvailability {
    do {
      switch try await container.accountStatus() {
      case .available:
        guard let id = try? await container.userRecordID().recordName else { return .transient }
        return .available(id)
      case .noAccount, .restricted: return .unavailable
      case .couldNotDetermine, .temporarilyUnavailable: return .transient
      @unknown default: return .transient
      }
    } catch { return .transient }
  }

  public func start(
    accountIdentifier: String, entries: [CatalogEntry], conflicts: [UUID],
    pendingDeletions: [CatalogPendingDeletion], session: OperationToken
  ) async {
    guard session.operationID > lastCommandID else { return }
    lastCommandID = session.operationID
    generation &+= 1
    let startedGeneration = generation
    persistenceFailed = false
    sendFailed = false
    self.session = session
    active = false
    initializingGeneration = startedGeneration
    initialFetch = nil
    pendingDeletionByID = Dictionary(
      uniqueKeysWithValues: pendingDeletions.filter {
        $0.accountIdentifier == accountIdentifier
      }.map { ($0.id, $0) })
    deferredEngineState = nil
    publications.reset(for: session)
    let previous = engine
    engine = nil
    await previous?.cancelOperations()
    let availability = await accountAvailability()
    guard generation == startedGeneration, self.session == session, !Task.isCancelled else {
      return
    }
    guard case .available(let currentAccount) = availability,
      currentAccount == accountIdentifier
    else {
      initializingGeneration = nil
      await reportAccountUnavailable(availability, session: session)
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
      if !disk.opaqueRecordIDs.isEmpty { disk.engineState = nil }
      let local = Dictionary(
        uniqueKeysWithValues: entries.compactMap { entry in
          entry.scope == .iCloud && entry.accountIdentifier == accountIdentifier
            ? (entry.id, entry) : nil
        })
      if disk.engineState == nil {
        initialFetch = CatalogInitialFetch(
          entries: local,
          pendingDeletions: pendingDeletions.filter {
            $0.accountIdentifier == accountIdentifier
          }, opaqueRecordIDs: disk.opaqueRecordIDs)
      }
      let prior = disk.entries
      let replay = Self.cachedReplay(
        disk: disk, local: local, pendingDeletions: pendingDeletions,
        unresolvedConflicts: Set(conflicts))
      let replayIDs = Set(replay.map(\.id))
      disk.conflicts = Set(conflicts)
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
      created.state.remove(
        pendingRecordZoneChanges: Self.conflictingChanges(
          created.state.pendingRecordZoneChanges, disk: disk))
      if disk.engineState == nil || disk.zoneSaveFailed {
        created.state.add(pendingDatabaseChanges: [
          .saveZone(CKRecordZone(zoneName: Self.zoneName))
        ])
      }
      let saves = local.values.filter { entry in
        guard !disk.conflicts.contains(entry.id), !replayIDs.contains(entry.id),
          !disk.opaqueRecordIDs.contains(entry.id)
        else { return false }
        guard let previous = prior[entry.id] else { return entry.syncedVersion == nil }
        return !entry.sameCloudContents(as: previous)
          || entry.syncedVersion != entry.version
      }.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID($0.id)) }
      let deletions = pendingDeletions.filter {
        $0.accountIdentifier == accountIdentifier && !disk.conflicts.contains($0.id)
          && !replayIDs.contains($0.id) && !disk.opaqueRecordIDs.contains($0.id)
      }.map(\.id)
        .map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(Self.recordID($0)) }
      created.state.add(pendingRecordZoneChanges: saves + deletions)
      let pending =
        initialFetch != nil || !created.state.pendingDatabaseChanges.isEmpty
        || !created.state.pendingRecordZoneChanges.isEmpty || !disk.conflicts.isEmpty
        || !replay.isEmpty
      await sendEvent(
        .catalogCloudStatus(
          session, disk.opaqueRecordIDs.isEmpty ? (pending ? .pending : .ready) : .failed))
      if !replay.isEmpty {
        await sendEvent(.catalogCloudChanges(session, accountIdentifier, replay))
      }
      if generation == startedGeneration && initialFetch == nil {
        initializingGeneration = nil
        await processPublications()
      }
    } catch {
      initialFetch = nil
      deferredEngineState = nil
      initializingGeneration = nil
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
    initializingGeneration = nil
    initialFetch = nil
    pendingDeletionByID = [:]
    deferredEngineState = nil
    session = nil
    publications.reset(for: nil)
    let previous = engine
    engine = nil
    await previous?.cancelOperations()
  }

  public func queue(
    command: OperationToken, session requestedSession: OperationToken, resolvedConflicts: [UUID],
    saves: [CatalogEntry], deletions: [CatalogPendingDeletion]
  ) async {
    guard command.operationID > lastCommandID else { return }
    guard session == nil || session == requestedSession else { return }
    publications.append(
      CatalogPublication(
        command: command, session: requestedSession, resolvedConflicts: resolvedConflicts,
        saves: saves, deletions: deletions))
    await processPublications()
  }

  private func processPublications() async {
    if processingPublications {
      retryPublicationsAfterProcessing = true
      return
    }
    guard initializingGeneration == nil, active, let engine, let session,
      publications.hasPending
    else { return }
    processingPublications = true
    defer {
      processingPublications = false
      if retryPublicationsAfterProcessing {
        retryPublicationsAfterProcessing = false
        Task { await self.processPublications() }
      }
    }
    let queuedGeneration = generation
    let availability = await accountAvailability()
    guard generation == queuedGeneration, active, self.engine === engine,
      self.session == session, !Task.isCancelled
    else { return }
    guard let disk = self.disk else { return }
    guard case .available(let currentAccount) = availability,
      currentAccount == disk.accountIdentifier
    else {
      await reportAccountUnavailable(availability, session: session)
      return
    }
    while generation == queuedGeneration && active && self.engine === engine
      && self.session == session
    {
      guard let publication = publications.takeNext(for: session) else { break }
      do {
        guard var disk = self.disk else { return }
        let resolvedConflicts = publication.resolvedConflicts
        let saves = publication.saves
        let deletions = publication.deletions
        disk.conflicts.subtract(resolvedConflicts)
        let fetchedConflicts = Self.fetchedConflicts(
          saves: saves.filter { !disk.opaqueRecordIDs.contains($0.id) }, disk: disk,
          resolvedConflicts: Set(resolvedConflicts))
        let fetchedDeletionConflicts = deletions.filter {
          !disk.opaqueRecordIDs.contains($0.id)
        }.compactMap {
          Self.fetchedChangeConflictingWithDeletion($0, serverEntries: disk.serverEntries)
        }
        let allConflicts = fetchedConflicts + fetchedDeletionConflicts
        disk.conflicts.formUnion(allConflicts.map(\.id))
        for id in allConflicts.map(\.id) {
          engine.state.remove(pendingRecordZoneChanges: [
            .saveRecord(Self.recordID(id)), .deleteRecord(Self.recordID(id)),
          ])
        }
        let permittedSaves = saves.filter {
          !disk.conflicts.contains($0.id) && !disk.opaqueRecordIDs.contains($0.id)
        }
        let permittedDeletions = deletions.filter {
          $0.accountIdentifier == disk.accountIdentifier && !disk.conflicts.contains($0.id)
            && !disk.opaqueRecordIDs.contains($0.id)
        }
        for entry in permittedSaves {
          guard entry.scope == .iCloud, entry.accountIdentifier == disk.accountIdentifier,
            CatalogCloudPayload.encoded(entry) != nil
          else { throw Failure.invalidPayload }
          disk.entries[entry.id] = entry
        }
        for deletion in permittedDeletions {
          disk.entries.removeValue(forKey: deletion.id)
        }
        let acceptedDeletions = Self.dropResolvedServerDeletions(
          resolvedConflicts: resolvedConflicts, saves: permittedSaves, disk: &disk)
        for id in acceptedDeletions {
          engine.state.remove(pendingRecordZoneChanges: [.saveRecord(Self.recordID(id))])
        }
        self.disk = disk
        try persistDisk()
        for id in resolvedConflicts { pendingDeletionByID.removeValue(forKey: id) }
        for entry in saves { pendingDeletionByID.removeValue(forKey: entry.id) }
        for deletion in deletions where deletion.accountIdentifier == disk.accountIdentifier {
          pendingDeletionByID[deletion.id] = deletion
        }
        engine.state.add(
          pendingRecordZoneChanges:
            permittedSaves.map { .saveRecord(Self.recordID($0.id)) }
            + permittedDeletions.map { .deleteRecord(Self.recordID($0.id)) })
        let pending =
          !engine.state.pendingRecordZoneChanges.isEmpty
          || !engine.state.pendingDatabaseChanges.isEmpty || !disk.conflicts.isEmpty
          || publications.hasPending
        if !allConflicts.isEmpty {
          await sendEvent(.catalogCloudChanges(session, disk.accountIdentifier, allConflicts))
        }
        await sendEvent(
          .catalogCloudStatus(
            session,
            disk.opaqueRecordIDs.isEmpty && !persistenceFailed && !sendFailed
              ? (pending ? .pending : .ready) : .failed))
      } catch {
        await sendEvent(.catalogCloudStatus(session, .failed))
        return
      }
    }
  }

}

extension CatalogCloudSync {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard active, engine === syncEngine, var disk, let session else { return }
    switch event {
    case .stateUpdate(let update):
      if initialFetch == nil {
        disk.engineState = update.stateSerialization
      } else {
        deferredEngineState = update.stateSerialization
        disk.engineState = nil
      }
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
      initialFetch = nil
      initializingGeneration = nil
      deferredEngineState = nil
      engine = nil
      self.session = nil
      await sendEvent(.catalogCloudAccountChanged(session))

    case .fetchedRecordZoneChanges(let update):
      await handleFetchedRecordZoneChanges(update, syncEngine: syncEngine, session: session)

    case .fetchedDatabaseChanges(let update):
      if update.deletions.contains(where: { $0.zoneID == Self.catalogZoneID }) {
        initialFetch = nil
        initializingGeneration = nil
        deferredEngineState = nil
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { change in
          switch change {
          case .saveRecord(let id), .deleteRecord(let id):
            return id.zoneID == Self.catalogZoneID
          @unknown default: return false
          }
        }
        let engineDeletions = pending.compactMap { change -> UUID? in
          if case .deleteRecord(let id) = change { return Self.catalogID(from: id) }
          return nil
        }
        let completedDeletions = Self.reconcileDeletedZone(
          pendingEngineDeletions: engineDeletions,
          bufferedDeletions: pendingDeletionByID, disk: &disk)
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
        for id in completedDeletions { pendingDeletionByID.removeValue(forKey: id) }
        await sendEvent(.catalogCloudStatus(session, sendFailed ? .failed : .pending))
        await processPublications()
        if !completedDeletions.isEmpty {
          await sendEvent(
            .catalogCloudDeletionsAcknowledged(
              session, disk.accountIdentifier, completedDeletions))
        }
      }

    case .sentRecordZoneChanges(let update):
      await handleSentRecordZoneChanges(update, syncEngine: syncEngine, session: session)

    case .sentDatabaseChanges(let update):
      let savedZone = update.savedZones.contains { $0.zoneID == Self.catalogZoneID }
      let failedZoneSave = update.failedZoneSaves.contains {
        $0.zone.zoneID == Self.catalogZoneID
      }
      if savedZone || failedZoneSave {
        disk.zoneSaveFailed = failedZoneSave
        self.disk = disk
        do { try persistDisk() } catch {
          await sendEvent(.catalogCloudStatus(session, .failed))
          return
        }
      }
      var failures = SendFailures()
      for error in update.failedZoneSaves where error.zone.zoneID == Self.catalogZoneID {
        failures.record(Self.isTransient(error.error) ? .offline : .failed)
      }
      if let error = update.failedZoneDeletes[Self.catalogZoneID] {
        failures.record(Self.isTransient(error) ? .offline : .failed)
      }
      if let status = failures.status {
        if failures.hasNonretryable { sendFailed = true }
        await sendEvent(.catalogCloudStatus(session, sendFailed ? .failed : status))
      }

    case .willFetchChanges:
      fetchFailed = false
      if !persistenceFailed && !sendFailed && disk.opaqueRecordIDs.isEmpty {
        await sendEvent(.catalogCloudStatus(session, .pending))
      }

    case .didFetchRecordZoneChanges(let update):
      await handleDidFetchRecordZoneChanges(update, syncEngine: syncEngine, session: session)

    case .didFetchChanges, .didSendChanges:
      if publications.hasPending { await processPublications() }
      guard active, engine === syncEngine, self.session == session,
        let currentDisk = self.disk
      else { return }
      if !fetchFailed && !persistenceFailed && initialFetch == nil
        && Self.canReportReady(
          sendFailed: sendFailed,
          pendingRecordChanges: !syncEngine.state.pendingRecordZoneChanges.isEmpty,
          pendingDatabaseChanges: !syncEngine.state.pendingDatabaseChanges.isEmpty,
          bufferedPublications: publications.hasPending, disk: currentDisk)
      {
        await sendEvent(.catalogCloudStatus(session, .ready))
      }

    default: break
    }
  }

  private func handleDidFetchRecordZoneChanges(
    _ update: CKSyncEngine.Event.DidFetchRecordZoneChanges, syncEngine: CKSyncEngine,
    session: OperationToken
  ) async {
    guard update.zoneID == Self.catalogZoneID else { return }
    if let error = update.error {
      fetchFailed = true
      await sendEvent(.catalogCloudStatus(session, Self.isOffline(error) ? .offline : .failed))
    } else {
      await finishInitialFetch(syncEngine: syncEngine, session: session)
    }
  }

  private func finishInitialFetch(syncEngine: CKSyncEngine, session: OperationToken) async {
    guard let initialFetch, var disk else { return }
    let reconciliation = initialFetch.reconcile(&disk)
    disk.engineState = deferredEngineState
    self.disk = disk
    do { try persistDisk() } catch {
      await sendEvent(.catalogCloudStatus(session, .failed))
      return
    }
    self.initialFetch = nil
    deferredEngineState = nil
    initializingGeneration = nil
    let staleSaves = reconciliation.changes.compactMap {
      change -> CKSyncEngine.PendingRecordZoneChange? in
      if case .delete(let id) = change { return .saveRecord(Self.recordID(id)) }
      return nil
    }
    syncEngine.state.remove(pendingRecordZoneChanges: staleSaves)
    syncEngine.state.add(
      pendingRecordZoneChanges: reconciliation.resumingSaves.map {
        .saveRecord(Self.recordID($0))
      })
    if !reconciliation.changes.isEmpty {
      await sendEvent(
        .catalogCloudChanges(session, disk.accountIdentifier, reconciliation.changes))
    }
    await processPublications()
    let pending = syncEngine.state.pendingRecordZoneChanges
    if !pending.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: pending) }
  }

  private func observeInitialFetch(_ id: UUID) {
    guard var initialFetch else { return }
    initialFetch.observe(id)
    self.initialFetch = initialFetch
  }

  private func handleFetchedRecordZoneChanges(
    _ update: CKSyncEngine.Event.FetchedRecordZoneChanges, syncEngine: CKSyncEngine,
    session: OperationToken
  ) async {
    guard var disk else { return }
    var changes: [CatalogCloudChange] = []
    var foundOpaque = false
    for modification in update.modifications {
      let record = modification.record
      let id: UUID
      let payload: CatalogEntry
      switch Self.classifyFetchedRecord(record, accountIdentifier: disk.accountIdentifier) {
      case .unrelated: continue
      case .opaque(let opaqueID):
        observeInitialFetch(opaqueID)
        disk.opaqueRecordIDs.insert(opaqueID)
        syncEngine.state.remove(pendingRecordZoneChanges: [
          .saveRecord(record.recordID), .deleteRecord(record.recordID),
        ])
        foundOpaque = true
        continue
      case .valid(let validID, let validEntry):
        id = validID
        payload = validEntry
        observeInitialFetch(id)
        if let resumed = Self.reconcileReadableOpaqueRecord(
          payload, systemFields: Self.systemFields(record),
          pendingDeletion: pendingDeletionByID[id], disk: &disk)
        {
          syncEngine.state.add(pendingRecordZoneChanges: [resumed])
          continue
        }
      }
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
        if pendingDeletionByID[id]?.baseVersion == payload.version {
          disk.recordSystemFields[id] = Self.systemFields(record)
          disk.serverEntries[id] = payload
          disk.serverDeletions.remove(id)
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
      observeInitialFetch(id)
      if let recovered = Self.reconcileDeletedOpaqueRecord(
        id, pendingDeletion: pendingDeletionByID[id], disk: &disk)
      {
        switch recovered {
        case .resumeSave(let pending):
          syncEngine.state.add(pendingRecordZoneChanges: [pending])
        case .deleted(let removedID): changes.append(.delete(removedID))
        }
        continue
      }
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
    for deletion in update.deletions {
      guard let id = Self.catalogID(from: deletion.recordID),
        !disk.entries.keys.contains(id)
      else { continue }
      pendingDeletionByID.removeValue(forKey: id)
    }
    if !changes.isEmpty {
      await sendEvent(.catalogCloudChanges(session, disk.accountIdentifier, changes))
    }
    if foundOpaque || !disk.opaqueRecordIDs.isEmpty {
      await sendEvent(.catalogCloudStatus(session, .failed))
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
    var failures = SendFailures()
    for record in update.savedRecords {
      guard let id = Self.catalogID(from: record.recordID),
        let entry = Self.entry(from: record, accountIdentifier: disk.accountIdentifier)
      else { continue }
      disk.recordSystemFields[id] = Self.systemFields(record)
      disk.serverEntries[id] = entry
      disk.serverDeletions.remove(id)
      disk.opaqueRecordIDs.remove(id)
      acknowledged[id] = entry.version
    }
    for id in update.deletedRecordIDs.compactMap(Self.catalogID(from:)) {
      disk.recordSystemFields.removeValue(forKey: id)
      disk.serverEntries.removeValue(forKey: id)
      disk.serverDeletions.insert(id)
      disk.opaqueRecordIDs.remove(id)
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
            switch Self.reconcileServerRecordChangedSave(remote, disk: &disk) {
            case .acknowledged(let version): acknowledged[id] = version
            case .conflict(let change): conflicts.append(change)
            }
          } else {
            disk.opaqueRecordIDs.insert(id)
            failures.record(.failed)
            disk.conflicts.insert(id)
          }
        } else {
          failures.record(.failed)
          disk.conflicts.insert(id)
        }
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(Self.recordID(id))])
      case .unknownItem:
        disk.conflicts.insert(id)
        disk.serverEntries.removeValue(forKey: id)
        disk.serverDeletions.insert(id)
        conflicts.append(.delete(id))
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(Self.recordID(id))])
      default:
        failures.record(Self.isTransient(failure.error) ? .offline : .failed)
      }
    }
    if !update.failedRecordDeletes.isEmpty {
      for (recordID, error) in update.failedRecordDeletes {
        guard let id = Self.catalogID(from: recordID) else { continue }
        if error.code == .serverRecordChanged, let server = error.serverRecord {
          disk.conflicts.insert(id)
          syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(recordID)])
          if let remote = Self.entry(from: server, accountIdentifier: disk.accountIdentifier) {
            disk.recordSystemFields[id] = Self.systemFields(server)
            disk.serverEntries[id] = remote
            disk.serverDeletions.remove(id)
            disk.opaqueRecordIDs.remove(id)
            conflicts.append(.upsert(remote))
          } else {
            disk.opaqueRecordIDs.insert(id)
            failures.record(.failed)
          }
        } else if error.code == .unknownItem {
          disk.recordSystemFields.removeValue(forKey: id)
          disk.serverEntries.removeValue(forKey: id)
          disk.serverDeletions.insert(id)
          syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(recordID)])
          acknowledgedDeletions.append(id)
        } else {
          failures.record(Self.isTransient(error) ? .offline : .failed)
        }
      }
    }
    self.disk = disk
    do { try persistDisk() } catch {
      await sendEvent(.catalogCloudStatus(session, .failed))
      return
    }
    for id in acknowledgedDeletions { pendingDeletionByID.removeValue(forKey: id) }
    if let status = failures.status {
      if failures.hasNonretryable { sendFailed = true }
      await sendEvent(.catalogCloudStatus(session, sendFailed ? .failed : status))
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
    guard active, engine === syncEngine, initialFetch == nil, let session else { return nil }
    let batchGeneration = generation
    let availability = await accountAvailability()
    guard active, engine === syncEngine, generation == batchGeneration,
      self.session == session, !Task.isCancelled
    else { return nil }
    guard let disk = self.disk else { return nil }
    guard case .available(let currentAccount) = availability,
      currentAccount == disk.accountIdentifier
    else {
      await reportAccountUnavailable(availability, session: session)
      return nil
    }
    let inScope = syncEngine.state.pendingRecordZoneChanges.filter { change in
      guard context.options.scope.contains(change) else { return false }
      return true
    }
    let pending = Self.sendableChanges(inScope, disk: disk)
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
      let disk = try JSONDecoder().decode(DiskState.self, from: data)
      guard disk.isValid else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "Invalid catalog cloud cache"))
      }
      return disk
    } catch is DecodingError {
      let quarantine = URL(fileURLWithPath: stateURL.path + ".invalid-" + UUID().uuidString)
      try FileManager.default.moveItem(at: stateURL, to: quarantine)
      return nil
    }
  }

  private func persistDisk() throws {
    guard let disk else { return }
    do {
      let directory = stateURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try JSONEncoder().encode(disk).write(to: stateURL, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    } catch {
      persistenceFailed = true
      throw error
    }
  }

  private static func recordID(_ id: UUID) -> CKRecord.ID {
    CKRecord.ID(recordName: id.uuidString, zoneID: CKRecordZone.ID(zoneName: zoneName))
  }

  private static var catalogZoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName) }

  private static func catalogID(from recordID: CKRecord.ID) -> UUID? {
    guard recordID.zoneID == catalogZoneID else { return nil }
    return UUID(uuidString: recordID.recordName)
  }

  static func cachedReplay(
    disk: DiskState, local: [UUID: CatalogEntry],
    pendingDeletions: [CatalogPendingDeletion], unresolvedConflicts: Set<UUID> = []
  ) -> [CatalogCloudChange] {
    disk.serverEntries.values.compactMap { remote -> CatalogCloudChange? in
      if disk.opaqueRecordIDs.contains(remote.id) { return nil }
      if let chosenLocal = local[remote.id], chosenLocal.version > remote.version,
        chosenLocal.syncedVersion != chosenLocal.version,
        !unresolvedConflicts.contains(remote.id),
        let resolvedVersion = chosenLocal.resolvedConflictVersion,
        resolvedVersion > remote.version
      {
        return nil
      }
      if let localEntry = local[remote.id], localEntry.syncedVersion == remote.version {
        return nil
      }
      if let deletion = pendingDeletions.first(where: {
        $0.id == remote.id && $0.accountIdentifier == disk.accountIdentifier
      }), deletion.baseVersion == remote.version {
        return nil
      }
      return .upsert(remote)
    }
      + disk.serverDeletions.compactMap { id -> CatalogCloudChange? in
        if disk.opaqueRecordIDs.contains(id) { return nil }
        let wasSynced = local[id]?.syncedVersion != nil
        let pendingDeletion = pendingDeletions.contains {
          $0.id == id && $0.accountIdentifier == disk.accountIdentifier
        }
        return wasSynced || pendingDeletion ? .delete(id) : nil
      }
  }

  static func reconcileDeletedZone(
    pendingEngineDeletions: [UUID],
    bufferedDeletions: [UUID: CatalogPendingDeletion], disk: inout DiskState
  ) -> [UUID] {
    let acknowledged = Set(pendingEngineDeletions).union(
      bufferedDeletions.values.compactMap { deletion in
        deletion.accountIdentifier == disk.accountIdentifier ? deletion.id : nil
      })
    disk.serverEntries = [:]
    disk.serverDeletions = []
    disk.recordSystemFields = [:]
    disk.opaqueRecordIDs = []
    disk.conflicts.subtract(acknowledged)
    return acknowledged.sorted { $0.uuidString < $1.uuidString }
  }

  enum OpaqueDeletionRecovery: Equatable {
    case resumeSave(CKSyncEngine.PendingRecordZoneChange)
    case deleted(UUID)
  }

  static func reconcileDeletedOpaqueRecord(
    _ id: UUID, pendingDeletion: CatalogPendingDeletion?, disk: inout DiskState
  ) -> OpaqueDeletionRecovery? {
    let wasOpaque = disk.opaqueRecordIDs.remove(id) != nil
    guard wasOpaque else { return nil }
    if pendingDeletion?.accountIdentifier == disk.accountIdentifier {
      disk.entries.removeValue(forKey: id)
      disk.serverEntries.removeValue(forKey: id)
      disk.serverDeletions.insert(id)
      disk.recordSystemFields.removeValue(forKey: id)
      disk.conflicts.remove(id)
      return .deleted(id)
    }
    guard let local = disk.entries[id], local.syncedVersion == nil else { return nil }
    disk.serverEntries.removeValue(forKey: id)
    disk.serverDeletions.remove(id)
    disk.recordSystemFields.removeValue(forKey: id)
    disk.conflicts.remove(id)
    return .resumeSave(.saveRecord(recordID(id)))
  }

  static func reconcileReadableOpaqueRecord(
    _ remote: CatalogEntry, systemFields: Data, pendingDeletion: CatalogPendingDeletion?,
    disk: inout DiskState
  ) -> CKSyncEngine.PendingRecordZoneChange? {
    let wasOpaque = disk.opaqueRecordIDs.remove(remote.id) != nil
    guard wasOpaque, pendingDeletion?.baseVersion == remote.version else { return nil }
    disk.recordSystemFields[remote.id] = systemFields
    disk.serverEntries[remote.id] = remote
    disk.serverDeletions.remove(remote.id)
    disk.conflicts.remove(remote.id)
    return .deleteRecord(recordID(remote.id))
  }

  static func sendableChanges(
    _ changes: [CKSyncEngine.PendingRecordZoneChange], disk: DiskState
  ) -> [CKSyncEngine.PendingRecordZoneChange] {
    changes.filter { change in
      switch change {
      case .saveRecord(let id), .deleteRecord(let id):
        return catalogID(from: id).map {
          !disk.conflicts.contains($0) && !disk.opaqueRecordIDs.contains($0)
        } ?? false
      @unknown default: return false
      }
    }
  }

  static func conflictingChanges(
    _ changes: [CKSyncEngine.PendingRecordZoneChange], disk: DiskState
  ) -> [CKSyncEngine.PendingRecordZoneChange] {
    changes.filter { change in
      switch change {
      case .saveRecord(let id), .deleteRecord(let id):
        return catalogID(from: id).map { disk.conflicts.contains($0) } ?? false
      @unknown default: return false
      }
    }
  }

  static func canReportReady(
    sendFailed: Bool, pendingRecordChanges: Bool, pendingDatabaseChanges: Bool,
    bufferedPublications: Bool, disk: DiskState
  ) -> Bool {
    !sendFailed && !pendingRecordChanges && !pendingDatabaseChanges && !bufferedPublications
      && disk.conflicts.isEmpty && disk.opaqueRecordIDs.isEmpty
  }

  private static func isOffline(_ error: CKError) -> Bool {
    error.code == .networkUnavailable || error.code == .networkFailure
      || error.code == .serviceUnavailable || error.code == .zoneBusy
  }

  static func isTransient(_ error: CKError) -> Bool {
    isOffline(error) || error.code == .notAuthenticated || error.code == .operationCancelled
      || error.code == .requestRateLimited || error.code == .accountTemporarilyUnavailable
  }

  private func reportAccountUnavailable(
    _ availability: AccountAvailability, session: OperationToken
  ) async {
    switch availability {
    case .transient: await sendEvent(.catalogCloudStatus(session, .offline))
    case .available, .unavailable: await sendEvent(.catalogCloudAccountChanged(session))
    }
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

  static func classifyFetchedRecord(
    _ record: CKRecord, accountIdentifier: String
  ) -> FetchedCatalogRecord {
    guard let id = catalogID(from: record.recordID) else {
      return .unrelated
    }
    guard let entry = entry(from: record, accountIdentifier: accountIdentifier) else {
      return .opaque(id)
    }
    return .valid(id, entry)
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
