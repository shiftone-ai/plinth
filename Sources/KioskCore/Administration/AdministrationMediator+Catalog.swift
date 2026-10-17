import Foundation

extension AdministrationMediator {
  static func reduceCatalog(
    _ state: AdministrationState, _ envelope: EventEnvelope, mode: AppMode
  ) -> Mediation<AdministrationState> {
    var next = state
    switch envelope.event {
    case .catalogPassphraseEdited(let value), .catalogConfirmPassphraseEdited(let value):
      guard envelope.source == .settings, mode == .administration,
        value.utf8.count <= 1024
      else { return .reject(state, .invalidState) }
      if case .catalogPassphraseEdited = envelope.event {
        next.catalogPassphrase = value
      } else {
        next.catalogConfirmPassphrase = value
      }
      return .handled(.init(next, reply: .accepted))

    case .catalogPassphraseCleared:
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      next.catalogPassphrase = ""
      next.catalogConfirmPassphrase = ""
      return .handled(.init(next))

    case .catalogExportRequested(let ids):
      guard envelope.source == .settings, mode == .administration,
        state.catalogPassphrase.precomposedStringWithCanonicalMapping.count >= 16,
        state.catalogPassphrase.precomposedStringWithCanonicalMapping
          == state.catalogConfirmPassphrase.precomposedStringWithCanonicalMapping
      else { return .reject(state, .invalidProfile) }
      return .handled(
        .init(
          next, reply: .accepted,
          parentEvents: [
            .catalogExportOperationRequested(
              ids: ids, passphrase: state.catalogPassphrase)
          ]))

    case .catalogImportFileRequested(let url):
      guard envelope.source == .settings, mode == .administration,
        state.catalogPassphrase.precomposedStringWithCanonicalMapping.count >= 16
      else { return .reject(state, .invalidProfile) }
      return .handled(
        .init(
          next, reply: .accepted,
          parentEvents: [
            .catalogImportOperationRequested(
              url, passphrase: state.catalogPassphrase)
          ]))

    case .catalogRegisterRequested(let id, let name):
      guard envelope.source == .settings else { return .reject(state, .wrongSource) }
      guard mode == .administration, !state.saving, !state.hasUnsavedDraft,
        let profile = state.savedProfile
      else { return .reject(state, .invalidState) }
      return .handled(
        .init(
          next, reply: .accepted,
          parentEvents: [.catalogRegistrationRequested(id: id, name: name, profile: profile)]))

    case .catalogNameEdited(let value):
      guard envelope.source == .settings, mode == .administration,
        value.utf8.count <= 120
      else { return .reject(state, .invalidState) }
      next.catalogNameDraft = value
      return .handled(.init(next, reply: .accepted))

    case .catalogSelectionNameEdited(let value):
      guard envelope.source == .settings, mode == .administration,
        state.catalogSelection != nil, value.utf8.count <= 120
      else { return .reject(state, .invalidState) }
      next.catalogSelectionNameDraft = value
      return .handled(.init(next, reply: .accepted))

    case .catalogRegistrationSucceeded:
      guard envelope.source == .root else { return .reject(state, .wrongSource) }
      next.catalogNameDraft = ""
      return .handled(.init(next))

    case .catalogSelectionOpened(let entry):
      guard envelope.source == .root, mode == .administration, !state.saving,
        !state.hasUnsavedDraft
      else { return .reject(state, .invalidState) }
      next.catalogSelection = entry
      next.catalogSelectionNameDraft = entry.name
      return .handled(.init(next))

    case .catalogSelectionDismissed:
      guard envelope.source == .settings, mode == .administration else {
        return .reject(state, .invalidState)
      }
      next.catalogSelection = nil
      next.catalogSelectionNameDraft = ""
      return .handled(.init(next, reply: .accepted))

    case .catalogSelectionApplied(let entry):
      guard envelope.source == .root, mode == .administration, !state.saving,
        !state.hasUnsavedDraft, state.catalogSelection?.id == entry.id
      else { return .reject(state, .invalidState) }
      var profile = entry.snapshot.profile(revision: state.savedProfile?.revision ?? 1)
      profile.webAdministrationEnabled = state.savedProfile?.webAdministrationEnabled ?? false
      next.draft = ProfileDraft(profile: profile)
      next.catalogRequiresAvailableOutput = true
      next.catalogSelection = nil
      next.catalogSelectionNameDraft = ""
      return .handled(.init(next, reply: .accepted))

    default: return .bubble
    }
  }
}
