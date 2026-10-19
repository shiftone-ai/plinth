import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct RemoteStatusRuntimeTests {
  @Test func remoteStartURLSaveWaitsForTargetPersistenceAndKeepsActivePage() throws {
    let controller = RuntimeFixture()
    let target = RuntimeFixture()
    let controllerID = UUID()
    let targetID = UUID()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let controllerIdentity = RemoteIdentity.generate()
    let targetIdentity = RemoteIdentity.generate()
    let targetDevice = RemoteDevice(
      id: targetID, name: "Gallery Mac", platform: .mac,
      updatedAt: date, signingPublicKey: targetIdentity.signingPublicKey,
      agreementPublicKey: targetIdentity.agreementPublicKey)
    let controllerDevice = RemoteDevice(
      id: controllerID, name: "Control iPad",
      platform: .ipad, updatedAt: date,
      signingPublicKey: controllerIdentity.signingPublicKey,
      agreementPublicKey: controllerIdentity.agreementPublicKey)
    let targetGrant = RemotePeerGrant(
      id: targetID, name: targetDevice.name,
      accountIdentifier: "account-a", signingPublicKey: targetIdentity.signingPublicKey,
      agreementPublicKey: targetIdentity.agreementPublicKey, approvedAt: date)
    let controllerGrant = RemotePeerGrant(
      id: controllerID, name: controllerDevice.name,
      accountIdentifier: "account-a", signingPublicKey: controllerIdentity.signingPublicKey,
      agreementPublicKey: controllerIdentity.agreementPublicKey, approvedAt: date)
    controller.runtime.send(
      .bootstrapped(
        profile: nil, credentialsConfigured: false,
        displayCount: 1), from: .root)
    try target.startExhibiting()
    let original = try #require(target.runtime.snapshot.root.savedProfile)
    let active = target.runtime.snapshot.root.activeProfile
    let controllerSession = try connect(
      controller,
      installation: RemoteInstallation(
        id: controllerID,
        approvedTargets: [targetID: targetGrant]), devices: [targetDevice])
    let targetInstallation = RemoteInstallation(
      id: targetID,
      enabledAccountIdentifier: "account-a",
      approvedControllers: [controllerID: controllerGrant])
    let targetSession = try connect(
      target, installation: targetInstallation,
      devices: [controllerDevice])
    controller.runtime.send(.remoteTabSelected(.otherDevices), from: .settings)
    controller.runtime.send(.remoteDeviceSelected(targetID), from: .settings)
    let statusID = UUID()
    controller.runtime.send(.remoteStatusRequested(statusID), from: .settings)
    let statusHeader = RemoteMessageHeader(
      kind: .result,
      accountIdentifier: "account-a", senderID: targetID,
      recipientID: controllerID, requestID: statusID, expiresAt: 1_700_000_120)
    controller.port.deliver(
      .remoteCommandResultReceived(
        controllerSession,
        RemoteCommandResult(
          header: statusHeader,
          outcome: .succeeded(
            RemoteStatusSnapshot(
              reportedAt: 1_700_000_001,
              mode: .exhibiting, savedProfile: original, activeRevision: active?.revision))),
        receivedAt: 1_700_000_002), source: .cloudRemote)
    #expect(controller.runtime.send(.remoteEditOpened, from: .settings).reply == .accepted)
    controller.runtime.send(.remoteEditChanged("https://example.com/next"), from: .settings)
    #expect(
      controller.runtime.send(
        .remoteEditReviewRequested,
        from: .settings
      ).reply == .accepted)
    let saveID = UUID()
    #expect(
      controller.runtime.send(
        .remoteEditSaveRequested(saveID),
        from: .settings
      ).reply == .accepted)
    let command = try #require(controller.runtime.snapshot.root.remote.outgoingCommand)
    #expect(command.phase == .sending)
    guard case .saveProfile(let patch) = command.command else {
      Issue.record("No remote save command")
      return
    }
    #expect(patch.baseRevision == original.revision)
    #expect(controller.runtime.snapshot.root.remote.selectedSnapshot?.savedProfile == original)

    let header = RemoteMessageHeader(
      kind: .command, accountIdentifier: "account-a",
      senderID: controllerID, recipientID: targetID, requestID: saveID,
      expiresAt: 1_700_000_120)
    target.port.deliver(
      .remoteCommandReceived(
        targetSession,
        RemoteCommandRequest(header: header, command: command.command),
        receivedAt: 1_700_000_003), source: .cloudRemote)
    let claim = try #require(target.runtime.snapshot.root.remote.commandClaimOperation)
    var claimed = targetInstallation
    claimed.processedRequestExpirations[saveID] = header.expiresAt
    target.port.deliver(
      .remoteCommandClaimed(
        claim, claimed,
        processedAt: 1_700_000_004), source: .cloudRemote)
    let pending = try #require(target.runtime.snapshot.root.pendingProfile)
    #expect(pending.startURL == "https://example.com/next")
    #expect(target.runtime.snapshot.root.savedProfile == original)
    #expect(target.runtime.snapshot.root.activeProfile == active)
    let saveOperation = try #require(target.runtime.snapshot.root.saveOperation)
    target.port.deliver(.profileSaved(saveOperation, pending), source: .profileRepository)
    #expect(target.runtime.snapshot.root.savedProfile == pending)
    #expect(target.runtime.snapshot.root.activeProfile == active)
    let resultEffect = try #require(
      target.port.effects.last { effect in
        if case .sendRemoteCommandResult = effect.kind { return true }
        return false
      })
    guard case .sendRemoteCommandResult(_, let outcome) = resultEffect.kind,
      case .succeeded(let snapshot) = outcome
    else {
      Issue.record("Target did not confirm persistence")
      return
    }
    #expect(snapshot.savedProfile == pending)
    #expect(snapshot.activeRevision == active?.revision)
    let resultHeader = RemoteMessageHeader(
      kind: .result,
      accountIdentifier: "account-a", senderID: targetID,
      recipientID: controllerID, requestID: saveID, expiresAt: 1_700_000_120)
    controller.port.deliver(
      .remoteCommandResultReceived(
        controllerSession,
        RemoteCommandResult(header: resultHeader, outcome: outcome),
        receivedAt: 1_700_000_005), source: .cloudRemote)
    #expect(controller.runtime.snapshot.root.remote.outgoingCommand?.phase == .processed)
    #expect(controller.runtime.snapshot.root.remote.selectedSnapshot?.savedProfile == pending)
    #expect(controller.runtime.snapshot.root.savedProfile == nil)
    #expect(target.runtime.snapshot.administration.savedProfile == pending)
    let queuedResult = try #require(target.runtime.snapshot.root.remote.commandResultOperation)
    target.port.deliver(.remoteCommandResultQueued(queuedResult), source: .cloudRemote)

    let staleID = UUID()
    let staleHeader = RemoteMessageHeader(
      kind: .command,
      accountIdentifier: "account-a", senderID: controllerID,
      recipientID: targetID, requestID: staleID, expiresAt: 1_700_000_120)
    target.port.deliver(
      .remoteCommandReceived(
        targetSession,
        RemoteCommandRequest(header: staleHeader, command: .saveProfile(patch)),
        receivedAt: 1_700_000_006), source: .cloudRemote)
    let staleClaim = try #require(target.runtime.snapshot.root.remote.commandClaimOperation)
    claimed.processedRequestExpirations[staleID] = staleHeader.expiresAt
    target.port.deliver(
      .remoteCommandClaimed(
        staleClaim, claimed,
        processedAt: 1_700_000_007), source: .cloudRemote)
    let rejectionEffect = try #require(
      target.port.effects.last { effect in
        if case .sendRemoteCommandResult = effect.kind { return true }
        return false
      })
    guard case .sendRemoteCommandResult(_, let rejection) = rejectionEffect.kind else {
      Issue.record("No conflict response")
      return
    }
    #expect(rejection == .rejected(.revisionConflict))
    let staleResultOperation = try #require(
      target.runtime.snapshot.root.remote.commandResultOperation)
    target.port.deliver(
      .remoteCommandResultQueued(staleResultOperation),
      source: .cloudRemote)

    let failedID = UUID()
    let failedHeader = RemoteMessageHeader(
      kind: .command,
      accountIdentifier: "account-a", senderID: controllerID,
      recipientID: targetID, requestID: failedID, expiresAt: 1_700_000_120)
    let nextPatch = RemoteProfilePatch(
      baseRevision: pending.revision,
      edits: [.startURL("https://example.com/later")])
    target.port.deliver(
      .remoteCommandReceived(
        targetSession,
        RemoteCommandRequest(header: failedHeader, command: .saveProfile(nextPatch)),
        receivedAt: 1_700_000_008), source: .cloudRemote)
    let failedClaim = try #require(target.runtime.snapshot.root.remote.commandClaimOperation)
    claimed.processedRequestExpirations[failedID] = failedHeader.expiresAt
    target.port.deliver(
      .remoteCommandClaimed(
        failedClaim, claimed,
        processedAt: 1_700_000_009), source: .cloudRemote)
    let failedSave = try #require(target.runtime.snapshot.root.saveOperation)
    target.port.deliver(.profileSaveFailed(failedSave), source: .profileRepository)
    #expect(target.runtime.snapshot.root.savedProfile == pending)
    let failureEffect = try #require(
      target.port.effects.last { effect in
        if case .sendRemoteCommandResult = effect.kind { return true }
        return false
      })
    guard case .sendRemoteCommandResult(_, let failure) = failureEffect.kind else {
      Issue.record("No storage failure response")
      return
    }
    #expect(failure == .rejected(.storageFailed))
    let failedResultOperation = try #require(
      target.runtime.snapshot.root.remote.commandResultOperation)
    target.port.deliver(
      .remoteCommandResultQueued(failedResultOperation),
      source: .cloudRemote)

    let expiredHeader = RemoteMessageHeader(
      kind: .command,
      accountIdentifier: "account-a", senderID: controllerID,
      recipientID: targetID, requestID: UUID(), expiresAt: 1_700_000_009)
    let previousClaim = target.runtime.snapshot.root.remote.commandClaimOperation
    target.port.deliver(
      .remoteCommandReceived(
        targetSession,
        RemoteCommandRequest(header: expiredHeader, command: .saveProfile(nextPatch)),
        receivedAt: 1_700_000_010), source: .cloudRemote)
    #expect(target.runtime.snapshot.root.remote.commandClaimOperation == previousClaim)
  }

  @Test func twoRuntimesExchangeASignedStatusAndIgnoreReplayAndOldSelection() throws {
    let controller = RuntimeFixture()
    let target = RuntimeFixture()
    let controllerID = UUID()
    let targetID = UUID()
    let controllerIdentity = RemoteIdentity.generate()
    let targetIdentity = RemoteIdentity.generate()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let controllerDevice = RemoteDevice(
      id: controllerID, name: "Control iPad", platform: .ipad, updatedAt: date,
      signingPublicKey: controllerIdentity.signingPublicKey,
      agreementPublicKey: controllerIdentity.agreementPublicKey)
    let targetDevice = RemoteDevice(
      id: targetID, name: "Gallery Mac", platform: .mac, updatedAt: date,
      signingPublicKey: targetIdentity.signingPublicKey,
      agreementPublicKey: targetIdentity.agreementPublicKey)
    let controllerGrant = RemotePeerGrant(
      id: controllerID, name: controllerDevice.name, accountIdentifier: "account-a",
      signingPublicKey: controllerIdentity.signingPublicKey,
      agreementPublicKey: controllerIdentity.agreementPublicKey, approvedAt: date)
    let targetGrant = RemotePeerGrant(
      id: targetID, name: targetDevice.name, accountIdentifier: "account-a",
      signingPublicKey: targetIdentity.signingPublicKey,
      agreementPublicKey: targetIdentity.agreementPublicKey, approvedAt: date)
    let controllerInstallation = RemoteInstallation(
      id: controllerID, approvedTargets: [targetID: targetGrant])
    let targetInstallation = RemoteInstallation(
      id: targetID, enabledAccountIdentifier: "account-a",
      approvedControllers: [controllerID: controllerGrant])

    controller.runtime.send(
      .bootstrapped(
        profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    try target.startExhibiting()
    let controllerSession = try connect(
      controller,
      installation: controllerInstallation, devices: [targetDevice])
    let targetSession = try connect(
      target,
      installation: targetInstallation, devices: [controllerDevice])
    controller.runtime.send(.remoteTabSelected(.otherDevices), from: .settings)
    controller.runtime.send(.remoteDeviceSelected(targetID), from: .settings)

    let requestID = UUID()
    #expect(
      controller.runtime.send(
        .remoteStatusRequested(requestID), from: .settings
      ).reply == .accepted)
    let sendOperation = try #require(
      controller.runtime.snapshot.root.remote
        .outgoingCommandOperation)
    #expect(
      controller.port.effects.contains { effect in
        if case .sendRemoteCommand(let grant, .readStatus, let id, let account) = effect.kind {
          return grant == targetGrant && id == requestID && account == "account-a"
        }
        return false
      })

    let header = RemoteMessageHeader(
      kind: .command, accountIdentifier: "account-a", senderID: controllerID,
      recipientID: targetID, requestID: requestID, expiresAt: 1_700_000_120)
    let sealed = try RemoteMessageCrypto.seal(
      JSONEncoder().encode(RemoteCommandPayload.readStatus), header: header,
      sender: controllerIdentity,
      recipientAgreementPublicKey: targetIdentity.agreementPublicKey)
    let command = try JSONDecoder().decode(
      RemoteCommandPayload.self,
      from: RemoteMessageCrypto.open(
        sealed, recipient: targetIdentity,
        senderSigningPublicKey: controllerIdentity.signingPublicKey))
    controller.port.deliver(
      .remoteCommandCloudSaved(sendOperation, requestID),
      source: .cloudRemote)
    target.port.deliver(
      .remoteCommandReceived(
        targetSession, RemoteCommandRequest(header: header, command: command),
        receivedAt: 1_700_000_001), source: .cloudRemote)
    let claim = try #require(target.runtime.snapshot.root.remote.commandClaimOperation)
    var claimedInstallation = targetInstallation
    claimedInstallation.processedRequestExpirations[requestID] = header.expiresAt
    target.port.deliver(
      .remoteCommandClaimed(
        claim, claimedInstallation, processedAt: 1_700_000_002), source: .cloudRemote)
    let resultOperation = try #require(
      target.runtime.snapshot.root.remote.commandResultOperation)
    let resultEffect = try #require(
      target.port.effects.first { effect in
        if case .sendRemoteCommandResult = effect.kind { return true }
        return false
      })
    guard case .sendRemoteCommandResult(_, let outcome) = resultEffect.kind else {
      Issue.record("Missing status result effect")
      return
    }
    guard case .succeeded(let snapshot) = outcome else {
      Issue.record("Status request was rejected")
      return
    }
    #expect(snapshot.mode == .exhibiting)
    #expect(snapshot.savedProfile == target.runtime.snapshot.root.savedProfile)

    let resultHeader = RemoteMessageHeader(
      kind: .result, accountIdentifier: "account-a", senderID: targetID,
      recipientID: controllerID, requestID: requestID, expiresAt: 1_700_000_120)
    let sealedResult = try RemoteMessageCrypto.seal(
      JSONEncoder().encode(outcome), header: resultHeader, sender: targetIdentity,
      recipientAgreementPublicKey: controllerIdentity.agreementPublicKey)
    let received = try JSONDecoder().decode(
      RemoteCommandOutcome.self,
      from: RemoteMessageCrypto.open(
        sealedResult, recipient: controllerIdentity,
        senderSigningPublicKey: targetIdentity.signingPublicKey))
    target.port.deliver(.remoteCommandResultQueued(resultOperation), source: .cloudRemote)
    controller.port.deliver(
      .remoteCommandResultReceived(
        controllerSession, RemoteCommandResult(header: resultHeader, outcome: received),
        receivedAt: 1_700_000_003), source: .cloudRemote)
    #expect(controller.runtime.snapshot.root.remote.selectedSnapshot == snapshot)
    #expect(controller.runtime.snapshot.root.savedProfile == nil)
    #expect(target.runtime.snapshot.root.savedProfile == snapshot.savedProfile)

    let previousEffects = target.port.effects.count
    target.port.deliver(
      .remoteCommandReceived(
        targetSession, RemoteCommandRequest(header: header, command: command),
        receivedAt: 1_700_000_004), source: .cloudRemote)
    #expect(target.port.effects.count == previousEffects)

    controller.runtime.send(.remoteDeviceSelected(nil), from: .settings)
    controller.port.deliver(
      .remoteCommandResultReceived(
        controllerSession, RemoteCommandResult(header: resultHeader, outcome: received),
        receivedAt: 1_700_000_005), source: .cloudRemote)
    #expect(controller.runtime.snapshot.root.remote.selectedSnapshot == nil)
  }

  private func connect(
    _ fixture: RuntimeFixture, installation: RemoteInstallation, devices: [RemoteDevice]
  ) throws -> OperationToken {
    fixture.runtime.send(.remoteLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.remote.loadOperation)
    fixture.port.deliver(.remoteLoaded(load, installation), source: .cloudRemote)
    let check = try #require(fixture.runtime.snapshot.root.remote.accountOperation)
    fixture.port.deliver(
      .remoteAccountChecked(
        check,
        RemoteAccountCheck(
          availability: .available("account-a"),
          installation: installation)), source: .cloudRemote)
    let session = try #require(fixture.runtime.snapshot.root.remote.sessionOperation)
    fixture.port.deliver(
      .remoteDirectoryChanged(session, "account-a", devices),
      source: .cloudRemote)
    fixture.port.deliver(
      .remoteDirectoryStatusChanged(session, .ready),
      source: .cloudRemote)
    return session
  }
}
