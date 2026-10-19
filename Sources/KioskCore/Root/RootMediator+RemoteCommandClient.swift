import Foundation

extension RootMediator {
  static func reduceRemoteCommandClient(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    let editing = reduceRemoteEditing(state, envelope)
    if case .bubble = editing {} else { return editing }
    let exhibition = reduceRemoteExhibitionClient(state, envelope)
    if case .bubble = exhibition {} else { return exhibition }
    let status = reduceRemoteStatusRequest(state, envelope)
    if case .bubble = status {} else { return status }
    return reduceRemoteCommandTransport(state, envelope)
  }

  static func reduceRemoteStatusRequest(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .cloudRemote, epoch: state.epoch)
    switch envelope.event {
    case .remoteStatusRequested(let requestID):
      guard [.settings, .platform].contains(envelope.source),
        state.mode == .administration,
        state.remote.selectedTab == .otherDevices,
        let id = state.remote.selectedDeviceID,
        let target = state.remote.devices.first(where: { $0.id == id }),
        let grant = state.remote.installation?.approvedTargets[id],
        grant.signingPublicKey == target.signingPublicKey,
        grant.agreementPublicKey == target.agreementPublicKey,
        let accountIdentifier = state.remote.accountIdentifier,
        grant.accountIdentifier == accountIdentifier,
        state.remote.sessionOperation != nil,
        ![.sending, .waiting].contains(state.remote.outgoingCommand?.phase ?? .idle)
      else { return .reject(state, .invalidState) }
      next.remote.outgoingCommand = RemoteOutgoingCommand(
        requestID: requestID, targetID: id,
        accountIdentifier: accountIdentifier, deadline: envelope.timestamp + 120)
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
                target: grant, command: .readStatus, requestID: requestID,
                accountIdentifier: accountIdentifier)),
            Effect(
              deadline,
              .scheduleRemoteCommandDeadline(
                envelope.timestamp + 120, requestID: requestID)),
          ]))

    default: return .bubble
    }
  }

  static func reduceRemoteCommandTransport(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    switch envelope.event {
    case .remoteCommandCloudSaved(let completed, let requestID):
      guard envelope.source == .cloudRemote,
        state.remote.outgoingCommandOperation == completed,
        state.remote.outgoingCommand?.requestID == requestID,
        state.remote.outgoingCommand?.phase == .sending
      else { return .reject(state, .staleOperation) }
      next.remote.outgoingCommand?.phase = .waiting
      return .handled(.init(next))

    case .remoteCommandCloudFailed(let completed, let requestID):
      guard envelope.source == .cloudRemote,
        state.remote.outgoingCommandOperation == completed,
        state.remote.outgoingCommand?.requestID == requestID,
        state.remote.outgoingCommand?.phase == .sending
      else { return .reject(state, .staleOperation) }
      next.remote.outgoingCommand?.phase = .failed
      next.remote.outgoingCommandDeadlineOperation = nil
      return .handled(.init(next))

    case .remoteCommandResultReceived(let session, let result, let receivedAt):
      guard envelope.source == .cloudRemote,
        state.remote.sessionOperation == session,
        let outgoing = state.remote.outgoingCommand,
        state.remote.selectedDeviceID == outgoing.targetID,
        state.remote.accountIdentifier == outgoing.accountIdentifier,
        result.header.kind == .result,
        result.header.accountIdentifier == outgoing.accountIdentifier,
        result.header.senderID == outgoing.targetID,
        result.header.recipientID == state.remote.installation?.id,
        result.header.requestID == outgoing.requestID,
        receivedAt < result.header.expiresAt,
        envelope.timestamp < outgoing.deadline,
        [.sending, .waiting].contains(outgoing.phase)
      else { return .reject(state, .staleOperation) }
      next.remote.outgoingCommand?.outcome = result.outcome
      next.remote.outgoingCommandDeadlineOperation = nil
      switch result.outcome {
      case .succeeded(let snapshot):
        next.remote.selectedSnapshot = snapshot
        next.remote.outgoingCommand?.phase = .processed
        if case .saveProfile = outgoing.command {
          next.remote.editing = nil
        } else if state.remote.editing?.baseProfile?.revision
          != snapshot.savedProfile?.revision
        {
          next.remote.editing = nil
        }
      case .rejected:
        next.remote.outgoingCommand?.phase = .rejected
      }
      return .handled(.init(next))

    case .remoteCommandDeadlineReached(let completed, let requestID):
      guard envelope.source == .idleClock,
        state.remote.outgoingCommandDeadlineOperation == completed,
        let outgoing = state.remote.outgoingCommand,
        outgoing.requestID == requestID,
        [.sending, .waiting].contains(outgoing.phase)
      else { return .reject(state, .staleOperation) }
      if envelope.timestamp < outgoing.deadline {
        let retry = envelope.token(owner: .idleClock, epoch: state.epoch)
        next.remote.outgoingCommandDeadlineOperation = retry
        return .handled(
          .init(
            next,
            effects: [
              Effect(
                retry,
                .scheduleRemoteCommandDeadline(outgoing.deadline, requestID: requestID))
            ]))
      }
      next.remote.outgoingCommand?.phase = .unknown
      next.remote.outgoingCommandDeadlineOperation = nil
      return .handled(.init(next))

    default: return .bubble
    }
  }
}
