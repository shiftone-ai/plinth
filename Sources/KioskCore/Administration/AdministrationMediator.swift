import Foundation

public struct WebOutputOptions: Equatable, Sendable {
  public let macDisplays: [DisplayDescriptor]?
  public let mobileDisplays: MobileDisplayAvailability?

  public init(
    macDisplays: [DisplayDescriptor]? = nil, mobileDisplays: MobileDisplayAvailability? = nil
  ) {
    self.macDisplays = macDisplays
    self.mobileDisplays = mobileDisplays
  }

  public func permits(_ edit: ProfileDraftEdit, draft: ProfileDraft?) -> Bool {
    switch edit {
    case .macOutputMode: return macDisplays != nil && mobileDisplays == nil
    case .macDisplayID(let id):
      return macDisplays != nil && mobileDisplays == nil
        && draft?.macOutput.mode == .fixedFullscreen
        && (id == nil || macDisplays?.contains(where: { $0.id == id }) == true)
    case .exhibitionDestination(let destination):
      guard let mobileDisplays else { return false }
      return destination != .externalDisplay || mobileDisplays.supportsExternalDisplay
    case .externalDisplayMode(let mode):
      guard let mobileDisplays, draft?.profile.exhibitionDestination == .externalDisplay else {
        return false
      }
      guard let mode else { return true }
      return mobileDisplays.displayModes.contains(mode)
    case .externalDisplayRotation:
      return mobileDisplays != nil && draft?.profile.exhibitionDestination == .externalDisplay
    default: return true
    }
  }
}

public enum AdministrationMediator {
  public static func reduce(
    _ state: AdministrationState, _ envelope: EventEnvelope,
    mode: AppMode, webEnabled: Bool = false,
    webOutputOptions: WebOutputOptions = .init()
  ) -> Mediation<AdministrationState> {
    var next = state
    let token = envelope.token(owner: .administration, epoch: state.epoch)
    switch envelope.event {
    case .passcodeEdited(let value):
      guard
        (envelope.source == .unlock && mode == .unlocking)
          || (envelope.source == .settings && mode == .administration)
      else { return .reject(state, .wrongSource) }
      guard state.verification == nil, value.utf8.count <= 1024 else {
        return .reject(state, .invalidState)
      }
      next.passcode = value
      return .handled(.init(next, reply: .accepted))

    case .clearPasscode:
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      next.passcode = ""
      return .handled(.init(next))
    case .invalidateWebAuthentication:
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      next.pendingWebLogin = nil
      next.webVerification = nil
      next.lastWebLogin = nil
      return .handled(
        .init(
          next,
          effects: state.webVerification.map {
            [Effect(token, .cancelOperation($0))]
          } ?? []))
    case .openAdministration(let profile):
      guard envelope.source == .root, mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.savedProfile = profile
      next.passcode = ""
      if !state.hasUnsavedDraft { next.draft = profile.map(ProfileDraft.init) }
      next.catalogSelection = nil
      next.catalogSelectionNameDraft = ""
      next.catalogRequiresAvailableOutput = false
      next.catalogPassphrase = ""
      next.catalogConfirmPassphrase = ""
      next.saving = false
      next.saveFailed = false
      next.unlockID = nil
      next.verification = nil
      return .handled(
        .init(next, effects: state.verification.map { [Effect(token, .cancelOperation($0))] } ?? [])
      )

    case .initializeWebDraft(let profile):
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      next.savedProfile = profile
      next.draft = profile.map(ProfileDraft.init)
      return .handled(.init(next))

    case .draftChanged, .draftEdited:
      guard
        [.settings, .navigationRules, .interactionPolicy, .resetPolicy, .webAdministration]
          .contains(envelope.source)
      else { return .reject(state, .wrongSource) }
      guard
        mode == .administration
          || (envelope.source == .webAdministration
            && [.exhibiting, .paused, .safeHold].contains(mode)),
        !state.saving
      else {
        return .reject(state, .invalidState)
      }
      if envelope.source == .webAdministration {
        guard case .draftEdited(let edit) = envelope.event else {
          return .reject(state, .wrongSource)
        }
        if case .webAdministrationEnabled = edit { return .reject(state, .wrongSource) }
        guard webOutputOptions.permits(edit, draft: state.draft) else {
          return .reject(state, .unsupportedDisplays)
        }
      }
      switch envelope.event {
      case .draftChanged(let draft): next.draft = draft
      case .draftEdited(let edit):
        var draft =
          state.draft
          ?? ProfileDraft(profile: KioskProfile(startURL: "", navigation: .init(rules: [])))
        guard draft.apply(edit) else { return .reject(state, .invalidState) }
        next.draft = draft
      default: break
      }
      next.saveFailed = false
      return .handled(.init(next, reply: .accepted))

    case .discardDraftRequested:
      guard
        (envelope.source == .settings && mode == .administration)
          || (envelope.source == .webAdministration
            && [.administration, .exhibiting, .paused, .safeHold].contains(mode)),
        !state.saving
      else {
        return .reject(state, .invalidState)
      }
      next.draft = state.savedProfile.map(ProfileDraft.init)
      next.catalogRequiresAvailableOutput = false
      next.saveFailed = false
      return .handled(.init(next, reply: .accepted))

    case .catalogPassphraseEdited, .catalogConfirmPassphraseEdited,
      .catalogPassphraseCleared, .catalogExportRequested, .catalogImportFileRequested,
      .catalogRegisterRequested, .catalogNameEdited, .catalogSelectionNameEdited,
      .catalogRegistrationSucceeded, .catalogSelectionOpened, .catalogSelectionDismissed,
      .catalogSelectionApplied:
      return reduceCatalog(state, envelope, mode: mode)

    case .addOriginRuleRequested, .removeOriginRuleRequested:
      guard [.settings, .navigationRules, .webAdministration].contains(envelope.source),
        mode == .administration
          || (envelope.source == .webAdministration
            && [.exhibiting, .paused, .safeHold].contains(mode)),
        !state.saving
      else { return .reject(state, .invalidState) }
      var draft =
        state.draft
        ?? ProfileDraft(profile: KioskProfile(startURL: "", navigation: .init(rules: [])))
      switch envelope.event {
      case .addOriginRuleRequested:
        let used = Set(draft.rules.map(\.id))
        var id: UInt64 = 1
        while used.contains(id) { id += 1 }
        draft.rules.append(.init(id: id, address: ""))
      case .removeOriginRuleRequested(let id): draft.rules.removeAll { $0.id == id }
      default: break
      }
      next.draft = draft
      next.saveFailed = false
      return .handled(.init(next, reply: .accepted))

    case .saveDraftRequested:
      guard [.settings, .webAdministration].contains(envelope.source) else {
        return .reject(state, .wrongSource)
      }
      guard
        mode == .administration
          || (envelope.source == .webAdministration
            && [.exhibiting, .paused, .safeHold].contains(mode))
      else {
        return .reject(state, .invalidState)
      }
      guard !state.saving else { return .reject(state, .alreadySaving) }
      guard var profile = state.draft?.validatedProfile else {
        return .reject(state, .invalidProfile)
      }
      guard let revision = ProfileRevision.next(after: state.savedProfile?.revision) else {
        return .reject(state, .invalidProfile)
      }
      profile.revision = revision
      next.saving = true
      next.saveFailed = false
      return .handled(
        .init(next, reply: .accepted, parentEvents: [.profileCommitRequested(profile)]))

    case .draftSaveSucceeded(let profile):
      guard envelope.source == .root, state.saving else { return .reject(state, .invalidState) }
      next.savedProfile = profile
      next.draft = ProfileDraft(profile: profile)
      next.catalogRequiresAvailableOutput = false
      next.saving = false
      if !profile.webAdministrationEnabled {
        next.pendingWebLogin = nil
        next.lastWebLogin = nil
        next.webVerification = nil
      }
      return .handled(
        .init(
          next,
          effects: !profile.webAdministrationEnabled
            ? state.webVerification.map { [Effect(token, .cancelOperation($0))] } ?? [] : []))

    case .webLoginRequested(let password, let candidate):
      guard envelope.source == .webAdministration else { return .reject(state, .wrongSource) }
      guard webEnabled, mode != .bootstrapping, mode != .terminating,
        state.verification == nil, state.webVerification == nil, password.utf8.count <= 1024,
        candidate.utf8.count == 64,
        candidate.utf8.allSatisfy({
          (48...57).contains($0) || (97...102).contains($0)
        })
      else { return .reject(state, .invalidState) }
      guard state.cooldownUntil.map({ envelope.timestamp >= $0 }) ?? true else {
        return .reject(state, .cooldown)
      }
      if state.cooldownUntil != nil {
        next.failedAttempts = 0
        next.cooldownUntil = nil
      }
      next.webVerification = token
      next.pendingWebLogin = candidate
      next.lastWebLogin = nil
      return .handled(
        .init(next, reply: .accepted, effects: [Effect(token, .verifyPasscode(password))]))

    case .webLoginStatusRequested(let candidate):
      guard envelope.source == .webAdministration else { return .reject(state, .wrongSource) }
      guard webEnabled else { return .reject(state, .unauthenticated) }
      if state.pendingWebLogin == candidate {
        return .handled(.init(state, reply: .webLoginStatus(.pending)))
      }
      guard state.lastWebLogin?.token == candidate else {
        return .reject(state, .unauthenticated)
      }
      return .handled(
        .init(
          state,
          reply: .webLoginStatus(
            state.lastWebLogin?.succeeded == true
              ? .succeeded : .failed)))

    case .draftSaveFailed:
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      next.saving = false
      next.saveFailed = true
      return .handled(.init(next))

    case .openUnlock(let unlockID):
      guard envelope.source == .root, mode == .unlocking else {
        return .reject(state, .invalidState)
      }
      next.unlockID = unlockID
      next.passcode = ""
      next.verification = nil
      next.epoch += 1
      return .handled(
        .init(next, effects: state.verification.map { [Effect(token, .cancelOperation($0))] } ?? [])
      )

    case .configurePasscodeRequested:
      guard envelope.source == .settings, mode == .administration else {
        return .reject(state, .invalidState)
      }
      return .handled(
        .init(
          next, reply: .accepted,
          parentEvents: [.credentialConfigurationRequested(state.passcode)]))

    case .passcodeSubmitted:
      guard envelope.source == .unlock else { return .reject(state, .wrongSource) }
      guard mode == .unlocking, state.unlockID != nil, state.verification == nil,
        state.webVerification == nil
      else {
        return .reject(state, .invalidState)
      }
      guard state.cooldownUntil.map({ envelope.timestamp >= $0 }) ?? true else {
        return .reject(state, .cooldown)
      }
      if state.cooldownUntil != nil {
        next.failedAttempts = 0
        next.cooldownUntil = nil
      }
      next.verification = token
      next.passcode = ""
      return .handled(
        .init(next, reply: .accepted, effects: [Effect(token, .verifyPasscode(state.passcode))]))

    case .credentialVerified(let completed, let succeeded):
      guard envelope.source == .credentials else { return .reject(state, .wrongSource) }
      if let candidate = state.pendingWebLogin {
        guard state.webVerification == completed else { return .reject(state, .staleOperation) }
        next.webVerification = nil
        next.pendingWebLogin = nil
        next.lastWebLogin = WebLoginResult(token: candidate, succeeded: succeeded)
        if succeeded {
          next.failedAttempts = 0
          next.cooldownUntil = nil
          return .handled(.init(next, parentEvents: [.webAuthenticationVerified(candidate)]))
        }
        next.failedAttempts += 1
        if next.failedAttempts >= 3 { next.cooldownUntil = envelope.timestamp + 30 }
        return .handled(.init(next))
      }
      guard mode == .unlocking, state.verification == completed, let unlockID = state.unlockID
      else {
        return .reject(state, .staleOperation)
      }
      next.verification = nil
      if succeeded {
        next.unlockID = nil
        next.failedAttempts = 0
        next.cooldownUntil = nil
        return .handled(.init(next, parentEvents: [.authenticationVerified(unlockID: unlockID)]))
      }
      next.failedAttempts += 1
      if next.failedAttempts >= 3 { next.cooldownUntil = envelope.timestamp + 30 }
      return .handled(.init(next))

    case .biometricAuthenticationVerified:
      guard envelope.source == .root, mode == .leavingKiosk else {
        return .reject(state, .invalidState)
      }
      next.unlockID = nil
      next.passcode = ""
      next.failedAttempts = 0
      next.cooldownUntil = nil
      next.verification = nil
      next.epoch += 1
      return .handled(
        .init(next, effects: state.verification.map { [Effect(token, .cancelOperation($0))] } ?? [])
      )

    case .cancelAuthentication:
      guard [.root, .unlock].contains(envelope.source) else { return .reject(state, .wrongSource) }
      next.unlockID = nil
      next.passcode = ""
      next.verification = nil
      next.epoch += 1
      return .handled(
        .init(
          next, reply: envelope.source == .unlock ? .accepted : nil,
          effects: state.verification.map { [Effect(token, .cancelOperation($0))] } ?? [],
          parentEvents: envelope.source == .unlock ? [.unlockCancelled] : []))
    default: return .bubble
    }
  }
}
