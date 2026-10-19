import Foundation

extension RootMediator {
  static func reduceRemoteExhibitionClient(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .cloudRemote, epoch: state.epoch)
    switch envelope.event {
    case .remoteExhibitionReviewRequested(let action):
      guard envelope.source == .settings, state.mode == .administration,
        [.restart, .stop].contains(action),
        let id = state.remote.selectedDeviceID,
        state.remote.installation?.approvedTargets[id] != nil,
        state.remote.selectedSnapshot?.mode == .exhibiting,
        ![.sending, .waiting].contains(state.remote.outgoingCommand?.phase ?? .idle)
      else { return .reject(state, .invalidState) }
      next.remote.exhibitionReviewAction = action
      return .handled(.init(next, reply: .accepted))

    case .remoteExhibitionReviewCancelled:
      guard envelope.source == .settings else { return .reject(state, .wrongSource) }
      next.remote.exhibitionReviewAction = nil
      return .handled(.init(next, reply: .accepted))

    case .remoteExhibitionRequested(let requestID, let action):
      guard envelope.source == .settings, state.mode == .administration,
        state.remote.selectedTab == .otherDevices,
        let id = state.remote.selectedDeviceID,
        let target = state.remote.devices.first(where: { $0.id == id }),
        let grant = state.remote.installation?.approvedTargets[id],
        grant.signingPublicKey == target.signingPublicKey,
        grant.agreementPublicKey == target.agreementPublicKey,
        let accountIdentifier = state.remote.accountIdentifier,
        grant.accountIdentifier == accountIdentifier,
        state.remote.sessionOperation != nil,
        ![.sending, .waiting].contains(state.remote.outgoingCommand?.phase ?? .idle),
        state.remote.selectedSnapshot.map({ snapshot in
          switch action {
          case .start: snapshot.mode == .administration
          case .restart, .stop: snapshot.mode == .exhibiting
          case .resume: [.paused, .safeHold].contains(snapshot.mode)
          }
        }) == true,
        ![.restart, .stop].contains(action)
          || state.remote.exhibitionReviewAction == action
      else { return .reject(state, .invalidState) }
      let command = RemoteCommandPayload.exhibition(action)
      next.remote.exhibitionReviewAction = nil
      next.remote.outgoingCommand = RemoteOutgoingCommand(
        requestID: requestID, targetID: id, accountIdentifier: accountIdentifier,
        deadline: envelope.timestamp + 120, command: command)
      next.remote.outgoingCommandOperation = token
      let deadline = envelope.token(owner: .idleClock, epoch: state.epoch)
      next.remote.outgoingCommandDeadlineOperation = deadline
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(
              token,
              .sendRemoteCommand(
                target: grant, command: command,
                requestID: requestID, accountIdentifier: accountIdentifier)),
            Effect(
              deadline,
              .scheduleRemoteCommandDeadline(
                envelope.timestamp + 120, requestID: requestID)),
          ]))

    default: return .bubble
    }
  }
}
