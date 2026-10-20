extension RootMediator {
  static func reduceProfile(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .profileCommitRequested(let profile):
      let reason: RejectionReason?
      if envelope.source != .administration {
        reason = .wrongSource
      } else if ![.administration, .exhibiting, .paused, .safeHold].contains(state.mode) {
        reason = .invalidState
      } else if state.saveOperation != nil {
        reason = .alreadySaving
      } else if state.profileCorrupt && !state.administratorSession {
        reason = .unauthenticated
      } else if !profile.validationIssues.isEmpty
        || profile.revision != ProfileRevision.next(after: state.savedProfile?.revision)
        || (context.catalogRequiresAvailableOutput && !state.canPresent(profile))
      {
        reason = .invalidProfile
      } else {
        reason = nil
      }
      if let reason {
        return .handled(
          .init(
            state, reply: .rejected(reason),
            childControls:
              envelope.source == .administration ? [.init(.administration, .draftSaveFailed)] : []))
      }
      next.saveOperation = token
      next.pendingProfile = profile
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(token, state.profileCorrupt ? .recoverProfile(profile) : .saveProfile(profile))
          ]))

    case .profileSaved(let completed, let profile):
      guard envelope.source == .profileRepository else { return .reject(state, .wrongSource) }
      guard state.saveOperation == completed, state.pendingProfile == profile else {
        return .reject(state, .staleOperation)
      }
      if state.savedProfile != profile { next.catalogUpdateCandidateID = nil }
      next.savedProfile = profile
      next.profileCorrupt = false
      if !profile.webAdministrationEnabled { next.webSession = nil }
      next.saveOperation = nil
      next.pendingProfile = nil
      if state.remote.remoteSaveOperation == completed {
        next.remote.remoteSaveOperation = nil
        guard let request = state.remote.incomingCommand else {
          return .handled(
            .init(next, childControls: [.init(.administration, .remoteProfileSaved(profile))]))
        }
        let result = RemoteStatusSnapshot(
          reportedAt: Int64(envelope.timestamp), mode: state.mode,
          savedProfile: profile, activeRevision: state.activeProfile?.revision,
          macDisplays: state.macDisplays, mobileDisplays: state.mobileDisplays)
        let reply = envelope.token(owner: .cloudRemote, epoch: state.epoch)
        next.remote.commandResultOperation = reply
        return .handled(
          .init(
            next,
            effects: [
              Effect(
                reply,
                .sendRemoteCommandResult(request, .succeeded(result)))
            ],
            childControls: [.init(.administration, .remoteProfileSaved(profile))]))
      }
      return .handled(
        .init(next, childControls: [.init(.administration, .draftSaveSucceeded(profile))]))

    case .profileSaveFailed(let completed):
      guard envelope.source == .profileRepository else { return .reject(state, .wrongSource) }
      guard state.saveOperation == completed else { return .reject(state, .staleOperation) }
      next.saveOperation = nil
      next.pendingProfile = nil
      if state.remote.remoteSaveOperation == completed {
        next.remote.remoteSaveOperation = nil
        guard let request = state.remote.incomingCommand else { return .handled(.init(next)) }
        let reply = envelope.token(owner: .cloudRemote, epoch: state.epoch)
        next.remote.commandResultOperation = reply
        return .handled(
          .init(
            next,
            effects: [
              Effect(
                reply,
                .sendRemoteCommandResult(request, .rejected(.storageFailed)))
            ]))
      }
      return .handled(.init(next, childControls: [.init(.administration, .draftSaveFailed)]))

    default: return .bubble
    }
  }
}
