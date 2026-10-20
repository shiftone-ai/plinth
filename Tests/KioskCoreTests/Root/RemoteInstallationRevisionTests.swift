import Foundation
import KioskCore
import Testing

struct RemoteInstallationRevisionTests {
  @Test func delayedPreferenceCompletionCannotRestoreARevokedController() throws {
    let controllerID = UUID()
    let grant = RemotePeerGrant(
      id: controllerID, name: "Controller", accountIdentifier: "account-a",
      signingPublicKey: Data(repeating: 1, count: 32),
      agreementPublicKey: Data(repeating: 2, count: 32), approvedAt: .now)
    var initial = RemoteInstallation(
      id: UUID(), enabledAccountIdentifier: "account-a",
      approvedControllers: [controllerID: grant])
    var state = RootState()
    state.mode = .administration
    state.remote.installation = initial
    state.remote.accountIdentifier = "account-a"
    let preference = OperationToken(owner: .cloudRemote, operationID: 1)
    let revocation = OperationToken(owner: .cloudRemote, operationID: 2)
    state.remote.preferenceOperation = preference
    state.remote.pairing.revocationOperation = revocation
    state.remote.pairing.revokingControllerID = controllerID

    initial.mutationRevision = 1
    let olderPreference = initial
    initial.approvedControllers.removeValue(forKey: controllerID)
    initial.mutationRevision = 2
    let revoked = try transition(
      state, .remoteControllerRevoked(revocation, initial), id: 3)
    let late = try transition(
      revoked.state, .remoteConfigurationUpdated(preference, olderPreference), id: 4)
    #expect(late.state.remote.installation?.mutationRevision == 2)
    #expect(late.state.remote.installation?.approvedControllers[controllerID] == nil)
    #expect(late.state.remote.preferenceOperation == nil)
  }

  private func transition(_ state: RootState, _ event: Event, id: UInt64) throws
    -> Transition<RootState>
  {
    let result = RootMediator.reduce(
      state, EventEnvelope(eventID: id, source: .cloudRemote, timestamp: Double(id), event: event))
    guard case .handled(let transition) = result else { throw TestError.notHandled }
    return transition
  }

  private enum TestError: Error { case notHandled }
}
