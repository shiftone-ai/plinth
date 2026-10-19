import CloudKit
import Foundation
import KioskCore

nonisolated struct RemoteOutgoingCloudMessage: Sendable {
  let message: RemoteSealedMessage
  let payloadData: Data
  let announcedSigningPublicKey: Data?
  let command: OperationToken?
}

extension RemoteDirectoryCloudSync {
  public func sendCommand(
    target: RemotePeerGrant, command: RemoteCommandPayload,
    requestID: UUID, accountIdentifier requestedAccount: String,
    operation: OperationToken
  ) async throws {
    guard let installation, let identity, let engine, let session,
      accountIdentifier == requestedAccount,
      installation.approvedTargets[target.id] == target,
      target.accountIdentifier == requestedAccount,
      case .available(let checkedAccount) = await accountAvailability(),
      checkedAccount == requestedAccount,
      self.session == session, self.engine === engine
    else { throw Failure.accountChanged }
    let header = RemoteMessageHeader(
      kind: .command, accountIdentifier: requestedAccount,
      senderID: installation.id, recipientID: target.id,
      requestID: requestID, expiresAt: Int64(Date().timeIntervalSince1970) + 120)
    let sealed = try RemoteMessageCrypto.seal(
      JSONEncoder().encode(command), header: header, sender: identity,
      recipientAgreementPublicKey: target.agreementPublicKey)
    try queueMessage(
      sealed, announcedSigningPublicKey: nil,
      command: operation, in: engine)
    await sendQueuedChanges(in: engine, session: session)
  }

  public func claimCommand(_ request: RemoteCommandRequest) async throws -> RemoteInstallation {
    guard let current = installation, let accountIdentifier,
      current.enabledAccountIdentifier == accountIdentifier,
      current.approvedControllers[request.header.senderID]?.accountIdentifier
        == accountIdentifier,
      request.header.kind == .command,
      request.header.accountIdentifier == accountIdentifier,
      request.header.recipientID == current.id,
      request.header.expiresAt > Int64(Date().timeIntervalSince1970),
      current.processedRequestExpirations[request.header.requestID] == nil,
      case .available(let checkedAccount) = await accountAvailability(),
      checkedAccount == accountIdentifier
    else { throw Failure.invalidMessage }
    var updated = current
    let cutoff = Int64(Date().timeIntervalSince1970) - 86_400
    updated.processedRequestExpirations = updated.processedRequestExpirations.filter {
      $0.value >= cutoff
    }
    updated.processedRequestExpirations[request.header.requestID] = request.header.expiresAt
    try persist(updated)
    installation = updated
    return updated
  }

  public func sendResult(
    for request: RemoteCommandRequest, outcome: RemoteCommandOutcome
  ) async throws {
    guard let current = installation, let identity, let engine, let session,
      let accountIdentifier,
      current.enabledAccountIdentifier == accountIdentifier,
      let controller = current.approvedControllers[request.header.senderID],
      controller.accountIdentifier == accountIdentifier,
      request.header.accountIdentifier == accountIdentifier,
      request.header.recipientID == current.id,
      self.session == session, self.engine === engine
    else { throw Failure.accountChanged }
    let header = RemoteMessageHeader(
      kind: .result, accountIdentifier: accountIdentifier,
      senderID: current.id, recipientID: controller.id,
      requestID: request.header.requestID,
      expiresAt: request.header.expiresAt)
    let datedOutcome: RemoteCommandOutcome
    switch outcome {
    case .succeeded(let snapshot):
      datedOutcome = .succeeded(
        snapshot.reported(
          at: Int64(Date().timeIntervalSince1970)))
    case .rejected:
      datedOutcome = outcome
    }
    let sealed = try RemoteMessageCrypto.seal(
      JSONEncoder().encode(datedOutcome), header: header, sender: identity,
      recipientAgreementPublicKey: controller.agreementPublicKey)
    try queueMessage(
      sealed, announcedSigningPublicKey: nil,
      command: nil, in: engine)
    await sendQueuedChanges(in: engine, session: session)
  }

  public func sendPairingRequest(
    target: RemoteDevice, code: String, requestID: UUID,
    accountIdentifier requestedAccount: String, command: OperationToken
  ) async throws {
    guard code.utf8.count == 8, code.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
      let targetAgreementKey = target.agreementPublicKey,
      target.signingPublicKey?.count == 32,
      targetAgreementKey.count == 32,
      let installation, let identity, let engine, let session,
      accountIdentifier == requestedAccount,
      devices[target.id]?.signingPublicKey == target.signingPublicKey,
      devices[target.id]?.agreementPublicKey == target.agreementPublicKey,
      case .available(let checkedAccount) = await accountAvailability(),
      checkedAccount == requestedAccount,
      self.session == session, self.engine === engine
    else { throw Failure.accountChanged }
    let header = RemoteMessageHeader(
      kind: .pairingRequest, accountIdentifier: requestedAccount,
      senderID: installation.id, recipientID: target.id,
      requestID: requestID, expiresAt: Int64(Date().timeIntervalSince1970) + 120)
    let payload = RemotePairingRequestPayload(
      code: code, name: displayName, signingPublicKey: identity.signingPublicKey,
      agreementPublicKey: identity.agreementPublicKey)
    let sealed = try RemoteMessageCrypto.seal(
      JSONEncoder().encode(payload), header: header, sender: identity,
      recipientAgreementPublicKey: targetAgreementKey)
    pairingTargets[requestID] = target
    try queueMessage(
      sealed, announcedSigningPublicKey: identity.signingPublicKey,
      command: command, in: engine)
    await sendQueuedChanges(in: engine, session: session)
  }

  public func respondToPairing(
    _ proposal: RemotePairingProposal, approved: Bool
  ) async throws -> RemoteInstallation {
    guard let current = installation, let identity, let engine, let session,
      let accountIdentifier,
      current.enabledAccountIdentifier == accountIdentifier,
      proposal.header.kind == .pairingRequest,
      proposal.header.accountIdentifier == accountIdentifier,
      proposal.header.recipientID == current.id,
      proposal.header.expiresAt > Int64(Date().timeIntervalSince1970),
      proposal.signingPublicKey.count == 32,
      proposal.agreementPublicKey.count == 32,
      case .available(let checkedAccount) = await accountAvailability(),
      checkedAccount == accountIdentifier,
      self.session == session, self.engine === engine
    else { throw Failure.accountChanged }
    let header = RemoteMessageHeader(
      kind: .pairingResult, accountIdentifier: accountIdentifier,
      senderID: current.id, recipientID: proposal.header.senderID,
      requestID: proposal.header.requestID,
      expiresAt: proposal.header.expiresAt)
    let result = try RemoteMessageCrypto.seal(
      JSONEncoder().encode(RemotePairingResultPayload(approved: approved)),
      header: header, sender: identity,
      recipientAgreementPublicKey: proposal.agreementPublicKey)
    var updated = current
    if approved {
      updated.approvedControllers[proposal.header.senderID] = RemotePeerGrant(
        id: proposal.header.senderID, name: proposal.name,
        accountIdentifier: accountIdentifier,
        signingPublicKey: proposal.signingPublicKey,
        agreementPublicKey: proposal.agreementPublicKey, approvedAt: .now)
      try persist(updated)
      installation = updated
    }
    try queueMessage(result, announcedSigningPublicKey: nil, command: nil, in: engine)
    await sendQueuedChanges(in: engine, session: session)
    return updated
  }

  public func saveTargetGrant(
    _ grant: RemotePeerGrant, requestID: UUID
  ) async throws -> RemoteInstallation {
    guard let current = installation, let accountIdentifier,
      let target = pairingTargets[requestID], target.id == grant.id,
      target.signingPublicKey == grant.signingPublicKey,
      target.agreementPublicKey == grant.agreementPublicKey,
      grant.accountIdentifier == accountIdentifier,
      case .available(let checkedAccount) = await accountAvailability(),
      checkedAccount == accountIdentifier
    else { throw Failure.accountChanged }
    var updated = current
    updated.approvedTargets[grant.id] = grant
    try persist(updated)
    installation = updated
    pairingTargets.removeValue(forKey: requestID)
    return updated
  }

  public func revokeController(
    _ id: UUID, accountIdentifier requestedAccount: String
  ) async throws -> RemoteInstallation {
    guard let current = installation, accountIdentifier == requestedAccount,
      current.enabledAccountIdentifier == requestedAccount,
      current.approvedControllers[id]?.accountIdentifier == requestedAccount,
      case .available(let checkedAccount) = await accountAvailability(),
      checkedAccount == requestedAccount
    else { throw Failure.accountChanged }
    var updated = current
    updated.approvedControllers.removeValue(forKey: id)
    try persist(updated)
    installation = updated
    return updated
  }

  func queueMessage(
    _ message: RemoteSealedMessage, announcedSigningPublicKey: Data?,
    command: OperationToken?, in engine: CKSyncEngine
  ) throws {
    let recordID = CKRecord.ID(
      recordName: "message-\(UUID().uuidString)",
      zoneID: Self.zoneID)
    let pending = RemoteOutgoingCloudMessage(
      message: message, payloadData: try JSONEncoder().encode(message),
      announcedSigningPublicKey: announcedSigningPublicKey, command: command)
    outgoingMessages[recordID] = pending
    engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
  }

  func sendQueuedChanges(in engine: CKSyncEngine, session: OperationToken) async {
    do { try await engine.sendChanges() } catch {
      guard self.session == session, self.engine === engine else { return }
      await sendEvent(.remoteDirectoryStatusChanged(session, Self.status(for: error)))
    }
  }

  nonisolated static func messageRecord(
    id: CKRecord.ID, pending: RemoteOutgoingCloudMessage
  ) -> CKRecord {
    let record = CKRecord(recordType: messageRecordType, recordID: id)
    let header = pending.message.header
    record["kind"] = header.kind.rawValue
    record["senderID"] = header.senderID.uuidString
    record["recipientID"] = header.recipientID.uuidString
    record["requestID"] = header.requestID.uuidString
    record["expiresAt"] = NSNumber(value: header.expiresAt)
    if let key = pending.announcedSigningPublicKey {
      record["senderSigningPublicKey"] = key
    }
    record.encryptedValues["payload"] = pending.payloadData
    return record
  }

  func handleFetchedMessage(
    _ record: CKRecord, session: OperationToken, accountIdentifier: String
  ) async {
    if let expiresAt = record["expiresAt"] as? NSNumber,
      expiresAt.int64Value <= Int64(Date().timeIntervalSince1970)
    {
      engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(record.recordID)])
      return
    }
    guard record.recordType == Self.messageRecordType,
      record.recordID.zoneID == Self.zoneID,
      !seenMessageIDs.contains(record.recordID),
      let data = record.encryptedValues["payload"] as? Data,
      data.count <= 64_000,
      let message = try? JSONDecoder().decode(RemoteSealedMessage.self, from: data),
      message.header.version == 1,
      message.header.accountIdentifier == accountIdentifier,
      message.header.recipientID == installation?.id,
      message.header.senderID != installation?.id,
      record["kind"] as? String == message.header.kind.rawValue,
      record["senderID"] as? String == message.header.senderID.uuidString,
      record["recipientID"] as? String == message.header.recipientID.uuidString,
      record["requestID"] as? String == message.header.requestID.uuidString,
      (record["expiresAt"] as? NSNumber)?.int64Value == message.header.expiresAt,
      let identity,
      let current = installation
    else { return }
    seenMessageIDs.insert(record.recordID)
    let now = Int64(Date().timeIntervalSince1970)
    guard message.header.expiresAt > now else { return }
    switch message.header.kind {
    case .pairingRequest:
      guard current.enabledAccountIdentifier == accountIdentifier,
        let senderKey = record["senderSigningPublicKey"] as? Data,
        senderKey.count == 32,
        let plaintext = try? RemoteMessageCrypto.open(
          message, recipient: identity, senderSigningPublicKey: senderKey),
        let payload = try? JSONDecoder().decode(
          RemotePairingRequestPayload.self, from: plaintext),
        payload.signingPublicKey == senderKey,
        payload.agreementPublicKey.count == 32,
        !payload.name.isEmpty, payload.name.utf8.count <= 320,
        payload.code.utf8.count == 8
      else { return }
      await sendEvent(
        .remotePairingRequestReceived(
          session, RemotePairingProposal(header: message.header, payload: payload),
          code: payload.code, receivedAt: now))

    case .pairingResult:
      guard let target = pairingTargets[message.header.requestID],
        target.id == message.header.senderID,
        let signingKey = target.signingPublicKey,
        let plaintext = try? RemoteMessageCrypto.open(
          message, recipient: identity, senderSigningPublicKey: signingKey),
        let payload = try? JSONDecoder().decode(
          RemotePairingResultPayload.self, from: plaintext)
      else { return }
      await sendEvent(
        .remotePairingResultReceived(
          session, RemotePairingResult(header: message.header, approved: payload.approved),
          receivedAt: now))

    case .command:
      guard current.enabledAccountIdentifier == accountIdentifier,
        let controller = current.approvedControllers[message.header.senderID],
        controller.accountIdentifier == accountIdentifier,
        let plaintext = try? RemoteMessageCrypto.open(
          message, recipient: identity,
          senderSigningPublicKey: controller.signingPublicKey),
        let command = try? JSONDecoder().decode(RemoteCommandPayload.self, from: plaintext)
      else { return }
      await sendEvent(
        .remoteCommandReceived(
          session, RemoteCommandRequest(header: message.header, command: command),
          receivedAt: now))

    case .result:
      guard let target = current.approvedTargets[message.header.senderID],
        target.accountIdentifier == accountIdentifier,
        let plaintext = try? RemoteMessageCrypto.open(
          message, recipient: identity,
          senderSigningPublicKey: target.signingPublicKey),
        let outcome = try? JSONDecoder().decode(RemoteCommandOutcome.self, from: plaintext)
      else { return }
      await sendEvent(
        .remoteCommandResultReceived(
          session, RemoteCommandResult(header: message.header, outcome: outcome),
          receivedAt: now))
    }
  }
}
