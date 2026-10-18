extension RootMediator {
  static func reduceWebAdministration(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    switch envelope.event {
    case .webServerStarted, .webServerFailed, .webServerStoppedUnexpectedly,
      .webServerAddressChanged:
      return reduceWebServerEvent(state, envelope)
    case .webAuthenticationVerified, .webSessionRequested:
      return reduceWebSessionEvent(state, envelope)
    default: return .bubble
    }
  }

  private static func reduceWebServerEvent(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    switch envelope.event {
    case .webServerStarted(let completed, let endpoint):
      guard envelope.source == .webAdministration,
        state.webServerOperation == completed,
        state.savedProfile?.webAdministrationEnabled == true
      else { return .reject(state, .staleOperation) }
      let currentEndpoint = state.pendingWebServerEndpoint ?? endpoint
      next.webServerOperation = nil
      next.pendingWebServerEndpoint = nil
      next.webServerRunning = true
      next.webServerURL = currentEndpoint.url
      next.localWebServerOrigins = currentEndpoint.origins
      next.webServerFailure = nil
      return .handled(
        .init(
          next,
          childControls: [
            .init(.exhibition, .localWebServerOriginsChanged(currentEndpoint.origins))
          ]))

    case .webServerFailed(let completed, let failure):
      guard envelope.source == .webAdministration,
        state.webServerOperation == completed
      else { return .reject(state, .staleOperation) }
      next.webServerOperation = nil
      next.pendingWebServerEndpoint = nil
      next.webServerRunning = false
      next.webServerURL = nil
      next.localWebServerOrigins = []
      next.webServerFailure = failure
      return .handled(
        .init(
          next,
          childControls: [
            .init(.exhibition, .localWebServerOriginsChanged([]))
          ]))

    case .webServerAddressChanged(let endpoint):
      return webServerAddressChanged(state, envelope, endpoint: endpoint)

    case .webServerStoppedUnexpectedly(let failure):
      return webServerStoppedUnexpectedly(state, envelope, failure: failure)

    default: return .bubble
    }
  }

  private static func webServerStoppedUnexpectedly(
    _ state: RootState, _ envelope: EventEnvelope, failure: WebServerFailure
  ) -> Mediation<RootState> {
    guard envelope.source == .webAdministration, state.webServerRunning else {
      return .reject(state, .staleOperation)
    }
    var next = state
    next.webServerRunning = false
    next.webServerURL = nil
    next.localWebServerOrigins = []
    next.webServerFailure = failure
    return .handled(
      .init(
        next,
        childControls: [
          .init(.exhibition, .localWebServerOriginsChanged([]))
        ]))
  }

  private static func webServerAddressChanged(
    _ state: RootState, _ envelope: EventEnvelope, endpoint: WebServerEndpoint
  ) -> Mediation<RootState> {
    guard envelope.source == .webAdministration else { return .reject(state, .wrongSource) }
    guard state.webServerRunning || state.webServerOperation != nil else {
      return .reject(state, .invalidState)
    }
    var next = state
    if state.webServerOperation != nil { next.pendingWebServerEndpoint = endpoint }
    next.webServerURL = endpoint.url
    next.localWebServerOrigins = endpoint.origins
    return .handled(
      .init(
        next,
        childControls: [.init(.exhibition, .localWebServerOriginsChanged(endpoint.origins))]))
  }

  private static func reduceWebSessionEvent(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    switch envelope.event {
    case .webAuthenticationVerified(let token):
      guard envelope.source == .administration else { return .reject(state, .wrongSource) }
      guard state.savedProfile?.webAdministrationEnabled == true,
        state.credentialsConfigured,
        state.mobileDisplays?.deviceAvailable != false,
        state.mode != .bootstrapping, state.mode != .terminating
      else { return .reject(state, .invalidState) }
      next.webSession = WebAdministrationSession(token: token, createdAt: envelope.timestamp)
      return .handled(.init(next))

    case .webSessionRequested(let token, let activity):
      guard envelope.source == .webAdministration else {
        return .reject(state, .wrongSource)
      }
      guard state.savedProfile?.webAdministrationEnabled == true,
        state.credentialsConfigured,
        var session = state.webSession, session.token == token
      else { return .reject(state, .unauthenticated) }
      guard session.isValid(at: envelope.timestamp) else {
        next.webSession = nil
        return .handled(.init(next, reply: .rejected(.unauthenticated)))
      }
      if activity { session.lastActivityAt = envelope.timestamp }
      next.webSession = session
      return .handled(.init(next, reply: .accepted))

    default: return .bubble
    }
  }

  static func withWebServerLifecycle(
    _ mediation: Mediation<RootState>, before: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    guard case .handled(var transition) = mediation else { return mediation }
    let canListen = transition.state.mobileDisplays == nil || transition.state.mobileForeground
    switch envelope.event {
    case .bootstrapped:
      if canListen,
        transition.state.savedProfile?.webAdministrationEnabled == true
          && transition.state.credentialsConfigured
      {
        startWebServer(&transition, event: envelope)
      }
    case .profileSaved:
      if transition.state.savedProfile?.webAdministrationEnabled == true {
        if canListen, transition.state.credentialsConfigured,
          !before.webServerRunning && before.webServerOperation == nil
        {
          startWebServer(&transition, event: envelope)
        }
      } else {
        transition.state.webSession = nil
        stopWebServer(&transition, event: envelope)
      }
    case .applicationDeactivated, .mobileLastSceneDisconnected:
      if before.mobileDisplays != nil { stopWebServer(&transition, event: envelope) }
    case .applicationActivated:
      if before.mobileDisplays != nil,
        before.savedProfile?.webAdministrationEnabled == true,
        before.credentialsConfigured,
        !before.webServerRunning, before.webServerOperation == nil
      {
        startWebServer(&transition, event: envelope)
      }
    case .systemDidWake:
      if before.mobileDisplays == nil,
        before.savedProfile?.webAdministrationEnabled == true,
        before.credentialsConfigured
      {
        stopWebServer(&transition, event: envelope)
        startWebServer(&transition, event: envelope)
      }
    case .credentialConfigured:
      if canListen, transition.state.credentialsConfigured,
        transition.state.savedProfile?.webAdministrationEnabled == true,
        !before.webServerRunning, before.webServerOperation == nil
      {
        startWebServer(&transition, event: envelope)
      }
    default: break
    }
    return .handled(transition)
  }

  private static func startWebServer(
    _ transition: inout Transition<RootState>, event: EventEnvelope
  ) {
    let token = event.token(owner: .webAdministration, epoch: transition.state.epoch)
    transition.state.webServerOperation = token
    transition.state.pendingWebServerEndpoint = nil
    transition.state.webServerFailure = nil
    transition.effects.append(Effect(token, .startWebServer))
  }

  private static func stopWebServer(
    _ transition: inout Transition<RootState>, event: EventEnvelope
  ) {
    if let pending = transition.state.webServerOperation {
      transition.effects.append(
        Effect(
          event.token(
            owner: .webAdministration,
            epoch: transition.state.epoch), .cancelOperation(pending)))
    }
    if transition.state.webServerRunning || transition.state.webServerOperation != nil {
      transition.effects.append(
        Effect(
          event.token(
            owner: .webAdministration,
            epoch: transition.state.epoch), .stopWebServer))
    }
    transition.state.webServerOperation = nil
    transition.state.pendingWebServerEndpoint = nil
    transition.state.webServerRunning = false
    transition.state.webServerURL = nil
    transition.state.localWebServerOrigins = []
    transition.childControls.append(.init(.exhibition, .localWebServerOriginsChanged([])))
  }
}
