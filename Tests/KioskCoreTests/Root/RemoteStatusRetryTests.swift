import Foundation
import KioskCore
import Testing

struct RemoteStatusRetryTests {
  @Test func automaticStatusReadRetriesWhenTargetIsStillBusy() throws {
    let targetID = UUID()
    let localID = UUID()
    let grant = RemotePeerGrant(
      id: targetID, name: "Gallery", accountIdentifier: "account-a",
      signingPublicKey: Data(repeating: 1, count: 32),
      agreementPublicKey: Data(repeating: 2, count: 32), approvedAt: .now)
    var state = RootState()
    state.mode = .administration
    state.remote.installation = RemoteInstallation(
      id: localID, approvedTargets: [targetID: grant])
    state.remote.accountIdentifier = "account-a"
    state.remote.sessionOperation = OperationToken(owner: .cloudRemote, operationID: 1)
    state.remote.selectedDeviceID = targetID
    let firstID = UUID()
    state.remote.outgoingCommand = RemoteOutgoingCommand(
      requestID: firstID, targetID: targetID,
      accountIdentifier: "account-a", deadline: 220,
      automaticStatusRefresh: true, phase: .waiting)
    state.remote.outgoingCommandDeadlineOperation = OperationToken(
      owner: .idleClock, operationID: 2)
    let busy = RemoteCommandResult(
      header: RemoteMessageHeader(
        kind: .result, accountIdentifier: "account-a", senderID: targetID,
        recipientID: localID, requestID: firstID, expiresAt: 220),
      outcome: .rejected(.busy))
    let received = try transition(
      state, .remoteCommandResultReceived(state.remote.sessionOperation!, busy, receivedAt: 100),
      source: .cloudRemote, id: 3, time: 100)
    #expect(received.state.remote.outgoingCommand?.phase == .waiting)
    let retryTimer = try #require(received.state.remote.outgoingCommandDeadlineOperation)
    #expect(
      received.effects.contains(
        Effect(retryTimer, .scheduleRemoteCommandDeadline(115, requestID: firstID))))

    let retried = try transition(
      received.state, .remoteCommandDeadlineReached(retryTimer, firstID),
      source: .idleClock, id: 4, time: 115)
    let secondID = try #require(retried.state.remote.outgoingCommand?.requestID)
    #expect(secondID != firstID)
    #expect(retried.state.remote.outgoingCommand?.automaticStatusRefresh == true)
    #expect(
      retried.effects.contains(where: { effect in
        if case .sendRemoteCommand(_, .readStatus, secondID, "account-a") = effect.kind {
          return true
        }
        return false
      }))
  }

  private func transition(
    _ state: RootState, _ event: Event, source: NodeID, id: UInt64,
    time: Double
  ) throws -> Transition<RootState> {
    let result = RootMediator.reduce(
      state, EventEnvelope(eventID: id, source: source, timestamp: time, event: event))
    guard case .handled(let transition) = result else { throw TestError.notHandled }
    return transition
  }

  private enum TestError: Error { case notHandled }
}
