import CloudKit
import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

@MainActor
private final class RemoteCloudRecordEventRecorder {
  var events: [Event] = []
}

@MainActor
struct RemoteCloudRecordTests {
  @Test func largeSignedStatusWithinACloudKitRecordIsDelivered() async throws {
    let recorder = RemoteCloudRecordEventRecorder()
    let controller = RemoteIdentity.generate()
    let target = RemoteIdentity.generate()
    let controllerID = UUID()
    let targetID = UUID()
    let grant = RemotePeerGrant(
      id: targetID, name: "Gallery", accountIdentifier: "account-a",
      signingPublicKey: target.signingPublicKey,
      agreementPublicKey: target.agreementPublicKey, approvedAt: .now)
    let directory = RemoteDirectoryCloudSync(
      stateURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
      displayName: "Controller", platform: .mac,
      sendEvent: { event in recorder.events.append(event) })
    let session = OperationToken(owner: .cloudRemote, operationID: 1)
    await directory.seedIncomingMessageForTest(
      installation: RemoteInstallation(id: controllerID, approvedTargets: [targetID: grant]),
      identity: controller, session: session)
    let header = RemoteMessageHeader(
      kind: .result, accountIdentifier: "account-a", senderID: targetID,
      recipientID: controllerID, requestID: UUID(),
      expiresAt: Int64(Date().timeIntervalSince1970) + 120)
    let profile = KioskProfile(
      startURL: "https://example.com/" + String(repeating: "a", count: 70_000),
      navigation: .init(mode: .denylist, rules: []))
    let outcome = RemoteCommandOutcome.succeeded(
      .init(reportedAt: 1, mode: .administration, savedProfile: profile, activeRevision: nil))
    let sealed = try RemoteMessageCrypto.seal(
      JSONEncoder().encode(outcome), header: header, sender: target,
      recipientAgreementPublicKey: controller.agreementPublicKey)
    let encoded = try JSONEncoder().encode(sealed)
    #expect(
      encoded.count > 64_000 && encoded.count < RemoteDirectoryCloudSync.maximumMessageDataBytes)
    let record = CKRecord(
      recordType: RemoteDirectoryCloudSync.messageRecordType,
      recordID: CKRecord.ID(
        recordName: "message-\(UUID())", zoneID: RemoteDirectoryCloudSync.zoneID))
    record["kind"] = header.kind.rawValue
    record["senderID"] = header.senderID.uuidString
    record["recipientID"] = header.recipientID.uuidString
    record["requestID"] = header.requestID.uuidString
    record["expiresAt"] = NSNumber(value: header.expiresAt)
    record.encryptedValues["payload"] = encoded
    await directory.handleFetchedMessage(
      record, session: session, accountIdentifier: "account-a")
    await directory.cancelMessageExpiryForTest()
    #expect(
      recorder.events.contains(where: { event in
        if case .remoteCommandResultReceived(_, let result, _) = event {
          return result.outcome == outcome
        }
        return false
      }))
  }

  @Test func recreatedZoneQueuesTheEnabledDevicesPublicRecord() async {
    let installation = RemoteInstallation(
      id: UUID(), enabledAccountIdentifier: "account-a")
    let directory = RemoteDirectoryCloudSync(
      stateURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
      displayName: "Gallery", platform: .ipad, sendEvent: { _ in })
    await directory.seedZoneRecoveryForTest(installation: installation)
    let change = await directory.recoveredOwnRecordChangeIfNeeded()
    guard case .saveRecord(let recordID) = change else {
      Issue.record("The public record was not queued after zone creation")
      return
    }
    #expect(recordID == RemoteDirectoryCloudSync.recordID(installation.id))
    #expect(await directory.recoveredOwnRecordChangeIfNeeded() == nil)
  }
}

extension RemoteDirectoryCloudSync {
  fileprivate func seedIncomingMessageForTest(
    installation: RemoteInstallation, identity: RemoteIdentity, session: OperationToken
  ) {
    self.installation = installation
    self.identity = identity
    self.session = session
    accountIdentifier = "account-a"
  }

  fileprivate func cancelMessageExpiryForTest() {
    messageExpiryTask?.cancel()
    messageExpiryTask = nil
  }

  fileprivate func seedZoneRecoveryForTest(installation: RemoteInstallation) {
    self.installation = installation
    accountIdentifier = "account-a"
    needsOwnRecordAfterZoneRecovery = true
  }
}
