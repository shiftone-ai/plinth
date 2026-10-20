import Foundation
import KioskCore
import Testing

struct RemotePairingMediatorTests {
  @Test func wrongCodeUsesAnAttemptAndOnlyAnAuthenticatedAdministratorCanApprove() throws {
    let targetID = UUID()
    let controllerID = UUID()
    let session = OperationToken(owner: .cloudRemote, operationID: 50)
    var state = RootState()
    state.mode = .administration
    state.credentialsConfigured = true
    state.administratorSession = true
    state.remote.installation = RemoteInstallation(
      id: targetID, enabledAccountIdentifier: "account-a")
    state.remote.accountIdentifier = "account-a"
    state.remote.sessionOperation = session

    let issued = try transition(state, .remotePairingCodeRequested, source: .settings, id: 1)
    let codeOperation = try #require(issued.state.remote.pairing.codeOperation)
    let generated = try transition(
      issued.state,
      .remotePairingCodeGenerated(codeOperation, "12345678"), source: .cloudRemote, id: 2)
    let payload = RemotePairingRequestPayload(
      code: "12345678", name: "Control iPad",
      signingPublicKey: Data(repeating: 1, count: 32),
      agreementPublicKey: Data(repeating: 2, count: 32))
    let proposal = RemotePairingProposal(
      header: RemoteMessageHeader(
        kind: .pairingRequest,
        accountIdentifier: "account-a", senderID: controllerID,
        recipientID: targetID, requestID: UUID(), expiresAt: 1_200),
      payload: payload)
    let wrong = try transition(
      generated.state,
      .remotePairingRequestReceived(session, proposal, code: "00000000", receivedAt: 1_100),
      source: .cloudRemote, id: 3)
    #expect(wrong.state.remote.pairing.code?.remainingAttempts == 4)
    #expect(wrong.state.remote.pairing.incoming == nil)

    let matching = try transition(
      wrong.state,
      .remotePairingRequestReceived(session, proposal, code: "12345678", receivedAt: 1_100),
      source: .cloudRemote, id: 4)
    #expect(matching.state.remote.pairing.code == nil)
    #expect(matching.state.remote.pairing.incoming == proposal)
    let incomingExpiry = try #require(matching.state.remote.pairing.incomingDeadlineOperation)
    #expect(
      matching.effects == [
        Effect(
          incomingExpiry,
          .scheduleRemotePairingDeadline(104, requestID: proposal.header.requestID))
      ])
    let expired = try transition(
      matching.state,
      .remotePairingDeadlineReached(incomingExpiry, proposal.header.requestID),
      source: .idleClock, id: 6, time: 105)
    #expect(expired.state.remote.pairing.incoming == nil)
    #expect(expired.state.remote.pairing.incomingDeadlineOperation == nil)
    #expect(
      rejected(expired.state, .remotePairingApprovalRequested(true), source: .settings, id: 7))
    #expect(
      try transition(expired.state, .remotePairingCodeRequested, source: .settings, id: 8)
        .state.remote.pairing.codeOperation != nil)

    var locked = matching.state
    locked.administratorSession = false
    #expect(rejected(locked, .remotePairingApprovalRequested(true), source: .settings, id: 5))
    let approved = try transition(
      matching.state,
      .remotePairingApprovalRequested(true), source: .settings, id: 5)
    let approvalOperation = try #require(approved.state.remote.pairing.approvalOperation)
    #expect(
      approved.effects == [
        Effect(
          approvalOperation,
          .respondToRemotePairing(proposal, approved: true))
      ])
  }

  @Test func switchingTargetsRejectsTheOldApprovalResult() throws {
    let localID = UUID()
    let target = RemoteDevice(
      id: UUID(), name: "Gallery iPad", platform: .ipad, updatedAt: .now,
      signingPublicKey: Data(repeating: 3, count: 32),
      agreementPublicKey: Data(repeating: 4, count: 32))
    let second = RemoteDevice(
      id: UUID(), name: "Gallery Mac", platform: .mac, updatedAt: .now,
      signingPublicKey: Data(repeating: 5, count: 32),
      agreementPublicKey: Data(repeating: 6, count: 32))
    var state = RootState()
    state.mode = .administration
    state.remote.installation = RemoteInstallation(id: localID)
    state.remote.accountIdentifier = "account-a"
    state.remote.sessionOperation = OperationToken(owner: .cloudRemote, operationID: 50)
    state.remote.status = .ready
    state.remote.devices = [target, second]
    state.remote.selectedTab = .otherDevices
    state.remote.selectedDeviceID = target.id
    state.remote.pairing.input = "12345678"
    let requestID = UUID()

    let requested = try transition(
      state,
      .remotePairingRequestRequested(requestID), source: .settings, id: 1)
    #expect(requested.state.remote.pairing.outgoing?.target.id == target.id)
    let switched = try transition(
      requested.state,
      .remoteDeviceSelected(second.id), source: .settings, id: 2)
    #expect(switched.state.remote.pairing.outgoing == nil)
    #expect(switched.state.remote.pairing.input.isEmpty)

    let result = RemotePairingResult(
      header: RemoteMessageHeader(
        kind: .pairingResult, accountIdentifier: "account-a", senderID: target.id,
        recipientID: localID, requestID: requestID, expiresAt: 1_200), approved: true)
    let session = try #require(state.remote.sessionOperation)
    #expect(
      rejected(
        switched.state,
        .remotePairingResultReceived(session, result, receivedAt: 1_100),
        source: .cloudRemote, id: 3))
    #expect(switched.state.remote.installation?.approvedTargets.isEmpty == true)
  }

  @Test func revocationBlocksAnOldCommandBeforeAndAfterSaving() throws {
    let controllerID = UUID()
    let exhibitID = UUID()
    let account = "account-a"
    let grant = RemotePeerGrant(
      id: controllerID, name: "Control iPad", accountIdentifier: account,
      signingPublicKey: Data(repeating: 1, count: 32),
      agreementPublicKey: Data(repeating: 2, count: 32), approvedAt: .now)
    var state = RootState()
    state.mode = .administration
    state.administratorSession = true
    state.credentialsConfigured = true
    state.remote.installation = RemoteInstallation(
      id: exhibitID, enabledAccountIdentifier: account,
      approvedControllers: [controllerID: grant])
    state.remote.accountIdentifier = account
    let session = OperationToken(owner: .cloudRemote, operationID: 50)
    state.remote.sessionOperation = session
    let request = RemoteCommandRequest(
      header: RemoteMessageHeader(
        kind: .command, accountIdentifier: account, senderID: controllerID,
        recipientID: exhibitID, requestID: UUID(), expiresAt: 1_200),
      command: .readStatus,
      authenticatedSigningPublicKey: grant.signingPublicKey)

    let revoking = try transition(
      state, .remoteControllerRevokeRequested(controllerID), source: .settings, id: 1)
    #expect(
      rejected(
        revoking.state,
        .remoteCommandReceived(session, request, receivedAt: 1_100),
        source: .cloudRemote, id: 2))
    var installation = try #require(revoking.state.remote.installation)
    installation.approvedControllers.removeValue(forKey: controllerID)
    let operation = try #require(revoking.state.remote.pairing.revocationOperation)
    let revoked = try transition(
      revoking.state, .remoteControllerRevoked(operation, installation),
      source: .cloudRemote, id: 3)
    #expect(
      rejected(
        revoked.state,
        .remoteCommandReceived(session, request, receivedAt: 1_100),
        source: .cloudRemote, id: 4))
    #expect(revoked.state.remote.incomingCommand == nil)
    #expect(revoked.state.saveOperation == nil)
  }

  @Test func revokingDuringClaimCannotRestoreTheGrantOrExecuteTheCommand() throws {
    let controllerID = UUID()
    let targetID = UUID()
    let key = Data(repeating: 8, count: 32)
    let grant = RemotePeerGrant(
      id: controllerID, name: "Controller", accountIdentifier: "account-a",
      signingPublicKey: key, agreementPublicKey: Data(repeating: 9, count: 32),
      approvedAt: .now)
    var state = RootState()
    state.mode = .administration
    state.credentialsConfigured = true
    state.administratorSession = true
    state.remote.installation = RemoteInstallation(
      id: targetID, enabledAccountIdentifier: "account-a",
      approvedControllers: [controllerID: grant])
    state.remote.accountIdentifier = "account-a"
    let session = OperationToken(owner: .cloudRemote, operationID: 50)
    state.remote.sessionOperation = session
    let request = RemoteCommandRequest(
      header: RemoteMessageHeader(
        kind: .command, accountIdentifier: "account-a", senderID: controllerID,
        recipientID: targetID, requestID: UUID(), expiresAt: 1_200),
      command: .readStatus, authenticatedSigningPublicKey: key)

    let received = try transition(
      state, .remoteCommandReceived(session, request, receivedAt: 1_100),
      source: .cloudRemote, id: 1)
    let claim = try #require(received.state.remote.commandClaimOperation)
    let revoking = try transition(
      received.state, .remoteControllerRevokeRequested(controllerID),
      source: .settings, id: 2)
    var oldInstallation = try #require(state.remote.installation)
    oldInstallation.processedRequestExpirations[request.header.requestID] = 1_200
    let late = try transition(
      revoking.state,
      .remoteCommandClaimed(claim, oldInstallation, processedAt: 1_101),
      source: .cloudRemote, id: 3)
    #expect(late.state.remote.incomingCommand == nil)
    #expect(late.state.remote.commandClaimOperation == nil)
    #expect(late.effects.isEmpty)

    let busyRequest = RemoteCommandRequest(
      header: RemoteMessageHeader(
        kind: .command, accountIdentifier: "account-a", senderID: controllerID,
        recipientID: targetID, requestID: UUID(), expiresAt: 1_200),
      command: .readStatus, authenticatedSigningPublicKey: key)
    let busy = try transition(
      received.state, .remoteCommandReceived(session, busyRequest, receivedAt: 1_100),
      source: .cloudRemote, id: 4)
    #expect(
      busy.effects.contains {
        if case .rejectRemoteCommand(let rejectedRequest, .busy) = $0.kind {
          return rejectedRequest == busyRequest
        }
        return false
      })
  }

  @Test func accountChangeDuringRemoteSaveReleasesTheSaveSlot() throws {
    var state = RootState()
    let profile = KioskProfile(
      startURL: "https://example.com", navigation: .init(rules: []))
    let save = OperationToken(owner: .cloudRemote, operationID: 10)
    state.saveOperation = save
    state.pendingProfile = profile
    state.remote.remoteSaveOperation = save
    let completed = try transition(
      state, .profileSaved(save, profile), source: .profileRepository, id: 11)
    #expect(completed.state.remote.remoteSaveOperation == nil)
    #expect(completed.state.savedProfile == profile)
    #expect(completed.effects.isEmpty)
    #expect(completed.childControls.contains(.init(.administration, .remoteProfileSaved(profile))))
  }

  @Test func unknownResultTriggersOneStatusReadAndKeepsTheUncertaintyVisible() throws {
    let targetID = UUID()
    let account = "account-a"
    let grant = RemotePeerGrant(
      id: targetID, name: "Target", accountIdentifier: account,
      signingPublicKey: Data(repeating: 3, count: 32),
      agreementPublicKey: Data(repeating: 4, count: 32), approvedAt: .now)
    var state = RootState()
    state.remote.installation = RemoteInstallation(
      id: UUID(), approvedTargets: [targetID: grant])
    state.remote.accountIdentifier = account
    state.remote.selectedDeviceID = targetID
    state.remote.sessionOperation = OperationToken(owner: .cloudRemote, operationID: 50)
    let expiredID = UUID()
    state.remote.outgoingCommand = RemoteOutgoingCommand(
      requestID: expiredID, targetID: targetID,
      accountIdentifier: account, deadline: 100,
      command: .exhibition(.stop), phase: .waiting)
    let deadline = OperationToken(owner: .idleClock, operationID: 51)
    state.remote.outgoingCommandDeadlineOperation = deadline

    let refresh = try transition(
      state, .remoteCommandDeadlineReached(deadline, expiredID),
      source: .idleClock, id: 52, time: 101)
    #expect(refresh.state.remote.lastUnknownCommand?.phase == .unknown)
    #expect(refresh.state.remote.outgoingCommand?.automaticStatusRefresh == true)
    #expect(
      refresh.effects.contains {
        if case .sendRemoteCommand(_, .readStatus, _, let requestedAccount) = $0.kind {
          return requestedAccount == account
        }
        return false
      })
    let retryID = try #require(refresh.state.remote.outgoingCommand?.requestID)
    let retryDeadline = try #require(refresh.state.remote.outgoingCommandDeadlineOperation)
    let timedOut = try transition(
      refresh.state, .remoteCommandDeadlineReached(retryDeadline, retryID),
      source: .idleClock, id: 53, time: 222)
    #expect(timedOut.state.remote.outgoingCommand?.phase == .unknown)
    #expect(timedOut.state.remote.lastUnknownCommand?.requestID == expiredID)
    #expect(timedOut.effects.isEmpty)
  }

  @Test func failedPageLoadReportsTheWebFailure() throws {
    let request = RemoteCommandRequest(
      header: RemoteMessageHeader(
        kind: .command, accountIdentifier: "account-a", senderID: UUID(),
        recipientID: UUID(), requestID: UUID(), expiresAt: 1_200),
      command: .exhibition(.start),
      authenticatedSigningPublicKey: Data(repeating: 3, count: 32))
    var state = RootState()
    state.mode = .enteringKiosk
    state.remote.incomingCommand = request
    state.remote.pendingExhibitionAction = .start
    let failed = try transition(
      state, .exhibitionUnavailable, source: .exhibition, id: 1)
    #expect(failed.state.mode == .safeHold)
    #expect(
      failed.effects.contains { effect in
        if case .sendRemoteCommandResult(let failedRequest, .rejected(.webLoadFailed)) =
          effect.kind
        {
          return failedRequest == request
        }
        return false
      })
  }

  private func transition(
    _ state: RootState, _ event: Event, source: NodeID, id: UInt64,
    time: Double? = nil
  ) throws -> Transition<RootState> {
    let result = RootMediator.reduce(
      state,
      EventEnvelope(eventID: id, source: source, timestamp: time ?? Double(id), event: event))
    guard case .handled(let value) = result else { throw TestError.notHandled }
    return value
  }

  private func rejected(
    _ state: RootState, _ event: Event, source: NodeID, id: UInt64
  ) -> Bool {
    let result = RootMediator.reduce(
      state,
      EventEnvelope(eventID: id, source: source, timestamp: Double(id), event: event))
    if case .handled(let transition) = result,
      case .rejected = transition.reply
    {
      return true
    }
    return false
  }

  private enum TestError: Error { case notHandled }
}
