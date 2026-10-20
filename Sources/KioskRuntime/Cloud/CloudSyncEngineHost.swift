import CloudKit
import Foundation
import KioskCore

/// One sync engine owns the private database; the catalog and remote directory own separate zones.
public actor CloudSyncEngineHost: CKSyncEngineDelegate {
  public static let shared = CloudSyncEngineHost()
  private let containerIdentifier: String
  private var engine: CKSyncEngine?
  private var accountIdentifier: String?
  private var catalog: CatalogCloudSync?
  private var catalogSession: OperationToken?
  private var remote: RemoteDirectoryCloudSync?
  private var remoteSession: OperationToken?
  private var transactionActive = false
  private var transactionWaiters: [CheckedContinuation<Void, Never>] = []
  private enum Registration: Equatable {
    case catalog(OperationToken)
    case remote(OperationToken)
  }
  private var registrationPending: Registration?
  private var registrationWaiters: [CheckedContinuation<Void, Never>] = []

  public init(containerIdentifier: String = CatalogCloudSync.containerIdentifier) {
    self.containerIdentifier = containerIdentifier
  }

  func attachCatalog(
    _ client: CatalogCloudSync, accountIdentifier: String,
    session: OperationToken, state: CKSyncEngine.State.Serialization?
  ) async -> CKSyncEngine? {
    await beginReadyTransaction()
    defer { endTransaction() }
    if catalog === client, let catalogSession,
      catalogSession.operationID > session.operationID
    {
      return nil
    }
    await prepareAccount(accountIdentifier)
    let replaced = catalog !== client ? catalog : nil
    let joining = catalog !== client
    catalog = client
    catalogSession = session
    await replaced?.sharedEngineInvalidated()
    let attached = await makeEngineIfNeeded(
      accountIdentifier: accountIdentifier, state: state,
      rebuild: joining && engine != nil)
    if attached != nil { registrationPending = .catalog(session) }
    return attached
  }

  func attachRemote(
    _ client: RemoteDirectoryCloudSync, accountIdentifier: String,
    session: OperationToken
  ) async -> CKSyncEngine? {
    await beginReadyTransaction()
    defer { endTransaction() }
    if remote === client, let remoteSession,
      remoteSession.operationID > session.operationID
    {
      return nil
    }
    await prepareAccount(accountIdentifier)
    let replaced = remote !== client ? remote : nil
    let joining = remote !== client
    remote = client
    remoteSession = session
    await replaced?.sharedEngineInvalidated()
    if replaced != nil, let engine {
      engine.state.remove(
        pendingRecordZoneChanges:
          engine.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case .saveRecord(let id), .deleteRecord(let id):
              id.zoneID == RemoteDirectoryCloudSync.zoneID
            @unknown default: false
            }
          })
    }
    let attached = await makeEngineIfNeeded(
      accountIdentifier: accountIdentifier, state: nil,
      rebuild: joining && engine != nil)
    if attached != nil { registrationPending = .remote(session) }
    return attached
  }

  func finishCatalogRegistration(session: OperationToken) async {
    await beginTransaction()
    defer { endTransaction() }
    if registrationPending == .catalog(session) { finishRegistration() }
  }

  func finishRemoteRegistration(session: OperationToken) async {
    await beginTransaction()
    defer { endTransaction() }
    if registrationPending == .remote(session) { finishRegistration() }
  }

  func detachCatalog(_ client: CatalogCloudSync, session: OperationToken) async {
    if registrationPending == .catalog(session) {
      await beginTransaction()
    } else {
      await beginReadyTransaction()
    }
    defer { endTransaction() }
    guard catalog === client, catalogSession == session else { return }
    if registrationPending == .catalog(session) { finishRegistration() }
    catalog = nil
    catalogSession = nil
    await releaseIfUnused()
  }

  func detachRemote(_ client: RemoteDirectoryCloudSync, session: OperationToken) async {
    if registrationPending == .remote(session) {
      await beginTransaction()
    } else {
      await beginReadyTransaction()
    }
    defer { endTransaction() }
    guard remote === client, remoteSession == session else { return }
    if registrationPending == .remote(session) { finishRegistration() }
    remote = nil
    remoteSession = nil
    await releaseIfUnused()
  }

  private func prepareAccount(_ requested: String) async {
    guard let accountIdentifier, accountIdentifier != requested else { return }
    let oldCatalog = catalog
    let oldRemote = remote
    catalog = nil
    catalogSession = nil
    remote = nil
    remoteSession = nil
    await disposeEngine()
    await oldCatalog?.sharedEngineInvalidated()
    await oldRemote?.sharedEngineInvalidated()
  }

  private func makeEngineIfNeeded(
    accountIdentifier: String, state: CKSyncEngine.State.Serialization?, rebuild: Bool
  ) async -> CKSyncEngine? {
    if let engine, !rebuild { return engine }
    let pendingRecords = engine?.state.pendingRecordZoneChanges ?? []
    let pendingDatabase = engine?.state.pendingDatabaseChanges ?? []
    if rebuild { await disposeEngine() }
    var configuration = CKSyncEngine.Configuration(
      database: CKContainer(identifier: containerIdentifier).privateCloudDatabase,
      stateSerialization: rebuild ? nil : state, delegate: self)
    configuration.automaticallySync = true
    let created = CKSyncEngine(configuration)
    engine = created
    self.accountIdentifier = accountIdentifier
    // The catalog's persisted engine token can contain remote work from a previous run.
    // Remote messages live only in the remote adapter, so those old saves have no payload.
    if remote == nil, !rebuild {
      created.state.remove(
        pendingRecordZoneChanges:
          created.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case .saveRecord(let id), .deleteRecord(let id):
              id.zoneID == RemoteDirectoryCloudSync.zoneID
            @unknown default: false
            }
          })
      created.state.remove(
        pendingDatabaseChanges:
          created.state.pendingDatabaseChanges.filter { change in
            switch change {
            case .saveZone(let zone): zone.zoneID == RemoteDirectoryCloudSync.zoneID
            case .deleteZone(let id): id == RemoteDirectoryCloudSync.zoneID
            @unknown default: false
            }
          })
    }
    await catalog?.adoptSharedEngine(created, fullFetch: rebuild)
    await remote?.adoptSharedEngine(created, fullFetch: rebuild)
    created.state.add(pendingDatabaseChanges: pendingDatabase)
    created.state.add(pendingRecordZoneChanges: pendingRecords)
    return created
  }

  private func releaseIfUnused() async {
    guard catalog == nil, remote == nil else { return }
    await disposeEngine()
  }

  private func disposeEngine() async {
    let previous = engine
    engine = nil
    accountIdentifier = nil
    await catalog?.adoptSharedEngine(nil, fullFetch: false)
    await remote?.adoptSharedEngine(nil, fullFetch: false)
    // A Root effect can be scheduled by a delegate event. Keep cancellation out
    // of that callback's task; CKSyncEngine traps on a nested awaited call.
    if let previous {
      Task.detached { await previous.cancelOperations() }
    }
  }

  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    await beginReadyTransaction()
    defer { endTransaction() }
    guard engine === syncEngine else { return }
    await catalog?.handleEvent(event, syncEngine: syncEngine)
    await remote?.handleEvent(event, syncEngine: syncEngine)
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    await beginReadyTransaction()
    defer { endTransaction() }
    guard engine === syncEngine else { return nil }
    let catalogBatch = await catalog?.nextRecordZoneChangeBatch(context, syncEngine: syncEngine)
    let remoteBatch = await remote?.nextRecordZoneChangeBatch(context, syncEngine: syncEngine)
    guard catalogBatch != nil || remoteBatch != nil else { return nil }
    return CKSyncEngine.RecordZoneChangeBatch(
      recordsToSave: (catalogBatch?.recordsToSave ?? []) + (remoteBatch?.recordsToSave ?? []),
      recordIDsToDelete: (catalogBatch?.recordIDsToDelete ?? [])
        + (remoteBatch?.recordIDsToDelete ?? []))
  }

  private func beginTransaction() async {
    if transactionActive {
      await withCheckedContinuation { transactionWaiters.append($0) }
    } else {
      transactionActive = true
    }
  }

  private func beginReadyTransaction() async {
    while true {
      await beginTransaction()
      if registrationPending == nil { return }
      endTransaction()
      await withCheckedContinuation { waiter in
        if registrationPending == nil {
          waiter.resume()
        } else {
          registrationWaiters.append(waiter)
        }
      }
    }
  }

  private func finishRegistration() {
    registrationPending = nil
    let waiting = registrationWaiters
    registrationWaiters.removeAll()
    for waiter in waiting { waiter.resume() }
  }

  private func endTransaction() {
    if transactionWaiters.isEmpty {
      transactionActive = false
    } else {
      transactionWaiters.removeFirst().resume()
    }
  }
}
