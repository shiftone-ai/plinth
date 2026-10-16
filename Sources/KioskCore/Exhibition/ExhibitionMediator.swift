public enum ExhibitionMediator {
  public static func reduce(_ state: ExhibitionState, _ envelope: EventEnvelope) -> Mediation<
    ExhibitionState
  > {
    var next = state
    switch envelope.event {
    case .localWebServerOriginsChanged(let origins):
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      next.localWebServerOrigins = origins
      return .handled(.init(next))
    case .webCapabilityRequested(_, let generation):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard generation == state.generation else { return .reject(state, .staleOperation) }
      return .reject(state, .unsupportedWindow)
    case .activateExhibition(let profile):
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      guard state.phase == .inactive else { return .reject(state, .invalidState) }
      guard profile.validationIssues.isEmpty else { return .reject(state, .invalidProfile) }
      next.profile = profile
      next.generation += 1
      next.phase = .preparing
      next.resetMode = profile.resetMode
      let token = envelope.token(
        owner: .exhibition, epoch: state.epoch, generation: next.generation)
      next.operation = token
      return .handled(
        .init(
          next,
          effects: [
            Effect(token, .createSurface(profile.resetMode, interaction: profile.interaction))
          ]))

    case .surfaceCreated(let completed):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard state.operation == completed, [.preparing, .recreatingSurface].contains(state.phase),
        let profile = state.profile
      else { return .reject(state, .staleOperation) }
      next.surfaceExists = true
      if state.phase == .recreatingSurface { next.phase = .loadingHome }
      let token = envelope.token(
        owner: .exhibition, epoch: state.epoch, generation: state.generation)
      next.operation = token
      next.pageLoad = .loading
      return .handled(.init(next, effects: [Effect(token, .load(profile.startURL))]))

    case .webNavigationBegan(let started):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard state.operation == started, [.preparing, .loadingHome, .ready].contains(state.phase)
      else {
        return .reject(state, .staleOperation)
      }
      next.pageLoad = .loading
      return .handled(.init(next))

    case .webFinished(let completed):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard state.operation == completed, [.preparing, .loadingHome, .ready].contains(state.phase)
      else {
        return .reject(state, .staleOperation)
      }
      next.phase = .ready
      next.pageLoad = .settled
      next.retryAttempt = 0
      return .handled(
        .init(
          next,
          parentEvents: [.preparing, .loadingHome].contains(state.phase) ? [.exhibitionReady] : []))

    case .webCommitted(let completed, let url):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard state.operation == completed, [.preparing, .loadingHome, .ready].contains(state.phase),
        let profile = state.profile
      else { return .reject(state, .staleOperation) }
      guard profile.evaluateNavigation(url) == .allow else { return .reject(state, .urlBlocked) }
      next.currentURL = url
      if state.phase == .ready && state.idleDeadline == nil && url != profile.startURL {
        return engage(next, envelope)
      }
      return .handled(.init(next))

    case .navigationRequested(
      let url, let generation, let mainFrame, let newWindow, let isGET, let supported):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard generation == state.generation,
        [.preparing, .loadingHome, .ready].contains(state.phase),
        let profile = state.profile
      else {
        return .handled(.init(state, reply: .navigation(.cancel(.staleOperation))))
      }
      guard !newWindow || isGET else {
        return .handled(.init(state, reply: .navigation(.cancel(.unsupportedWindow))))
      }
      if let origin = Origin(urlString: url), state.localWebServerOrigins.contains(origin) {
        return .handled(.init(state, reply: .navigation(.cancel(.urlBlocked))))
      }
      let decision: NavigationDecision =
        supported
        ? profile.evaluateNavigation(url, enforceOriginRules: mainFrame || newWindow)
        : .cancel(.unsupportedWindow)
      if mainFrame && decision != .allow {
        if state.phase == .preparing || state.phase == .loadingHome {
          if case .handled(var failed) = recover(state, envelope, failure: .policyDenied) {
            failed.reply = .navigation(decision)
            return .handled(failed)
          }
        }
        next.pageLoad = .settled
        return .handled(.init(next, reply: .navigation(decision)))
      }
      if newWindow && decision == .allow {
        let token = envelope.token(
          owner: .exhibition, epoch: state.epoch, generation: state.generation)
        next.operation = token
        return .handled(
          .init(
            next, reply: .navigation(.cancel(.unsupportedWindow)),
            effects: [Effect(token, .load(url))]))
      }
      return .handled(.init(state, reply: .navigation(decision)))

    case .visitorActivity:
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      guard state.phase == .ready else { return .reject(state, .invalidState) }
      return engage(state, envelope)

    case .idleDeadlineReached(let completed):
      guard envelope.source == .idleClock else { return .reject(state, .wrongSource) }
      guard state.phase == .ready, state.idleOperation == completed,
        let deadline = state.idleDeadline
      else {
        return .reject(state, .staleOperation)
      }
      if envelope.timestamp < deadline {
        let token = envelope.token(
          owner: .exhibition, epoch: state.epoch, generation: state.generation)
        next.idleOperation = token
        return .handled(.init(next, effects: [Effect(token, .scheduleIdle(deadline: deadline))]))
      }
      return quiesce(
        state, envelope, stopping: false, mode: state.profile?.resetMode ?? .newVisitorSession)

    case .resetExhibition(let mode):
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      guard [.preparing, .loadingHome, .ready, .recovering, .unavailable].contains(state.phase)
      else {
        return .reject(state, .invalidState)
      }
      return quiesce(state, envelope, stopping: false, mode: mode)

    case .stopExhibition:
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      if state.phase == .inactive {
        return .handled(.init(state, parentEvents: [.exhibitionStopped]))
      }
      if state.phase == .quiescing {
        next.stopping = true
        return .handled(.init(next))
      }
      return quiesce(state, envelope, stopping: true, mode: state.resetMode)

    case .surfaceReleased(let completed):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard state.releaseOperation == completed else { return .reject(state, .staleOperation) }
      next.releaseOperation = nil
      next.surfaceExists = false
      if state.phase == .recovering {
        return next.retryDue ? prepareRetry(next, envelope) : .handled(.init(next))
      }
      guard state.phase == .quiescing else { return .reject(state, .invalidState) }
      if state.stopping {
        next.phase = .inactive
        next.profile = nil
        next.operation = nil
        return .handled(.init(next, parentEvents: [.exhibitionStopped]))
      }
      let token = envelope.token(
        owner: .exhibition, epoch: state.epoch, generation: state.generation)
      next.phase = .recreatingSurface
      next.operation = token
      return .handled(
        .init(
          next,
          effects: [
            Effect(
              token,
              .createSurface(state.resetMode, interaction: state.profile?.interaction ?? .init()))
          ]))

    case .webFailed(let completed, let failure):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard state.operation == completed, [.preparing, .loadingHome, .ready].contains(state.phase)
      else {
        return .reject(state, .staleOperation)
      }
      return recover(state, envelope, failure: failure)

    case .webProcessTerminated(let generation):
      guard envelope.source == .webSurface else { return .reject(state, .wrongSource) }
      guard generation == state.generation,
        [.preparing, .loadingHome, .ready].contains(state.phase)
      else {
        return .reject(state, .staleOperation)
      }
      return recover(state, envelope, failure: .processTerminated)

    case .retryDeadlineReached(let completed):
      guard envelope.source == .idleClock else { return .reject(state, .wrongSource) }
      guard state.phase == .recovering, state.retryOperation == completed,
        let deadline = state.retryDeadline
      else { return .reject(state, .staleOperation) }
      if envelope.timestamp < deadline {
        let token = envelope.token(
          owner: .exhibition, epoch: state.epoch, generation: state.generation)
        next.retryOperation = token
        return .handled(.init(next, effects: [Effect(token, .scheduleRetry(deadline: deadline))]))
      }
      next.retryOperation = nil
      next.retryDue = true
      return next.releaseOperation == nil ? prepareRetry(next, envelope) : .handled(.init(next))
    default: return .bubble
    }
  }

  private static func engage(_ state: ExhibitionState, _ envelope: EventEnvelope) -> Mediation<
    ExhibitionState
  > {
    guard let profile = state.profile else { return .reject(state, .invalidState) }
    var next = state
    let deadline = envelope.timestamp + profile.idleTimeout
    next.idleDeadline = deadline
    if state.idleOperation != nil { return .handled(.init(next)) }
    let token = envelope.token(owner: .exhibition, epoch: state.epoch, generation: state.generation)
    next.idleOperation = token
    return .handled(.init(next, effects: [Effect(token, .scheduleIdle(deadline: deadline))]))
  }

  private static func cancellations(_ state: ExhibitionState, token: OperationToken) -> [Effect] {
    [state.operation, state.idleOperation, state.retryOperation].compactMap { $0 }.map {
      Effect(token, .cancelOperation($0))
    }
  }

  private static func quiesce(
    _ state: ExhibitionState, _ envelope: EventEnvelope,
    stopping: Bool, mode: ResetMode
  ) -> Mediation<ExhibitionState> {
    var next = state
    next.generation += 1
    next.phase = .quiescing
    next.pageLoad = .settled
    next.stopping = stopping
    next.resetMode = mode
    next.operation = nil
    next.idleOperation = nil
    next.idleDeadline = nil
    next.retryOperation = nil
    next.retryDeadline = nil
    next.currentURL = nil
    let token = envelope.token(owner: .exhibition, epoch: state.epoch, generation: state.generation)
    var effects = cancellations(state, token: token)
    if let pendingRelease = state.releaseOperation {
      next.releaseOperation = pendingRelease
    } else if state.surfaceExists
      || (state.operation != nil && [.preparing, .recreatingSurface].contains(state.phase))
    {
      let release = envelope.token(
        owner: .exhibition, epoch: state.epoch, generation: state.generation)
      next.releaseOperation = release
      effects.append(Effect(release, .releaseSurface(generation: state.generation)))
    } else if stopping {
      next.phase = .inactive
      next.profile = nil
      return .handled(.init(next, effects: effects, parentEvents: [.exhibitionStopped]))
    } else {
      next.phase = .recreatingSurface
      next.operation = token
      effects.append(
        Effect(token, .createSurface(mode, interaction: state.profile?.interaction ?? .init())))
    }
    return .handled(.init(next, effects: effects))
  }

  private static func recover(
    _ state: ExhibitionState, _ envelope: EventEnvelope,
    failure: WebFailure
  ) -> Mediation<ExhibitionState> {
    guard let profile = state.profile else { return .reject(state, .invalidState) }
    var next = state
    next.generation += 1
    next.operation = nil
    next.pageLoad = .settled
    next.idleOperation = nil
    next.idleDeadline = nil
    let token = envelope.token(owner: .exhibition, epoch: state.epoch, generation: next.generation)
    var effects = cancellations(state, token: token)
    if !failure.canRetry || state.retryAttempt >= profile.recovery.maximumAttempts {
      next.phase = .unavailable
      return .handled(.init(next, effects: effects, parentEvents: [.exhibitionUnavailable]))
    }
    next.phase = .recovering
    next.retryAttempt += 1
    next.retryDue = false
    let deadline = envelope.timestamp + profile.recovery.delay
    next.retryDeadline = deadline
    next.retryOperation = token
    if state.surfaceExists {
      let release = envelope.token(
        owner: .exhibition, epoch: state.epoch, generation: state.generation)
      next.releaseOperation = release
      effects.append(Effect(release, .releaseSurface(generation: state.generation)))
    }
    effects.append(Effect(token, .scheduleRetry(deadline: deadline)))
    return .handled(.init(next, effects: effects))
  }

  private static func prepareRetry(_ state: ExhibitionState, _ envelope: EventEnvelope)
    -> Mediation<ExhibitionState>
  {
    var next = state
    let token = envelope.token(owner: .exhibition, epoch: state.epoch, generation: state.generation)
    next.phase = .preparing
    next.operation = token
    next.retryOperation = nil
    next.retryDeadline = nil
    next.retryDue = false
    return .handled(
      .init(
        next,
        effects: [
          Effect(
            token,
            .createSurface(state.resetMode, interaction: state.profile?.interaction ?? .init()))
        ]))
  }
}
