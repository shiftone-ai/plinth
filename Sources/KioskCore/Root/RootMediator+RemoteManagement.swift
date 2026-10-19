import Foundation

extension RootMediator {
  static func reduceRemoteManagement(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .cloudRemote, epoch: state.epoch)
    switch envelope.event {
    case .remoteLoadRequested:
      guard envelope.source == .root, state.remote.loadOperation == nil,
        state.remote.installation == nil
      else { return .reject(state, .invalidState) }
      next.remote.loadOperation = token
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(token, .loadRemoteConfiguration)
          ]))

    case .remoteLoaded(let completed, let installation):
      guard envelope.source == .cloudRemote, state.remote.loadOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.remote.loadOperation = nil
      next.remote.installation = installation
      next.remote.accountOperation = token
      return .handled(.init(next, effects: [Effect(token, .checkRemoteAccount)]))

    case .remoteLoadFailed(let completed):
      guard envelope.source == .cloudRemote, state.remote.loadOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.remote.loadOperation = nil
      next.remote.status = .failed
      return .handled(.init(next))

    case .remoteAccountChecked(let completed, let check):
      guard envelope.source == .cloudRemote, state.remote.accountOperation == completed,
        let installation = state.remote.installation
      else { return .reject(state, .staleOperation) }
      guard installation.id == check.installation.id else {
        return .reject(state, .invalidState)
      }
      next.remote.accountOperation = nil
      next.remote.installation = check.installation
      next.remote.devices = []
      next.remote.selectedDeviceID = nil
      next.remote.pairing = RemotePairingState()
      next.remote.outgoingCommand = nil
      next.remote.lastUnknownCommand = nil
      next.remote.outgoingCommandOperation = nil
      next.remote.outgoingCommandDeadlineOperation = nil
      next.remote.selectedSnapshot = nil
      next.remote.editing = nil
      next.remote.incomingCommand = nil
      next.remote.commandClaimOperation = nil
      next.remote.commandResultOperation = nil
      next.remote.pendingExhibitionAction = nil
      next.remote.exhibitionReviewAction = nil
      switch check.availability {
      case .available(let accountIdentifier):
        next.remote.accountIdentifier = accountIdentifier
        next.remote.status = .checking
        next.remote.sessionOperation = token
        return .handled(
          .init(
            next,
            effects: [
              Effect(
                token,
                .startRemoteDirectory(
                  accountIdentifier: accountIdentifier, installation: check.installation))
            ]))
      case .unavailable:
        next.remote.accountIdentifier = nil
        next.remote.sessionOperation = nil
        next.remote.status = .signInRequired
      case .transient:
        next.remote.accountIdentifier = nil
        next.remote.sessionOperation = nil
        next.remote.status = .offline
      case .unsupported:
        next.remote.accountIdentifier = nil
        next.remote.sessionOperation = nil
        next.remote.status = .cloudUnavailable
      }
      return .handled(.init(next))

    case .remoteAccountCheckFailed(let completed):
      guard envelope.source == .cloudRemote, state.remote.accountOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.remote.accountOperation = nil
      next.remote.accountIdentifier = nil
      next.remote.sessionOperation = nil
      next.remote.devices = []
      next.remote.selectedDeviceID = nil
      next.remote.pairing = RemotePairingState()
      next.remote.outgoingCommand = nil
      next.remote.lastUnknownCommand = nil
      next.remote.outgoingCommandOperation = nil
      next.remote.outgoingCommandDeadlineOperation = nil
      next.remote.selectedSnapshot = nil
      next.remote.editing = nil
      next.remote.incomingCommand = nil
      next.remote.commandClaimOperation = nil
      next.remote.commandResultOperation = nil
      next.remote.pendingExhibitionAction = nil
      next.remote.exhibitionReviewAction = nil
      next.remote.status = .failed
      return .handled(.init(next, effects: [Effect(token, .stopRemoteDirectory)]))

    case .remoteAccountAvailabilityChanged:
      guard [.cloudRemote, .platform].contains(envelope.source),
        state.remote.installation != nil
      else { return .reject(state, .wrongSource) }
      next.remote.accountIdentifier = nil
      next.remote.sessionOperation = nil
      next.remote.devices = []
      next.remote.selectedDeviceID = nil
      next.remote.pairing = RemotePairingState()
      next.remote.outgoingCommand = nil
      next.remote.lastUnknownCommand = nil
      next.remote.outgoingCommandOperation = nil
      next.remote.outgoingCommandDeadlineOperation = nil
      next.remote.selectedSnapshot = nil
      next.remote.editing = nil
      next.remote.incomingCommand = nil
      next.remote.commandClaimOperation = nil
      next.remote.commandResultOperation = nil
      next.remote.pendingExhibitionAction = nil
      next.remote.exhibitionReviewAction = nil
      next.remote.preferenceOperation = nil
      next.remote.status = .checking
      next.remote.accountOperation = token
      return .handled(
        .init(
          next,
          effects: [
            Effect(token, .stopRemoteDirectory), Effect(token, .checkRemoteAccount),
          ]))

    case .remoteDirectoryChanged(let session, let accountIdentifier, let devices):
      guard envelope.source == .cloudRemote, state.remote.sessionOperation == session,
        state.remote.accountIdentifier == accountIdentifier
      else { return .reject(state, .staleOperation) }
      next.remote.devices = devices.filter { $0.id != state.remote.installation?.id }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      if let selected = next.remote.selectedDeviceID,
        !next.remote.devices.contains(where: { $0.id == selected })
      {
        next.remote.selectedDeviceID = nil
        next.remote.pairing.input = ""
        next.remote.pairing.outgoing = nil
        next.remote.pairing.requestOperation = nil
        next.remote.pairing.outgoingDeadlineOperation = nil
        next.remote.outgoingCommand = nil
        next.remote.lastUnknownCommand = nil
        next.remote.outgoingCommandOperation = nil
        next.remote.outgoingCommandDeadlineOperation = nil
        next.remote.selectedSnapshot = nil
        next.remote.editing = nil
        next.remote.exhibitionReviewAction = nil
      }
      return .handled(.init(next))

    case .remoteDirectoryStatusChanged(let session, let status):
      guard envelope.source == .cloudRemote, state.remote.sessionOperation == session else {
        return .reject(state, .staleOperation)
      }
      next.remote.status = status
      return .handled(.init(next))

    case .remoteRefreshRequested:
      guard [.settings, .platform].contains(envelope.source),
        let session = state.remote.sessionOperation
      else { return .reject(state, .invalidState) }
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(session, .refreshRemoteDirectory)
          ]))

    case .remoteEnabledRequested(let enabled):
      guard envelope.source == .settings, state.mode == .administration,
        state.credentialsConfigured, state.administratorSession
      else { return .reject(state, .unauthenticated) }
      guard let accountIdentifier = state.remote.accountIdentifier,
        state.remote.installation != nil, state.remote.preferenceOperation == nil
      else { return .reject(state, .invalidState) }
      next.remote.preferenceOperation = token
      next.remote.preferenceFailed = false
      if !enabled {
        next.remote.pairing.code = nil
        next.remote.pairing.codeExpiryOperation = nil
        next.remote.pairing.incoming = nil
        next.remote.pairing.incomingDeadline = nil
      }
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(token, .setRemoteEnabled(enabled, accountIdentifier: accountIdentifier))
          ]))

    case .remoteVisibilityRequested(let id, let visible):
      guard envelope.source == .settings, state.mode == .administration,
        state.remote.devices.contains(where: { $0.id == id }),
        let accountIdentifier = state.remote.accountIdentifier,
        state.remote.preferenceOperation == nil
      else { return .reject(state, .invalidState) }
      next.remote.preferenceOperation = token
      next.remote.preferenceFailed = false
      return .handled(
        .init(
          next, reply: .accepted,
          effects: [
            Effect(
              token,
              .setRemoteVisibility(
                id, visible: visible,
                accountIdentifier: accountIdentifier))
          ]))

    case .remoteConfigurationUpdated(let completed, let installation):
      guard envelope.source == .cloudRemote, state.remote.preferenceOperation == completed,
        state.remote.installation?.id == installation.id
      else { return .reject(state, .staleOperation) }
      next.remote.preferenceOperation = nil
      next.remote.installation = installation
      next.remote.preferenceFailed = false
      if !next.remote.enabled {
        next.remote.pairing.code = nil
        next.remote.pairing.codeExpiryOperation = nil
        next.remote.pairing.incoming = nil
        next.remote.pairing.incomingDeadline = nil
      }
      if let selected = next.remote.selectedDeviceID,
        installation.hiddenDeviceIDs(for: next.remote.accountIdentifier).contains(selected)
      {
        next.remote.selectedDeviceID = nil
      }
      return .handled(.init(next))

    case .remotePreferenceUpdateFailed(let completed):
      guard envelope.source == .cloudRemote, state.remote.preferenceOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.remote.preferenceOperation = nil
      next.remote.preferenceFailed = true
      return .handled(.init(next))

    case .remoteTabSelected(let tab):
      guard envelope.source == .settings, state.mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.remote.selectedTab = tab
      if tab == .thisDevice {
        next.remote.selectedDeviceID = nil
        next.remote.pairing.input = ""
        next.remote.pairing.outgoing = nil
        next.remote.pairing.requestOperation = nil
        next.remote.pairing.outgoingDeadlineOperation = nil
        next.remote.outgoingCommand = nil
        next.remote.lastUnknownCommand = nil
        next.remote.outgoingCommandOperation = nil
        next.remote.outgoingCommandDeadlineOperation = nil
        next.remote.selectedSnapshot = nil
        next.remote.editing = nil
        next.remote.exhibitionReviewAction = nil
      }
      return .handled(.init(next, reply: .accepted))

    case .remoteDeviceSelected(let id):
      guard envelope.source == .settings, state.mode == .administration,
        state.remote.selectedTab == .otherDevices
      else { return .reject(state, .invalidState) }
      if let id {
        let hidden =
          state.remote.installation?.hiddenDeviceIDs(
            for: state.remote.accountIdentifier) ?? []
        guard !hidden.contains(id), state.remote.devices.contains(where: { $0.id == id }) else {
          return .reject(state, .invalidState)
        }
      }
      if id != state.remote.selectedDeviceID {
        next.remote.pairing.input = ""
        next.remote.pairing.outgoing = nil
        next.remote.pairing.requestOperation = nil
        next.remote.pairing.outgoingDeadlineOperation = nil
        next.remote.outgoingCommand = nil
        next.remote.lastUnknownCommand = nil
        next.remote.outgoingCommandOperation = nil
        next.remote.outgoingCommandDeadlineOperation = nil
        next.remote.selectedSnapshot = nil
        next.remote.editing = nil
        next.remote.exhibitionReviewAction = nil
      }
      next.remote.selectedDeviceID = id
      return .handled(.init(next, reply: .accepted))

    default: return reduceRemotePairing(state, envelope)
    }
  }
}
