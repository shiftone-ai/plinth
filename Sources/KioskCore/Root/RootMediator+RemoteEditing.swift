import Foundation

extension RootMediator {
  static func reduceRemoteEditing(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    let draft = reduceRemoteEditDraft(state, envelope)
    if case .bubble = draft {
      return reduceRemoteEditCommit(state, envelope)
    }
    return draft
  }

  static func reduceRemoteEditDraft(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    switch envelope.event {
    case .remoteEditOpened:
      guard envelope.source == .settings, state.mode == .administration,
        let id = state.remote.selectedDeviceID,
        state.remote.installation?.approvedTargets[id] != nil,
        let snapshot = state.remote.selectedSnapshot, snapshot.savedProfile != nil,
        state.remote.outgoingCommand?.phase == .processed
      else { return .reject(state, .invalidState) }
      next.remote.editing = RemoteEditingState(
        targetID: id,
        baseProfile: snapshot.savedProfile)
      return .handled(.init(next, reply: .accepted))

    case .remoteEditChanged(let value):
      guard envelope.source == .settings, state.mode == .administration,
        state.remote.editing?.targetID == state.remote.selectedDeviceID,
        value.utf8.count <= 4096
      else { return .reject(state, .invalidState) }
      _ = next.remote.editing?.draft.apply(.startURL(value))
      next.remote.editing?.reviewOpen = false
      return .handled(.init(next, reply: .accepted))

    case .remoteEditDraftChanged(let edit):
      guard envelope.source == .settings, state.mode == .administration,
        state.remote.editing?.targetID == state.remote.selectedDeviceID
      else { return .reject(state, .invalidState) }
      switch edit {
      case .navigationMode, .allowsHTTP, .allowsScroll, .allowsDrag, .resetMode:
        break
      case .idleTimeoutText(let value):
        guard value.utf8.count <= 64 else { return .reject(state, .invalidState) }
      case .originAddress(_, let value):
        guard value.utf8.count <= 512 else { return .reject(state, .invalidState) }
      case .macOutputMode:
        guard state.remote.selectedSnapshot?.macDisplays?.isEmpty == false else {
          return .reject(state, .invalidState)
        }
      case .macDisplayID(let id):
        guard let displays = state.remote.selectedSnapshot?.macDisplays,
          id == nil || displays.contains(where: { $0.id == id })
        else { return .reject(state, .invalidState) }
      case .exhibitionDestination(let destination):
        guard let mobile = state.remote.selectedSnapshot?.mobileDisplays,
          destination != .externalDisplay
            || (mobile.supportsExternalDisplay && mobile.externalAvailable)
        else { return .reject(state, .invalidState) }
      case .externalDisplayMode(let mode):
        guard let mobile = state.remote.selectedSnapshot?.mobileDisplays,
          state.remote.editing?.draft.profile.exhibitionDestination == .externalDisplay,
          mode.map({ mobile.displayModes.contains($0) }) ?? true
        else { return .reject(state, .invalidState) }
      case .externalDisplayRotation:
        guard state.remote.selectedSnapshot?.mobileDisplays != nil,
          state.remote.editing?.draft.profile.exhibitionDestination == .externalDisplay
        else { return .reject(state, .invalidState) }
      default: return .reject(state, .invalidState)
      }
      guard next.remote.editing?.draft.apply(edit) == true else {
        return .reject(state, .invalidState)
      }
      next.remote.editing?.reviewOpen = false
      return .handled(.init(next, reply: .accepted))

    case .remoteEditRuleAdded:
      guard envelope.source == .settings, state.mode == .administration,
        var editing = state.remote.editing,
        editing.targetID == state.remote.selectedDeviceID,
        editing.draft.rules.count < 64
      else { return .reject(state, .invalidState) }
      let used = Set(editing.draft.rules.map(\.id))
      guard let id = (1...UInt64.max).first(where: { !used.contains($0) }) else {
        return .reject(state, .invalidState)
      }
      editing.draft.rules.append(.init(id: id, address: ""))
      editing.reviewOpen = false
      next.remote.editing = editing
      return .handled(.init(next, reply: .accepted))

    case .remoteEditRuleRemoved(let id):
      guard envelope.source == .settings, state.mode == .administration,
        state.remote.editing?.targetID == state.remote.selectedDeviceID,
        state.remote.editing?.draft.rules.contains(where: { $0.id == id }) == true
      else { return .reject(state, .invalidState) }
      next.remote.editing?.draft.rules.removeAll { $0.id == id }
      next.remote.editing?.reviewOpen = false
      return .handled(.init(next, reply: .accepted))

    default: return .bubble
    }
  }

  static func reduceRemoteEditCommit(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .cloudRemote, epoch: state.epoch)
    switch envelope.event {
    case .remoteEditReviewRequested:
      guard envelope.source == .settings, state.mode == .administration,
        let editing = state.remote.editing,
        editing.targetID == state.remote.selectedDeviceID,
        editing.baseProfile?.revision == state.remote.selectedSnapshot?.savedProfile?.revision,
        !editing.patch.edits.isEmpty,
        state.remote.outgoingCommand?.phase == .processed
      else { return .reject(state, .invalidState) }
      next.remote.editing?.reviewOpen = true
      return .handled(.init(next, reply: .accepted))

    case .remoteEditCancelled:
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.remote.editing = nil
      return .handled(.init(next, reply: .accepted))

    case .remoteEditSaveRequested(let requestID):
      guard envelope.source == .settings, state.mode == .administration,
        let editing = state.remote.editing, editing.reviewOpen,
        !editing.patch.edits.isEmpty,
        state.remote.selectedDeviceID == editing.targetID,
        editing.baseProfile?.revision == state.remote.selectedSnapshot?.savedProfile?.revision,
        let target = state.remote.devices.first(where: { $0.id == editing.targetID }),
        let grant = state.remote.installation?.approvedTargets[editing.targetID],
        grant.signingPublicKey == target.signingPublicKey,
        grant.agreementPublicKey == target.agreementPublicKey,
        let accountIdentifier = state.remote.accountIdentifier,
        grant.accountIdentifier == accountIdentifier,
        state.remote.sessionOperation != nil,
        ![.sending, .waiting].contains(state.remote.outgoingCommand?.phase ?? .idle)
      else { return .reject(state, .invalidState) }
      let command = RemoteCommandPayload.saveProfile(editing.patch)
      next.remote.outgoingCommand = RemoteOutgoingCommand(
        requestID: requestID, targetID: editing.targetID,
        accountIdentifier: accountIdentifier, deadline: envelope.timestamp + 120,
        command: command)
      next.remote.outgoingCommandOperation = token
      let deadline = envelope.token(owner: .idleClock, epoch: state.epoch)
      next.remote.outgoingCommandDeadlineOperation = deadline
      next.remote.editing?.reviewOpen = false
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
