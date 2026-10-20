import Foundation

extension RootMediator {
  static func reduceRemoteCommandTarget(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .cloudRemote, epoch: state.epoch)
    switch envelope.event {
    case .remoteCommandReceived(let session, let request, let receivedAt):
      guard envelope.source == .cloudRemote,
        state.remote.sessionOperation == session,
        state.remote.enabled,
        request.header.kind == .command,
        request.header.accountIdentifier == state.remote.accountIdentifier,
        request.header.recipientID == state.remote.installation?.id,
        receivedAt < request.header.expiresAt,
        state.remote.installation?.approvedControllers[request.header.senderID]
          .map({
            $0.accountIdentifier == state.remote.accountIdentifier
              && $0.signingPublicKey == request.authenticatedSigningPublicKey
          }) == true,
        state.remote.pairing.revokingControllerID != request.header.senderID,
        state.remote.installation?.processedRequestExpirations[
          request.header.requestID] == nil
      else { return .reject(state, .invalidState) }
      if state.remote.incomingCommand != nil || state.remote.preferenceOperation != nil
        || state.remote.remoteSaveOperation != nil
      {
        return .handled(
          .init(
            state,
            effects: [
              Effect(token, .rejectRemoteCommand(request, .busy))
            ]))
      }
      if state.mobileDisplays != nil && !state.mobileForeground {
        return .handled(
          .init(
            state,
            effects: [
              Effect(token, .rejectRemoteCommand(request, .invalidState))
            ]))
      }
      next.remote.incomingCommand = request
      next.remote.commandClaimOperation = token
      return .handled(.init(next, effects: [Effect(token, .claimRemoteCommand(request))]))

    case .remoteCommandClaimed(let completed, let installation, let processedAt):
      guard envelope.source == .cloudRemote,
        state.remote.commandClaimOperation == completed,
        let request = state.remote.incomingCommand,
        state.remote.installation?.id == installation.id,
        installation.processedRequestExpirations[request.header.requestID]
          == request.header.expiresAt
      else { return .reject(state, .staleOperation) }
      guard state.remote.enabled,
        state.remote.preferenceOperation == nil,
        state.remote.pairing.revokingControllerID != request.header.senderID,
        state.remote.installation?.approvedControllers[request.header.senderID]
          == installation.approvedControllers[request.header.senderID],
        installation.approvedControllers[request.header.senderID]?.signingPublicKey
          == request.authenticatedSigningPublicKey
      else {
        next.remote.incomingCommand = nil
        next.remote.commandClaimOperation = nil
        return .handled(.init(next))
      }
      next.remote.installation?.processedRequestExpirations =
        installation.processedRequestExpirations
      next.remote.commandClaimOperation = nil
      if state.mobileDisplays != nil && !state.mobileForeground {
        next.remote.commandResultOperation = token
        return .handled(
          .init(
            next,
            effects: [
              Effect(token, .sendRemoteCommandResult(request, .rejected(.invalidState)))
            ]))
      }
      switch request.command {
      case .readStatus:
        let snapshot = RemoteStatusSnapshot(
          reportedAt: processedAt, mode: state.mode,
          savedProfile: state.savedProfile,
          activeRevision: state.activeProfile?.revision,
          macDisplays: state.macDisplays, mobileDisplays: state.mobileDisplays)
        next.remote.commandResultOperation = token
        return .handled(
          .init(
            next,
            effects: [
              Effect(
                token,
                .sendRemoteCommandResult(request, .succeeded(snapshot)))
            ]))
      case .saveProfile(let patch):
        let rejection: RemoteCommandRejection?
        if patch.baseRevision != state.savedProfile?.revision {
          rejection = .revisionConflict
        } else if context.hasUnsavedDraft {
          rejection = .draftConflict
        } else if state.saveOperation != nil || state.remote.remoteSaveOperation != nil {
          rejection = .busy
        } else if ![.administration, .exhibiting, .paused, .safeHold].contains(state.mode)
          || state.profileCorrupt
        {
          rejection = .invalidState
        } else if let profile = patch.apply(to: state.savedProfile) {
          if !profile.validationIssues.isEmpty {
            rejection = .invalidProfile
          } else if patch.edits.contains(where: { $0.changesOutput })
            && !state.remoteOutputAvailable(profile)
          {
            rejection = .outputUnavailable
          } else {
            next.pendingProfile = profile
            next.saveOperation = token
            next.remote.remoteSaveOperation = token
            return .handled(
              .init(
                next,
                effects: [
                  Effect(token, .reportRemoteCommandProgress(request, .accepted)),
                  Effect(token, .saveProfile(profile)),
                ]))
          }
        } else {
          rejection = .invalidProfile
        }
        next.remote.commandResultOperation = token
        return .handled(
          .init(
            next,
            effects: [
              Effect(
                token,
                .sendRemoteCommandResult(request, .rejected(rejection ?? .invalidState)))
            ]))
      case .exhibition(let action):
        let operation = EventEnvelope(
          eventID: envelope.eventID,
          source: .cloudRemote, sourceEpoch: envelope.sourceEpoch,
          timestamp: envelope.timestamp, causationID: envelope.causationID,
          event: action.rootEvent)
        let execution = reduce(next, operation, context: context)
        if case .handled(var transition) = execution,
          transition.reply == .accepted
        {
          transition.state.remote.pendingExhibitionAction = action
          let snapshot = RemoteStatusSnapshot(
            reportedAt: Int64(envelope.timestamp), mode: transition.state.mode,
            savedProfile: transition.state.savedProfile,
            activeRevision: transition.state.activeProfile?.revision,
            macDisplays: transition.state.macDisplays,
            mobileDisplays: transition.state.mobileDisplays)
          transition.effects.insert(
            Effect(token, .reportRemoteCommandProgress(request, .accepted)), at: 0)
          transition.effects.insert(
            Effect(
              token,
              .reportRemoteCommandProgress(
                request, .stateChanged(snapshot))), at: 1)
          return .handled(transition)
        }
        let outcome: RemoteCommandOutcome
        if case .handled(let rejection) = execution,
          case .rejected(let reason) = rejection.reply
        {
          outcome = .rejected(Self.remoteRejection(reason))
        } else {
          outcome = .rejected(.invalidState)
        }
        next.remote.commandResultOperation = token
        return .handled(
          .init(
            next,
            effects: [
              Effect(
                token,
                .sendRemoteCommandResult(request, outcome))
            ]))
      }

    case .remoteCommandClaimFailed(let completed):
      guard envelope.source == .cloudRemote,
        state.remote.commandClaimOperation == completed,
        let request = state.remote.incomingCommand
      else { return .reject(state, .staleOperation) }
      next.remote.commandClaimOperation = nil
      next.remote.commandResultOperation = token
      return .handled(
        .init(
          next,
          effects: [
            Effect(
              token,
              .sendRemoteCommandResult(request, .rejected(.storageFailed)))
          ]))

    case .remoteCommandResultQueued(let completed):
      guard envelope.source == .cloudRemote,
        state.remote.commandResultOperation == completed
      else { return .reject(state, .staleOperation) }
      next.remote.incomingCommand = nil
      next.remote.commandResultOperation = nil
      next.remote.pendingExhibitionAction = nil
      return .handled(.init(next))

    case .remoteCommandResultFailed(let completed):
      guard envelope.source == .cloudRemote,
        state.remote.commandResultOperation == completed
      else { return .reject(state, .staleOperation) }
      next.remote.incomingCommand = nil
      next.remote.commandResultOperation = nil
      next.remote.pendingExhibitionAction = nil
      next.remote.status = .offline
      return .handled(.init(next))

    default: return .bubble
    }
  }

  static func finishRemoteExhibition(
    _ result: Mediation<RootState>, envelope: EventEnvelope
  ) -> Mediation<RootState> {
    guard case .handled(var transition) = result,
      let action = transition.state.remote.pendingExhibitionAction,
      let request = transition.state.remote.incomingCommand
    else { return result }
    let succeeded =
      action == .stop
      ? transition.state.mode == .paused
      : transition.state.mode == .exhibiting
    let failed = transition.state.mode == .safeHold
    guard succeeded || failed else { return result }
    let outcome: RemoteCommandOutcome
    if succeeded {
      outcome = .succeeded(
        RemoteStatusSnapshot(
          reportedAt: Int64(envelope.timestamp), mode: transition.state.mode,
          savedProfile: transition.state.savedProfile,
          activeRevision: transition.state.activeProfile?.revision,
          macDisplays: transition.state.macDisplays,
          mobileDisplays: transition.state.mobileDisplays))
    } else {
      if case .exhibitionUnavailable = envelope.event {
        outcome = .rejected(.webLoadFailed)
      } else {
        outcome = .rejected(.outputUnavailable)
      }
    }
    let reply = envelope.token(owner: .cloudRemote, epoch: transition.state.epoch)
    transition.state.remote.pendingExhibitionAction = nil
    transition.state.remote.commandResultOperation = reply
    transition.effects.append(Effect(reply, .sendRemoteCommandResult(request, outcome)))
    return .handled(transition)
  }

  private static func remoteRejection(_ reason: RejectionReason) -> RemoteCommandRejection {
    switch reason {
    case .unsavedDraft, .alreadySaving: .draftConflict
    case .invalidProfile, .invalidURL, .httpDisabled, .urlBlocked: .invalidProfile
    case .unsupportedDisplays, .unsupportedWindow: .outputUnavailable
    case .unauthenticated: .notAuthorized
    default: .invalidState
    }
  }
}
