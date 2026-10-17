public enum RootMediator {
  public static func reduce(
    _ state: RootState, _ envelope: EventEnvelope,
    context: ReadonlyContext = .init()
  ) -> Mediation<RootState> {
    switch envelope.event {
    case .webAuthenticationVerified, .webSessionRequested, .webServerStarted,
      .webServerFailed, .webServerStoppedUnexpectedly, .webServerAddressChanged:
      return reduceWebAdministration(state, envelope)
    case .webRestartExhibitionRequested, .webStopExhibitionRequested,
      .webResumeExhibitionRequested:
      return reduceWebExhibition(state, envelope, context: context)
    case .bootstrapped:
      return withWebServerLifecycle(bootstrapCompleted(state, envelope), before: state, envelope)
    case .biometricStatusRequested, .biometricStatusRead, .biometricChangeRequested,
      .biometricChangeCompleted, .biometricChangeCancelled,
      .biometricUnlockRequested, .biometricUnlockCancelled, .biometricUnlockCompleted:
      return reduceBiometric(state, envelope)
    case .applicationDeactivated, .systemWillSleep, .unlockDeadlineReached,
      .unlockCancelled, .authenticationVerified:
      return withWebServerLifecycle(
        reduceUnlockLifecycle(state, envelope), before: state, envelope)
    case .externalMouseAvailabilityChanged, .externalPointerCaptureCompleted,
      .externalPointerCaptureChanged, .externalMouseInput, .nativePointerMoved,
      .nativePointerConstraintFailed, .unlockRequested:
      if let pointer = reducePointer(state, envelope, context: context) { return pointer }
    case .externalWebControlDeliveryFailed, .externalWebControlExecutionRequested,
      .externalWebControlRequested:
      if let control = reduceExternalControl(state, envelope, context: context) { return control }
    default: break
    }
    return withWebServerLifecycle(
      reduceLifecycle(state, envelope, context: context), before: state, envelope)
  }

  private static func reduceUnlockLifecycle(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .applicationDeactivated:
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      var next = state
      if state.mobileDisplays != nil { next.mobileForeground = false }
      let resumes =
        state.mobileDisplays != nil && !state.administratorSession
        && (state.mode == .exhibiting || state.mode == .enteringKiosk
          || state.foregroundResume != .none)
      return hold(next, token: token, resumeOnActivation: resumes)

    case .systemWillSleep:
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      return hold(state, token: token)

    case .unlockDeadlineReached(let completed):
      guard envelope.source == .idleClock, state.unlockTimeoutOperation == completed else {
        return .reject(state, .staleOperation)
      }
      if let deadline = state.unlockDeadline, envelope.timestamp < deadline {
        var next = state
        next.unlockTimeoutOperation = token
        return .handled(
          .init(next, effects: [Effect(token, .scheduleUnlockTimeout(deadline: deadline))]))
      }
      return cancelUnlock(state, token: token)

    case .unlockCancelled:
      guard [.administration, .unlock, .platform].contains(envelope.source) else {
        return .reject(state, .wrongSource)
      }
      return cancelUnlock(state, token: token)

    case .authenticationVerified(let unlockID):
      guard envelope.source == .administration else { return .reject(state, .wrongSource) }
      guard state.mode == .unlocking, state.unlockID == unlockID else {
        return .reject(state, .staleOperation)
      }
      return completeAuthentication(state, token: token)

    default: return .bubble
    }
  }

  private static func reduceLifecycle(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .openInformationPageRequested(let page, let locale):
      guard envelope.source == .settings else { return .reject(state, .wrongSource) }
      guard state.mode == .administration else { return .reject(state, .invalidState) }
      return .handled(
        .init(
          state, reply: .accepted,
          effects: [Effect(token, .openInformationPage(page, locale: locale))]))
    case .bootstrapRequested:
      guard state.mode == .bootstrapping, state.bootstrapOperation == nil,
        envelope.source == .root
      else { return .reject(state, .invalidState) }
      next.bootstrapOperation = token
      return .handled(.init(next, effects: [Effect(token, .bootstrap)]))

    case .bootstrapFailed(let completed, let displayCount):
      guard state.mode == .bootstrapping, envelope.source == .profileRepository,
        state.bootstrapOperation == completed
      else {
        return .reject(state, .invalidState)
      }
      next.bootstrapOperation = nil
      next.displayCount = displayCount
      next.mode = .safeHold
      return .handled(.init(next))

    case .systemDidWake:
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      return .handled(.init(next))

    case .applicationActivated:
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      if state.mobileDisplays != nil { next.mobileForeground = true }
      if state.mode == .administration {
        guard state.biometricOperation == nil else { return .handled(.init(next)) }
        let statusToken = envelope.token(owner: .credentials, epoch: state.epoch)
        next.biometricStatusOperation = statusToken
        return .handled(.init(next, effects: [Effect(statusToken, .readBiometricStatus)]))
      }
      if state.mode == .unlocking, state.unlockID != nil, state.credentialsConfigured,
        state.biometricUnlockOperation == nil
      {
        let statusToken = envelope.token(owner: .credentials, epoch: state.epoch)
        next.biometricStatusOperation = statusToken
        return .handled(.init(next, effects: [Effect(statusToken, .readBiometricStatus)]))
      }
      guard state.mode == .safeHold,
        state.pointerCaptureFailed || state.foregroundResume == .awaitingActivation,
        state.foregroundResume != .awaitingStop, !state.administratorSession,
        let profile = state.activeProfile
      else { return .handled(.init(next)) }
      guard state.canPresent(profile) else {
        if profile.exhibitionDestination == .externalDisplay,
          state.mobileDisplays?.externalConnected == true
        {
          next.foregroundResume = .awaitingDisplay
        }
        return .handled(.init(next))
      }
      next.foregroundResume = .awaitingStop
      return .handled(.init(next, childControls: [.init(.exhibition, .stopExhibition)]))

    case .credentialConfigurationRequested(let passcode):
      guard envelope.source == .administration else { return .reject(state, .wrongSource) }
      guard state.mode == .administration, state.credentialOperation == nil else {
        return .reject(state, .invalidState)
      }
      guard passcode.count >= 8, passcode.utf8.count <= 1024 else {
        return .reject(state, .invalidProfile)
      }
      next.credentialOperation = token
      next.credentialConfigurationFailed = false
      return .handled(
        .init(next, reply: .accepted, effects: [Effect(token, .configurePasscode(passcode))]))

    case .credentialConfigured(let completed, let succeeded):
      guard envelope.source == .credentials, state.credentialOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.credentialOperation = nil
      next.credentialConfigurationFailed = !succeeded
      if succeeded {
        next.credentialsConfigured = true
        next.webSession = nil
      }
      let controls: [ChildControl] =
        succeeded
        ? [
          .init(.administration, .clearPasscode),
          .init(.administration, .invalidateWebAuthentication),
        ]
        : [.init(.administration, .clearPasscode)]
      return .handled(.init(next, childControls: controls))
    case .startExhibitionRequested:
      guard [.settings, .administration, .webAdministration].contains(envelope.source) else {
        return .reject(state, .wrongSource)
      }
      guard state.mode == .administration else { return .reject(state, .invalidState) }
      guard state.credentialsConfigured else { return .reject(state, .unauthenticated) }
      guard !context.hasUnsavedDraft, state.saveOperation == nil, state.credentialOperation == nil,
        state.biometricOperation == nil,
        state.externalSceneOperation == nil
      else {
        return .reject(state, .unsavedDraft)
      }
      guard let profile = state.savedProfile, profile.validationIssues.isEmpty else {
        return .reject(state, .invalidProfile)
      }
      guard state.canPresent(profile) else { return .reject(state, .unsupportedDisplays) }
      if envelope.source == .webAdministration {
        next.webRestartInProgress = true
        next.webRestartFailed = false
      }
      return enter(next, profile: profile, token: token, reply: .accepted)

    case .presentationApplied, .presentationFailed, .exhibitionReady, .exhibitionUnavailable:
      return reducePresentation(state, envelope, context: context)

    case .unlockDeadlineReached(let completed):
      guard envelope.source == .idleClock, state.unlockTimeoutOperation == completed else {
        return .reject(state, .staleOperation)
      }
      if let deadline = state.unlockDeadline, envelope.timestamp < deadline {
        next.unlockTimeoutOperation = token
        return .handled(
          .init(next, effects: [Effect(token, .scheduleUnlockTimeout(deadline: deadline))]))
      }
      return cancelUnlock(state, token: token)

    case .unlockCancelled:
      guard [.administration, .unlock, .platform].contains(envelope.source) else {
        return .reject(state, .wrongSource)
      }
      return cancelUnlock(state, token: token)

    case .authenticationVerified(let unlockID):
      guard envelope.source == .administration else { return .reject(state, .wrongSource) }
      guard state.mode == .unlocking, state.unlockID == unlockID else {
        return .reject(state, .staleOperation)
      }
      return completeAuthentication(state, token: token)

    case .exhibitionStopped, .presentationReleased:
      return reducePresentation(state, envelope, context: context)

    case .prepareExternalSceneRequested, .externalScenePrepared,
      .externalScenePreparationFailed, .mobileDisplaysChanged, .macDisplaysChanged,
      .displayCountChanged:
      return reduceDisplay(state, envelope, context: context)

    case .nativeInput(let input, let scope):
      guard envelope.source == .platform else { return .reject(state, .wrongSource) }
      let decision = InputPolicy.evaluate(
        input, scope: scope, mode: state.mode,
        webAvailable: context.webAvailable, generation: context.webGeneration,
        policy: state.activeProfile?.interaction ?? .init(), state: state.input)
      next.input = decision.state
      return .handled(
        .init(
          next, reply: .input(decision),
          childControls:
            decision.recordsVisitorActivity ? [.init(.exhibition, .visitorActivity)] : []))

    case .profileCommitRequested, .profileSaved, .profileSaveFailed:
      return reduceProfile(state, envelope, context: context)

    case .terminateRequested:
      guard [.platform, .settings, .administration].contains(envelope.source) else {
        return .reject(state, .wrongSource)
      }
      guard state.mode == .administration else { return .reject(state, .unauthenticated) }
      next.mode = .terminating
      next.externalSceneOperation = nil
      return .handled(
        .init(
          next, reply: .accepted,
          effects: state.externalSceneOperation.map { [Effect(token, .cancelOperation($0))] } ?? [],
          childControls: [
            .init(.administration, .cancelAuthentication), .init(.exhibition, .stopExhibition),
          ]))
    default: return .bubble
    }
  }

  static func requiresStableDisplay(_ state: RootState) -> Bool {
    // Authentication from an already stopped exhibition must survive reconnect notifications.
    // Cancellation from a live exhibition still requires the original output to remain available.
    state.mode == .enteringKiosk || state.mode == .exhibiting
      || (state.mode == .unlocking && state.unlockReturnMode != .safeHold)
  }

  static func completeAuthentication(
    _ state: RootState, token: OperationToken, fromBiometrics: Bool = false
  ) -> Mediation<RootState> {
    var next = state
    next.mode = .leavingKiosk
    next.administratorSession = true
    next.unlockID = nil
    next.unlockReturnMode = nil
    next.unlockTimeoutOperation = nil
    next.unlockDeadline = nil
    next.biometricUnlockOperation = nil
    next.biometricStatusOperation = nil
    next.biometricUnlockFailed = false
    let operations = [
      state.unlockTimeoutOperation, state.biometricUnlockOperation,
      state.biometricStatusOperation,
    ].compactMap { $0 }
    let controls: [ChildControl] =
      (fromBiometrics ? [.init(.administration, .biometricAuthenticationVerified)] : [])
      + [.init(.exhibition, .stopExhibition)]
    return .handled(
      .init(
        next, effects: operations.map { Effect(token, .cancelOperation($0)) },
        childControls: controls))
  }

  static func hold(
    _ state: RootState, token: OperationToken, resumeOnActivation: Bool = false
  ) -> Mediation<RootState> {
    var next = state
    next.foregroundResume = resumeOnActivation ? .awaitingActivation : .none
    guard [.enteringKiosk, .exhibiting, .unlocking].contains(state.mode) else {
      return .handled(.init(next))
    }
    next.mode = .safeHold
    if state.webRestartInProgress {
      next.webRestartInProgress = false
      next.webRestartFailed = true
    }
    next.input = .init()
    next.externalPointer = nil
    next.externalButtonDown = false
    next.unlockID = nil
    next.unlockTimeoutOperation = nil
    next.unlockDeadline = nil
    next.biometricUnlockOperation = nil
    next.biometricStatusOperation = nil
    var effects = state.unlockTimeoutOperation.map { [Effect(token, .cancelOperation($0))] } ?? []
    effects += state.biometricUnlockOperation.map { [Effect(token, .cancelOperation($0))] } ?? []
    effects += state.biometricStatusOperation.map { [Effect(token, .cancelOperation($0))] } ?? []
    effects += releasePointer(&next, token: token)
    if let operation = state.presentationOperation {
      next.presentationOperation = nil
      effects.append(Effect(token, .cancelOperation(operation)))
    }
    return .handled(
      .init(
        next, effects: effects,
        childControls: [
          .init(.administration, .cancelAuthentication), .init(.exhibition, .stopExhibition),
        ]))

  }

  private static func cancelUnlock(_ state: RootState, token: OperationToken) -> Mediation<
    RootState
  > {
    var next = state
    guard state.mode == .unlocking else { return .reject(state, .invalidState) }
    next.mode = state.unlockReturnMode ?? .safeHold
    next.unlockID = nil
    next.unlockReturnMode = nil
    next.unlockTimeoutOperation = nil
    next.unlockDeadline = nil
    next.biometricUnlockOperation = nil
    next.biometricStatusOperation = nil
    next.biometricUnlockFailed = false
    var controls: [ChildControl] = [.init(.administration, .cancelAuthentication)]
    if next.mode == .exhibiting {
      controls.append(.init(.exhibition, .resetExhibition(.newVisitorSession)))
    }
    return .handled(
      .init(
        next, reply: .accepted,
        effects: (state.unlockTimeoutOperation.map { [Effect(token, .cancelOperation($0))] } ?? [])
          + (state.biometricUnlockOperation.map { [Effect(token, .cancelOperation($0))] } ?? [])
          + (state.biometricStatusOperation.map { [Effect(token, .cancelOperation($0))] } ?? []),
        childControls: controls))

  }

  static func enter(
    _ state: RootState, profile: KioskProfile, token: OperationToken,
    reply: Reply? = nil
  ) -> Mediation<RootState> {
    var next = state
    next.mode = .enteringKiosk
    next.webExitDestination = nil
    next.pointerCaptureFailed = false
    next.foregroundResume = .none
    next.activeProfile = profile
    next.presentationOperation = token
    next.presentationAcquisition = token
    next.administratorSession = false
    let settings = state.mobileDisplays == nil ? profile.macOutput ?? .init() : .init()
    let display = state.macDisplays.flatMap { DisplaySelection.select(settings, from: $0) }
    let usesExternalDisplay =
      state.mobileDisplays != nil && profile.exhibitionDestination == .externalDisplay
    let externalMode =
      usesExternalDisplay
      ? profile.externalDisplayMode : nil
    let request = PresentationRequest(
      mode: settings.mode, displayID: display?.id, externalDisplayMode: externalMode,
      usesExternalDisplay: usesExternalDisplay,
      externalDisplayRotation: usesExternalDisplay
        ? profile.externalDisplayRotation ?? .standard : .standard)
    return .handled(
      .init(next, reply: reply, effects: [Effect(token, .applyPresentation(request))]))
  }

  static func administration(_ state: RootState, token: OperationToken) -> Mediation<
    RootState
  > {
    var next = state
    next.mode = .administration
    next.activeProfile = nil
    let statusToken = OperationToken(
      owner: .credentials, ownerEpoch: token.ownerEpoch, operationID: token.operationID)
    next.biometricStatusOperation = statusToken
    return .handled(
      .init(
        next, effects: [Effect(statusToken, .readBiometricStatus)],
        childControls: [.init(.administration, .openAdministration(state.savedProfile))]))
  }

  static func pause(_ state: RootState) -> Mediation<RootState> {
    var next = state
    next.mode = .paused
    next.webExitDestination = nil
    next.webRestartInProgress = false
    return .handled(.init(next))
  }
}
