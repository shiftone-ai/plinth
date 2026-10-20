import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct RemoteBackgroundRuntimeTests {
  @Test func backgroundBetweenReceiptAndClaimRejectsExhibition() throws {
    let prepared = try preparedTarget()
    let target = prepared.target
    let request = prepared.request
    target.port.deliver(
      .remoteCommandReceived(prepared.session, request, receivedAt: 1_700_000_001),
      source: .cloudRemote)
    let claim = try #require(target.runtime.snapshot.root.remote.commandClaimOperation)
    target.runtime.send(.applicationDeactivated, from: .platform)
    #expect(!target.runtime.snapshot.root.mobileForeground)

    var claimed = prepared.installation
    claimed.processedRequestExpirations[request.header.requestID] = request.header.expiresAt
    target.port.deliver(
      .remoteCommandClaimed(claim, claimed, processedAt: 1_700_000_002),
      source: .cloudRemote)
    #expect(target.runtime.snapshot.root.mode == .administration)
    #expect(target.runtime.snapshot.root.presentationOperation == nil)
    #expect(
      target.port.effects.contains { effect in
        if case .sendRemoteCommandResult(_, .rejected(.invalidState)) = effect.kind {
          return true
        }
        return false
      })
  }

  private struct PreparedTarget {
    let target: RuntimeFixture
    let installation: RemoteInstallation
    let request: RemoteCommandRequest
    let session: OperationToken
  }

  private func preparedTarget() throws -> PreparedTarget {
    let target = RuntimeFixture()
    target.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1),
      from: .root)
    target.runtime.send(.draftEdited(.startURL("https://example.com/home")), from: .settings)
    target.runtime.send(.saveDraftRequested, from: .settings)
    let save = try #require(target.runtime.snapshot.root.saveOperation)
    let profile = try #require(target.runtime.snapshot.root.pendingProfile)
    target.port.deliver(.profileSaved(save, profile), source: .profileRepository)
    target.runtime.send(.credentialConfigurationRequested("12345678"), from: .administration)
    let credential = try #require(target.runtime.snapshot.root.credentialOperation)
    target.port.deliver(.credentialConfigured(credential, succeeded: true), source: .credentials)
    #expect(target.runtime.snapshot.root.mode == .administration)
    target.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    target.runtime.send(.applicationActivated, from: .platform)
    #expect(target.runtime.snapshot.root.mobileForeground)

    let controllerID = UUID()
    let targetID = UUID()
    let identity = RemoteIdentity.generate()
    let installation = RemoteInstallation(
      id: targetID, enabledAccountIdentifier: "account-a",
      approvedControllers: [
        controllerID: RemotePeerGrant(
          id: controllerID, name: "Control iPad", accountIdentifier: "account-a",
          signingPublicKey: identity.signingPublicKey,
          agreementPublicKey: identity.agreementPublicKey, approvedAt: .now)
      ])
    target.runtime.send(.remoteLoadRequested, from: .root)
    let load = try #require(target.runtime.snapshot.root.remote.loadOperation)
    target.port.deliver(.remoteLoaded(load, installation), source: .cloudRemote)
    let account = try #require(target.runtime.snapshot.root.remote.accountOperation)
    target.port.deliver(
      .remoteAccountChecked(
        account,
        RemoteAccountCheck(
          availability: .available("account-a"), installation: installation)),
      source: .cloudRemote)
    let session = try #require(target.runtime.snapshot.root.remote.sessionOperation)
    let header = RemoteMessageHeader(
      kind: .command, accountIdentifier: "account-a", senderID: controllerID,
      recipientID: targetID, requestID: UUID(), expiresAt: 1_700_000_120)
    let request = RemoteCommandRequest(
      header: header, command: .exhibition(.start),
      authenticatedSigningPublicKey: identity.signingPublicKey)
    return PreparedTarget(
      target: target, installation: installation, request: request, session: session)
  }
}
