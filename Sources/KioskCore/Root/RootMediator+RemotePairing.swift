import Foundation

extension RootMediator {
  static func reduceRemotePairing(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .cloudRemote, epoch: state.epoch)
    switch envelope.event {
    case .remotePairingCodeRequested:
      guard envelope.source == .settings, state.mode == .administration,
        state.administratorSession, state.remote.enabled,
        state.remote.pairing.codeOperation == nil
      else { return .reject(state, .unauthenticated) }
      next.remote.pairing.codeOperation = token
      next.remote.pairing.incoming = nil
      next.remote.pairing.incomingDeadline = nil
      next.remote.pairing.incomingDeadlineOperation = nil
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [Effect(token, .generateRemotePairingCode)]))

    case .remotePairingCodeGenerated(let completed, let code):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.codeOperation == completed,
        state.mode == .administration, state.administratorSession, state.remote.enabled,
        code.utf8.count == 8, code.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
      else { return .reject(state, .staleOperation) }
      next.remote.pairing.codeOperation = nil
      next.remote.pairing.code = RemotePairingCode(
        value: code, expiresAt: envelope.timestamp + 300)
      let expiry = envelope.token(owner: .idleClock, epoch: state.epoch)
      next.remote.pairing.codeExpiryOperation = expiry
      return .handled(
        .init(
          next,
          effects: [
            Effect(
              expiry,
              .scheduleRemotePairingCodeExpiry(envelope.timestamp + 300))
          ]))

    case .remotePairingCodeGenerationFailed(let completed):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.codeOperation == completed
      else { return .reject(state, .staleOperation) }
      next.remote.pairing.codeOperation = nil
      next.remote.pairing.code = nil
      next.remote.pairing.codeExpiryOperation = nil
      return .handled(.init(next))

    case .remotePairingCodeExpired(let completed):
      guard envelope.source == .idleClock,
        state.remote.pairing.codeExpiryOperation == completed,
        let code = state.remote.pairing.code
      else { return .reject(state, .staleOperation) }
      if envelope.timestamp < code.expiresAt {
        let retry = envelope.token(owner: .idleClock, epoch: state.epoch)
        next.remote.pairing.codeExpiryOperation = retry
        return .handled(
          .init(
            next,
            effects: [
              Effect(
                retry,
                .scheduleRemotePairingCodeExpiry(code.expiresAt))
            ]))
      }
      next.remote.pairing.code = nil
      next.remote.pairing.codeExpiryOperation = nil
      return .handled(.init(next))

    case .remotePairingCodeEdited(let value):
      guard envelope.source == .settings, state.mode == .administration,
        value.utf8.count <= 8, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
      else { return .reject(state, .invalidProfile) }
      next.remote.pairing.input = value
      return .handled(.init(next, reply: .accepted))

    case .remotePairingRequestRequested(let requestID):
      guard envelope.source == .settings, state.mode == .administration,
        state.remote.selectedTab == .otherDevices,
        let targetID = state.remote.selectedDeviceID,
        let target = state.remote.devices.first(where: { $0.id == targetID }),
        target.signingPublicKey?.count == 32,
        target.agreementPublicKey?.count == 32,
        let accountIdentifier = state.remote.accountIdentifier,
        state.remote.sessionOperation != nil, state.remote.installation != nil,
        state.remote.pairing.input.utf8.count == 8,
        state.remote.pairing.outgoing?.phase != .sending,
        state.remote.pairing.outgoing?.phase != .awaitingApproval,
        state.remote.pairing.outgoing?.phase != .storingApproval
      else { return .reject(state, .invalidState) }
      next.remote.pairing.outgoing = RemoteOutgoingPairing(
        requestID: requestID, target: target,
        accountIdentifier: accountIdentifier, deadline: envelope.timestamp + 120)
      next.remote.pairing.requestOperation = token
      let deadlineToken = envelope.token(owner: .idleClock, epoch: state.epoch)
      next.remote.pairing.outgoingDeadlineOperation = deadlineToken
      let code = state.remote.pairing.input
      next.remote.pairing.input = ""
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(
              token,
              .sendRemotePairingRequest(
                target: target, code: code, requestID: requestID,
                accountIdentifier: accountIdentifier)),
            Effect(
              deadlineToken,
              .scheduleRemotePairingDeadline(
                envelope.timestamp + 120, requestID: requestID)),
          ]))

    case .remotePairingCloudSaved(let completed, let requestID):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.requestOperation == completed,
        state.remote.pairing.outgoing?.requestID == requestID,
        state.remote.pairing.outgoing?.phase == .sending
      else { return .reject(state, .staleOperation) }
      next.remote.pairing.outgoing?.phase = .awaitingApproval
      return .handled(.init(next))

    case .remotePairingCloudFailed(let completed, let requestID):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.requestOperation == completed,
        state.remote.pairing.outgoing?.requestID == requestID,
        state.remote.pairing.outgoing?.phase == .sending
      else { return .reject(state, .staleOperation) }
      next.remote.pairing.outgoing?.phase = .failed
      next.remote.pairing.outgoingDeadlineOperation = nil
      return .handled(.init(next))

    case .remotePairingRequestReceived(
      let session, let proposal, let receivedCode,
      let receivedAt):
      guard envelope.source == .cloudRemote,
        state.remote.sessionOperation == session,
        state.remote.enabled, state.remote.preferenceOperation == nil,
        state.mode == .administration, state.administratorSession,
        state.mobileDisplays == nil || state.mobileForeground,
        proposal.header.kind == .pairingRequest,
        proposal.header.accountIdentifier == state.remote.accountIdentifier,
        proposal.header.recipientID == state.remote.installation?.id,
        proposal.header.senderID != state.remote.installation?.id,
        receivedAt <= proposal.header.expiresAt,
        let code = state.remote.pairing.code,
        envelope.timestamp < code.expiresAt, code.remainingAttempts > 0,
        state.remote.pairing.incoming == nil
      else { return .reject(state, .invalidState) }
      if receivedCode != code.value {
        var reduced = code
        reduced.remainingAttempts -= 1
        next.remote.pairing.code = reduced.remainingAttempts > 0 ? reduced : nil
        if reduced.remainingAttempts == 0 {
          next.remote.pairing.codeExpiryOperation = nil
        }
        return .handled(.init(next))
      }
      next.remote.pairing.code = nil
      next.remote.pairing.codeExpiryOperation = nil
      next.remote.pairing.incoming = proposal
      let incomingDeadline =
        envelope.timestamp
        + Double(proposal.header.expiresAt - receivedAt)
      next.remote.pairing.incomingDeadline = incomingDeadline
      let deadline = envelope.token(owner: .idleClock, epoch: state.epoch)
      next.remote.pairing.incomingDeadlineOperation = deadline
      return .handled(
        .init(
          next,
          effects: [
            Effect(
              deadline,
              .scheduleRemotePairingDeadline(
                incomingDeadline, requestID: proposal.header.requestID))
          ]))

    case .remotePairingApprovalRequested(let approved):
      guard envelope.source == .settings, state.mode == .administration,
        state.administratorSession, state.remote.enabled,
        let proposal = state.remote.pairing.incoming,
        let deadline = state.remote.pairing.incomingDeadline,
        envelope.timestamp < deadline,
        state.remote.pairing.approvalOperation == nil
      else { return .reject(state, .unauthenticated) }
      next.remote.pairing.approvalOperation = token
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(token, .respondToRemotePairing(proposal, approved: approved))
          ]))

    case .remotePairingApprovalStored(let completed, let installation):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.approvalOperation == completed,
        state.remote.installation?.id == installation.id
      else { return .reject(state, .staleOperation) }
      next.remote.acceptInstallation(installation)
      next.remote.pairing.approvalOperation = nil
      next.remote.pairing.incoming = nil
      next.remote.pairing.incomingDeadline = nil
      next.remote.pairing.incomingDeadlineOperation = nil
      return .handled(.init(next))

    case .remotePairingApprovalFailed(let completed):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.approvalOperation == completed
      else { return .reject(state, .staleOperation) }
      next.remote.pairing.approvalOperation = nil
      return .handled(.init(next))

    case .remotePairingResultReceived(let session, let result, let receivedAt):
      guard envelope.source == .cloudRemote,
        state.remote.sessionOperation == session,
        let outgoing = state.remote.pairing.outgoing,
        state.remote.selectedDeviceID == outgoing.target.id,
        state.remote.accountIdentifier == outgoing.accountIdentifier,
        result.header.kind == .pairingResult,
        result.header.accountIdentifier == outgoing.accountIdentifier,
        result.header.senderID == outgoing.target.id,
        result.header.recipientID == state.remote.installation?.id,
        result.header.requestID == outgoing.requestID,
        receivedAt <= result.header.expiresAt,
        envelope.timestamp <= outgoing.deadline,
        [.sending, .awaitingApproval].contains(outgoing.phase)
      else { return .reject(state, .staleOperation) }
      if !result.approved {
        next.remote.pairing.outgoing?.phase = .rejected
        next.remote.pairing.outgoingDeadlineOperation = nil
        return .handled(.init(next))
      }
      guard let signingPublicKey = outgoing.target.signingPublicKey,
        let agreementPublicKey = outgoing.target.agreementPublicKey
      else { return .reject(state, .invalidState) }
      let grant = RemotePeerGrant(
        id: outgoing.target.id, name: outgoing.target.name,
        accountIdentifier: outgoing.accountIdentifier,
        signingPublicKey: signingPublicKey,
        agreementPublicKey: agreementPublicKey,
        approvedAt: Date(timeIntervalSince1970: TimeInterval(receivedAt)))
      next.remote.pairing.outgoing?.phase = .storingApproval
      next.remote.pairing.targetGrantOperation = token
      return .handled(
        .init(
          next,
          effects: [
            Effect(
              token,
              .saveRemoteTargetGrant(grant, requestID: outgoing.requestID))
          ]))

    case .remoteTargetGrantStored(let completed, let installation):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.targetGrantOperation == completed,
        state.remote.installation?.id == installation.id
      else { return .reject(state, .staleOperation) }
      next.remote.acceptInstallation(installation)
      next.remote.pairing.targetGrantOperation = nil
      if let outgoing = next.remote.pairing.outgoing,
        next.remote.selectedDeviceID == outgoing.target.id,
        next.remote.installation?.approvedTargets[outgoing.target.id] != nil
      {
        next.remote.pairing.outgoing?.phase = .approved
        next.remote.pairing.outgoingDeadlineOperation = nil
      }
      return .handled(.init(next))

    case .remoteTargetGrantFailed(let completed):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.targetGrantOperation == completed
      else { return .reject(state, .staleOperation) }
      next.remote.pairing.targetGrantOperation = nil
      next.remote.pairing.outgoing?.phase = .failed
      next.remote.pairing.outgoingDeadlineOperation = nil
      return .handled(.init(next))

    case .remoteControllerRevokeRequested(let id):
      guard envelope.source == .settings, state.mode == .administration,
        state.administratorSession, state.remote.enabled,
        state.remote.installation?.approvedControllers[id] != nil,
        let accountIdentifier = state.remote.accountIdentifier,
        state.remote.pairing.revocationOperation == nil
      else { return .reject(state, .unauthenticated) }
      next.remote.pairing.revokingControllerID = id
      next.remote.pairing.revocationOperation = token
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(token, .revokeRemoteController(id, accountIdentifier: accountIdentifier))
          ]))

    case .remoteControllerRevoked(let completed, let installation):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.revocationOperation == completed,
        state.remote.installation?.id == installation.id
      else { return .reject(state, .staleOperation) }
      next.remote.acceptInstallation(installation)
      next.remote.pairing.revokingControllerID = nil
      next.remote.pairing.revocationOperation = nil
      return .handled(.init(next))

    case .remoteControllerRevokeFailed(let completed):
      guard envelope.source == .cloudRemote,
        state.remote.pairing.revocationOperation == completed
      else { return .reject(state, .staleOperation) }
      next.remote.pairing.revokingControllerID = nil
      next.remote.pairing.revocationOperation = nil
      next.remote.preferenceFailed = true
      return .handled(.init(next))

    case .remotePairingDeadlineReached(let completed, let requestID):
      guard envelope.source == .idleClock else { return .reject(state, .wrongSource) }
      if state.remote.pairing.outgoingDeadlineOperation == completed,
        let outgoing = state.remote.pairing.outgoing,
        outgoing.requestID == requestID,
        [.sending, .awaitingApproval, .storingApproval].contains(outgoing.phase)
      {
        if envelope.timestamp < outgoing.deadline {
          let retry = envelope.token(owner: .idleClock, epoch: state.epoch)
          next.remote.pairing.outgoingDeadlineOperation = retry
          return .handled(
            .init(
              next,
              effects: [
                Effect(
                  retry,
                  .scheduleRemotePairingDeadline(outgoing.deadline, requestID: requestID))
              ]))
        }
        next.remote.pairing.outgoing?.phase = .unknown
        next.remote.pairing.outgoingDeadlineOperation = nil
        return .handled(.init(next))
      }
      guard state.remote.pairing.incomingDeadlineOperation == completed,
        state.remote.pairing.incoming?.header.requestID == requestID,
        let deadline = state.remote.pairing.incomingDeadline
      else { return .reject(state, .staleOperation) }
      if envelope.timestamp < deadline {
        let retry = envelope.token(owner: .idleClock, epoch: state.epoch)
        next.remote.pairing.incomingDeadlineOperation = retry
        return .handled(
          .init(
            next,
            effects: [
              Effect(retry, .scheduleRemotePairingDeadline(deadline, requestID: requestID))
            ]))
      }
      next.remote.pairing.incoming = nil
      next.remote.pairing.incomingDeadline = nil
      next.remote.pairing.incomingDeadlineOperation = nil
      return .handled(.init(next))

    default: return .bubble
    }
  }
}
