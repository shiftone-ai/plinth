import CloudKit
import Foundation
import KioskCore

public protocol RemoteDirectoryPort: Sendable {
  func load() async throws -> RemoteInstallation
  func accountAvailability() async -> RemoteAccountAvailability
  func checkAccount() async throws -> RemoteAccountCheck
  func start(
    accountIdentifier: String, installation: RemoteInstallation, session: OperationToken
  ) async
  func stop(command: OperationToken?) async
  func refresh(session: OperationToken) async
  func setEnabled(_ enabled: Bool, accountIdentifier: String) async throws -> RemoteInstallation
  func sendPairingRequest(
    target: RemoteDevice, code: String, requestID: UUID,
    accountIdentifier: String, command: OperationToken
  ) async throws
  func respondToPairing(
    _ proposal: RemotePairingProposal, approved: Bool
  ) async throws -> RemoteInstallation
  func saveTargetGrant(
    _ grant: RemotePeerGrant, requestID: UUID
  ) async throws -> RemoteInstallation
  func revokeController(
    _ id: UUID, accountIdentifier: String
  ) async throws -> RemoteInstallation
  func sendCommand(
    target: RemotePeerGrant, command: RemoteCommandPayload,
    requestID: UUID, accountIdentifier: String, operation: OperationToken
  ) async throws
  func claimCommand(_ request: RemoteCommandRequest) async throws -> RemoteInstallation
  func sendResult(
    for request: RemoteCommandRequest, outcome: RemoteCommandOutcome
  ) async throws
}

/// Publishes only discoverable device metadata in a zone separate from the settings catalog.
public actor RemoteDirectoryCloudSync: RemoteDirectoryPort, CKSyncEngineDelegate {
  enum Failure: Error { case accountChanged, invalidMessage }
  public nonisolated static let containerIdentifier = CatalogCloudSync.containerIdentifier
  private nonisolated static let zoneName = "RemoteAdministration"
  nonisolated static let recordType = "RemoteDevice"
  nonisolated static let zoneID = CKRecordZone.ID(zoneName: zoneName)
  nonisolated static let messageRecordType = "RemoteMessage"

  private let stateURL: URL
  private let containerIdentifier: String
  private let engineHost: CloudSyncEngineHost
  private let cloudAvailable: Bool
  let displayName: String
  let platform: RemoteDevicePlatform
  private let identityStore: RemoteIdentityKeyStore
  let sendEvent: @MainActor @Sendable (Event) -> Void
  var installation: RemoteInstallation?
  var identity: RemoteIdentity?
  var engine: CKSyncEngine?
  var accountIdentifier: String?
  var session: OperationToken?
  var devices: [UUID: RemoteDevice] = [:]
  var outgoingMessages: [CKRecord.ID: RemoteOutgoingCloudMessage] = [:]
  var pairingTargets: [UUID: RemoteDevice] = [:]
  var seenMessageIDs: Set<CKRecord.ID> = []
  var messageExpirations: [CKRecord.ID: Int64] = [:]
  var messageExpiryTask: Task<Void, Never>?
  var ownRecordSystemFields: Data?
  var awaitingInitialFetch = false
  var fetchFailed = false
  var sendFailed = false
  private var generation: UInt64 = 0
  private var lastCommandID: UInt64 = 0

  public init(
    stateURL: URL, displayName: String, platform: RemoteDevicePlatform,
    cloudAvailable: Bool = true,
    keychain: CredentialStore.Keychain = .platformDefault,
    containerIdentifier: String = RemoteDirectoryCloudSync.containerIdentifier,
    engineHost: CloudSyncEngineHost? = nil,
    sendEvent: @escaping @MainActor @Sendable (Event) -> Void
  ) {
    self.stateURL = stateURL
    self.cloudAvailable = cloudAvailable
    self.displayName = String(
      displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    self.platform = platform
    identityStore = RemoteIdentityKeyStore(keychain: keychain)
    self.containerIdentifier = containerIdentifier
    self.engineHost = engineHost ?? CloudSyncEngineHost(containerIdentifier: containerIdentifier)
    self.sendEvent = sendEvent
  }

  public func load() throws -> RemoteInstallation {
    if let installation { return installation }
    let loaded: RemoteInstallation
    if FileManager.default.fileExists(atPath: stateURL.path) {
      loaded = try JSONDecoder().decode(
        RemoteInstallation.self, from: Data(contentsOf: stateURL))
    } else {
      loaded = RemoteInstallation(id: UUID())
      try persist(loaded)
    }
    installation = loaded
    return loaded
  }

  public func accountAvailability() async -> RemoteAccountAvailability {
    guard cloudAvailable else { return .unsupported }
    let container = CKContainer(identifier: containerIdentifier)
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

  public func checkAccount() async throws -> RemoteAccountCheck {
    let availability = await accountAvailability()
    let current = try load()
    var updated = current
    updated.reconcileAccount(availability)
    if updated != current {
      try persist(updated)
      installation = updated
    }
    return RemoteAccountCheck(availability: availability, installation: updated)
  }

  public func start(
    accountIdentifier: String, installation: RemoteInstallation, session: OperationToken
  ) async {
    guard session.operationID > lastCommandID else { return }
    lastCommandID = session.operationID
    await clearSession()
    let startingGeneration = generation
    guard case .available(let currentAccount) = await accountAvailability(),
      currentAccount == accountIdentifier
    else {
      await sendEvent(.remoteAccountAvailabilityChanged)
      return
    }
    guard generation == startingGeneration, lastCommandID == session.operationID else { return }
    let loadedIdentity: RemoteIdentity
    do {
      loadedIdentity = try await identityStore.loadOrCreate(installationID: installation.id)
    } catch {
      guard generation == startingGeneration, lastCommandID == session.operationID else { return }
      await sendEvent(.remoteDirectoryStatusChanged(session, .failed))
      return
    }
    guard generation == startingGeneration, lastCommandID == session.operationID else { return }
    generation &+= 1
    let started = generation
    self.installation = installation
    identity = loadedIdentity
    self.accountIdentifier = accountIdentifier
    self.session = session
    devices = [:]
    ownRecordSystemFields = nil
    awaitingInitialFetch = true
    fetchFailed = false
    sendFailed = false
    guard
      let created = await engineHost.attachRemote(
        self, accountIdentifier: accountIdentifier, session: session)
    else { return }
    guard generation == started, self.session == session else {
      await engineHost.finishRemoteRegistration(session: session)
      return
    }
    engine = created
    created.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
    await engineHost.finishRemoteRegistration(session: session)
    await sendEvent(.remoteDirectoryStatusChanged(session, .checking))
    // CKSyncEngine may enter its delegate as soon as the zone is queued. A send or
    // fetch awaited by that callback's task traps, so begin the initial sync in
    // a detached task after registration completes.
    Task.detached { [weak self] in
      await self?.performInitialSync(engine: created, generation: started, session: session)
    }
  }

  private func performInitialSync(
    engine created: CKSyncEngine, generation started: UInt64, session: OperationToken
  ) async {
    guard generation == started, engine === created, self.session == session else { return }
    do {
      try await created.sendChanges()
      guard generation == started, engine === created else { return }
      try await created.fetchChanges()
    } catch {
      guard generation == started, engine === created else { return }
      await sendEvent(.remoteDirectoryStatusChanged(session, Self.status(for: error)))
    }
  }

  public func stop(command: OperationToken? = nil) async {
    if let command {
      guard command.operationID >= lastCommandID else { return }
      lastCommandID = command.operationID
    } else {
      lastCommandID = .max
    }
    await clearSession()
  }

  private func clearSession() async {
    generation &+= 1
    let previousSession = session
    engine = nil
    accountIdentifier = nil
    session = nil
    identity = nil
    devices = [:]
    outgoingMessages = [:]
    pairingTargets = [:]
    seenMessageIDs = []
    messageExpirations = [:]
    messageExpiryTask?.cancel()
    messageExpiryTask = nil
    ownRecordSystemFields = nil
    awaitingInitialFetch = false
    fetchFailed = false
    sendFailed = false
    if let previousSession { await engineHost.detachRemote(self, session: previousSession) }
  }

  func adoptSharedEngine(_ shared: CKSyncEngine?, fullFetch: Bool) async {
    engine = shared
    if fullFetch {
      devices = [:]
      ownRecordSystemFields = nil
      awaitingInitialFetch = true
      fetchFailed = false
      sendFailed = false
      if let session, let accountIdentifier {
        await sendEvent(.remoteDirectoryStatusChanged(session, .checking))
        await publishDevices(session: session, accountIdentifier: accountIdentifier)
      }
    }
  }

  func sharedEngineInvalidated() async {
    generation &+= 1
    engine = nil
    session = nil
    accountIdentifier = nil
    devices = [:]
    outgoingMessages = [:]
    pairingTargets = [:]
    seenMessageIDs = []
    messageExpirations = [:]
    messageExpiryTask?.cancel()
    messageExpiryTask = nil
    ownRecordSystemFields = nil
    await sendEvent(.remoteAccountAvailabilityChanged)
  }
}

extension RemoteDirectoryCloudSync {
  public func refresh(session requestedSession: OperationToken) async {
    Task.detached { [weak self] in
      await self?.performRefresh(session: requestedSession)
    }
  }

  private func performRefresh(session requestedSession: OperationToken) async {
    guard session == requestedSession, let engine, let accountIdentifier else { return }
    guard case .available(let currentAccount) = await accountAvailability(),
      currentAccount == accountIdentifier
    else {
      await sendEvent(.remoteAccountAvailabilityChanged)
      return
    }
    guard session == requestedSession, self.engine === engine else { return }
    do { try await engine.fetchChanges() } catch {
      guard session == requestedSession, self.engine === engine else { return }
      await sendEvent(.remoteDirectoryStatusChanged(requestedSession, Self.status(for: error)))
    }
  }

  public func setEnabled(
    _ enabled: Bool, accountIdentifier requestedAccount: String
  ) async throws -> RemoteInstallation {
    guard case .available(let currentAccount) = await accountAvailability(),
      currentAccount == requestedAccount, accountIdentifier == requestedAccount,
      let current = installation
    else { throw Failure.accountChanged }
    var updated = current
    if enabled {
      updated.enabledAccountIdentifier = requestedAccount
    } else {
      updated.disableRemoteManagement()
    }
    try persist(updated)
    installation = updated
    if let engine {
      let change: CKSyncEngine.PendingRecordZoneChange =
        enabled
        ? .saveRecord(Self.recordID(current.id)) : .deleteRecord(Self.recordID(current.id))
      engine.state.add(pendingRecordZoneChanges: [change])
      if let session { await sendEvent(.remoteDirectoryStatusChanged(session, .checking)) }
      if let session { await sendQueuedChanges(in: engine, session: session) }
    }
    return updated
  }

  func persist(_ value: RemoteInstallation) throws {
    let directory = stateURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(value).write(to: stateURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: stateURL.path)
  }

  nonisolated static func recordID(_ id: UUID) -> CKRecord.ID {
    CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
  }

  nonisolated static func status(for error: Error) -> RemoteDirectoryStatus {
    guard let error = error as? CKError else { return .failed }
    switch error.code {
    case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
      .zoneBusy, .serverResponseLost:
      return .offline
    case .notAuthenticated: return .signInRequired
    default: return .failed
    }
  }
}
