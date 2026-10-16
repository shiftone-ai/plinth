import Foundation

public enum AdministrationMediator {
  public static func reduce(
    _ state: AdministrationState, _ envelope: EventEnvelope,
    mode: AppMode
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
    case .openAdministration(let profile):
      guard envelope.source == .root, mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.savedProfile = profile
      next.passcode = ""
      next.draft = profile.map(ProfileDraft.init)
      next.catalogSelection = nil
      next.catalogSelectionNameDraft = ""
      next.catalogRequiresAvailableOutput = false
      next.saving = false
      next.saveFailed = false
      next.unlockID = nil
      next.verification = nil
      return .handled(
        .init(next, effects: state.verification.map { [Effect(token, .cancelOperation($0))] } ?? [])
      )

    case .draftChanged, .draftEdited:
      guard
        [.settings, .navigationRules, .interactionPolicy, .resetPolicy].contains(envelope.source)
      else { return .reject(state, .wrongSource) }
      guard mode == .administration, !state.saving else { return .reject(state, .invalidState) }
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
      guard envelope.source == .settings, mode == .administration, !state.saving else {
        return .reject(state, .invalidState)
      }
      next.draft = state.savedProfile.map(ProfileDraft.init)
      next.catalogRequiresAvailableOutput = false
      return .handled(.init(next, reply: .accepted))

    case .catalogPassphraseEdited, .catalogConfirmPassphraseEdited,
      .catalogPassphraseCleared, .catalogExportRequested, .catalogImportFileRequested,
      .catalogRegisterRequested, .catalogNameEdited, .catalogSelectionNameEdited,
      .catalogRegistrationSucceeded, .catalogSelectionOpened, .catalogSelectionDismissed,
      .catalogSelectionApplied:
      return reduceCatalog(state, envelope, mode: mode)

    case .addOriginRuleRequested, .removeOriginRuleRequested:
      guard [.settings, .navigationRules].contains(envelope.source),
        mode == .administration, !state.saving
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
      guard envelope.source == .settings else { return .reject(state, .wrongSource) }
      guard mode == .administration else { return .reject(state, .invalidState) }
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
      return .handled(.init(next))

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
      guard mode == .unlocking, state.unlockID != nil, state.verification == nil else {
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
