import CloudKit
import Foundation
import KioskCore

extension RemoteDirectoryCloudSync {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard engine === syncEngine, let session, let accountIdentifier else { return }
    switch event {
    case .accountChange(let change):
      if case .signIn(let currentUser) = change.changeType,
        currentUser.recordName == accountIdentifier
      {
        return
      }
      await sendEvent(.remoteAccountAvailabilityChanged)

    case .fetchedDatabaseChanges(let update):
      if update.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
        devices = [:]
        ownRecordSystemFields = nil
        needsOwnRecordAfterZoneRecovery = true
        syncEngine.state.add(pendingDatabaseChanges: [
          .saveZone(CKRecordZone(zoneID: Self.zoneID))
        ])
        await publishDevices(session: session, accountIdentifier: accountIdentifier)
      }

    case .fetchedRecordZoneChanges(let update):
      await handleFetchedRecordZoneChanges(
        update, session: session, accountIdentifier: accountIdentifier)

    case .willFetchChanges:
      fetchFailed = false

    case .didFetchChanges:
      if awaitingInitialFetch {
        awaitingInitialFetch = false
        queueOwnRecord(in: syncEngine)
      }
      await publishDevices(session: session, accountIdentifier: accountIdentifier)
      await reportReady(syncEngine, session: session)

    case .sentRecordZoneChanges(let update):
      await handleSentRecordZoneChanges(
        update, syncEngine: syncEngine, session: session)

    case .didFetchRecordZoneChanges(let update):
      if update.zoneID == Self.zoneID, let error = update.error {
        fetchFailed = true
        await sendEvent(.remoteDirectoryStatusChanged(session, Self.status(for: error)))
      }

    case .sentDatabaseChanges(let update):
      if update.savedZones.contains(where: { $0.zoneID == Self.zoneID }) {
        sendFailed = false
        if let change = recoveredOwnRecordChangeIfNeeded() {
          syncEngine.state.add(pendingRecordZoneChanges: [change])
        }
      }
      if update.failedZoneSaves.contains(where: { $0.zone.zoneID == Self.zoneID }) {
        sendFailed = true
        await sendEvent(.remoteDirectoryStatusChanged(session, .failed))
      }

    case .didSendChanges:
      await reportReady(syncEngine, session: session)

    default: break
    }
  }

  private func handleFetchedRecordZoneChanges(
    _ update: CKSyncEngine.Event.FetchedRecordZoneChanges,
    session: OperationToken, accountIdentifier: String
  ) async {
    for modification in update.modifications {
      let record = modification.record
      if record.recordType == Self.messageRecordType {
        await handleFetchedMessage(
          record, session: session,
          accountIdentifier: accountIdentifier)
        continue
      }
      guard let id = Self.deviceID(from: record.recordID) else { continue }
      if let device = Self.device(from: record) {
        devices[id] = device
        if id == installation?.id {
          ownRecordSystemFields = Self.systemFields(record)
        }
      }
    }
    for deletion in update.deletions {
      seenMessageIDs.remove(deletion.recordID)
      messageExpirations.removeValue(forKey: deletion.recordID)
      guard let id = Self.deviceID(from: deletion.recordID) else { continue }
      devices.removeValue(forKey: id)
      if id == installation?.id { ownRecordSystemFields = nil }
    }
    await publishDevices(session: session, accountIdentifier: accountIdentifier)
  }

  private func handleSentRecordZoneChanges(
    _ update: CKSyncEngine.Event.SentRecordZoneChanges,
    syncEngine: CKSyncEngine, session: OperationToken
  ) async {
    await handleSentMessages(update, session: session)
    for (id, error) in update.failedRecordDeletes
    where id.zoneID == Self.zoneID && error.code == .unknownItem {
      syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
      seenMessageIDs.remove(id)
      messageExpirations.removeValue(forKey: id)
      if Self.deviceID(from: id) == installation?.id {
        ownRecordSystemFields = nil
        sendFailed = false
      }
    }
    if let saved = update.savedRecords.first(where: {
      Self.deviceID(from: $0.recordID) == installation?.id
    }) {
      ownRecordSystemFields = Self.systemFields(saved)
      sendFailed = false
    }
    if update.deletedRecordIDs.contains(where: {
      Self.deviceID(from: $0) == installation?.id
    }) {
      ownRecordSystemFields = nil
      sendFailed = false
    }
    if let conflict = update.failedRecordSaves.first(where: {
      Self.deviceID(from: $0.record.recordID) == installation?.id
        && $0.error.code == .serverRecordChanged
    }), let server = conflict.error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
      ownRecordSystemFields = Self.systemFields(server)
      queueOwnRecord(in: syncEngine)
    } else if update.failedRecordSaves.contains(where: {
      Self.deviceID(from: $0.record.recordID) == installation?.id
    })
      || update.failedRecordDeletes.contains(where: {
        Self.deviceID(from: $0.key) == installation?.id && $0.value.code != .unknownItem
      })
    {
      sendFailed = true
      await sendEvent(.remoteDirectoryStatusChanged(session, .failed))
    }
  }

  private func handleSentMessages(
    _ update: CKSyncEngine.Event.SentRecordZoneChanges,
    session: OperationToken
  ) async {
    for saved in update.savedRecords {
      if let outgoing = outgoingMessages.removeValue(forKey: saved.recordID) {
        messageExpirations[saved.recordID] = outgoing.message.header.expiresAt
        scheduleMessageExpiry(session: session)
        guard let command = outgoing.command else { continue }
        switch outgoing.message.header.kind {
        case .pairingRequest:
          await sendEvent(
            .remotePairingCloudSaved(
              command, outgoing.message.header.requestID))
        case .command:
          await sendEvent(
            .remoteCommandCloudSaved(
              command, outgoing.message.header.requestID))
        case .pairingResult, .result: break
        }
      }
    }
    for failure in update.failedRecordSaves {
      guard let outgoing = outgoingMessages[failure.record.recordID] else { continue }
      let status = Self.status(for: failure.error)
      await sendEvent(.remoteDirectoryStatusChanged(session, status))
      if status == .failed {
        outgoingMessages.removeValue(forKey: failure.record.recordID)
        if let command = outgoing.command {
          switch outgoing.message.header.kind {
          case .pairingRequest:
            await sendEvent(
              .remotePairingCloudFailed(
                command, outgoing.message.header.requestID))
          case .command:
            await sendEvent(
              .remoteCommandCloudFailed(
                command, outgoing.message.header.requestID))
          case .pairingResult, .result: break
          }
        }
      }
    }
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    guard engine === syncEngine, !awaitingInitialFetch,
      let installation, let accountIdentifier, let identity
    else { return nil }
    let pending = syncEngine.state.pendingRecordZoneChanges.filter { change in
      guard context.options.scope.contains(change) else { return false }
      switch change {
      case .saveRecord(let id), .deleteRecord(let id): return id.zoneID == Self.zoneID
      @unknown default: return false
      }
    }
    let recordID = Self.recordID(installation.id)
    let enabled = installation.enabledAccountIdentifier == accountIdentifier
    let fields = ownRecordSystemFields
    let name = displayName.isEmpty ? "Plinth" : displayName
    let platform = platform.rawValue
    let signingPublicKey = identity.signingPublicKey
    let agreementPublicKey = identity.agreementPublicKey
    let updated = Date()
    let messages = outgoingMessages
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
      if let message = messages[id] { return Self.messageRecord(id: id, pending: message) }
      guard id == recordID, enabled else { return nil }
      let record =
        fields.flatMap(Self.record(from:))
        ?? CKRecord(recordType: Self.recordType, recordID: id)
      record["name"] = name
      record["platform"] = platform
      record["updatedAt"] = updated
      record["signingPublicKey"] = signingPublicKey
      record["agreementPublicKey"] = agreementPublicKey
      return record
    }
  }

  private func queueOwnRecord(in engine: CKSyncEngine) {
    guard let change = ownRecordChange() else { return }
    engine.state.add(pendingRecordZoneChanges: [change])
  }

  func recoveredOwnRecordChangeIfNeeded() -> CKSyncEngine.PendingRecordZoneChange? {
    guard needsOwnRecordAfterZoneRecovery else { return nil }
    needsOwnRecordAfterZoneRecovery = false
    return ownRecordChange()
  }

  private func ownRecordChange() -> CKSyncEngine.PendingRecordZoneChange? {
    guard let installation, let accountIdentifier else { return nil }
    if installation.enabledAccountIdentifier != accountIdentifier,
      ownRecordSystemFields == nil
    {
      return nil
    }
    let id = Self.recordID(installation.id)
    return installation.enabledAccountIdentifier == accountIdentifier
      ? .saveRecord(id) : .deleteRecord(id)
  }

  func publishDevices(session: OperationToken, accountIdentifier: String) async {
    guard !awaitingInitialFetch else { return }
    await sendEvent(
      .remoteDirectoryChanged(
        session, accountIdentifier, Array(devices.values)))
  }

  private func reportReady(_ engine: CKSyncEngine, session: OperationToken) async {
    guard !awaitingInitialFetch, !fetchFailed, !sendFailed,
      !engine.state.pendingRecordZoneChanges.contains(where: { change in
        switch change {
        case .saveRecord(let id), .deleteRecord(let id): id.zoneID == Self.zoneID
        @unknown default: false
        }
      }),
      !engine.state.pendingDatabaseChanges.contains(where: { change in
        switch change {
        case .saveZone(let zone): zone.zoneID == Self.zoneID
        case .deleteZone(let id): id == Self.zoneID
        @unknown default: false
        }
      })
    else { return }
    await sendEvent(.remoteDirectoryStatusChanged(session, .ready))
  }

  private nonisolated static func deviceID(from id: CKRecord.ID) -> UUID? {
    guard id.zoneID == zoneID else { return nil }
    return UUID(uuidString: id.recordName)
  }

  private nonisolated static func device(from record: CKRecord) -> RemoteDevice? {
    guard record.recordType == recordType,
      let id = deviceID(from: record.recordID),
      let name = record["name"] as? String, !name.isEmpty, name.utf8.count <= 320,
      let rawPlatform = record["platform"] as? String,
      let platform = RemoteDevicePlatform(rawValue: rawPlatform),
      let updatedAt = record["updatedAt"] as? Date
    else { return nil }
    let signingPublicKey = record["signingPublicKey"] as? Data
    let agreementPublicKey = record["agreementPublicKey"] as? Data
    return RemoteDevice(
      id: id, name: name, platform: platform, updatedAt: updatedAt,
      signingPublicKey: signingPublicKey?.count == 32 ? signingPublicKey : nil,
      agreementPublicKey: agreementPublicKey?.count == 32 ? agreementPublicKey : nil)
  }

  private nonisolated static func systemFields(_ record: CKRecord) -> Data {
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: coder)
    return coder.encodedData
  }

  private nonisolated static func record(from fields: Data) -> CKRecord? {
    guard let coder = try? NSKeyedUnarchiver(forReadingFrom: fields) else { return nil }
    coder.requiresSecureCoding = true
    return CKRecord(coder: coder)
  }

}
