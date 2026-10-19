import Foundation

public enum RemoteCommandPayload: Codable, Equatable, Sendable {
  case readStatus
  case saveProfile(RemoteProfilePatch)
  case exhibition(RemoteExhibitionAction)
}

public enum RemoteExhibitionAction: String, Codable, Equatable, Sendable {
  case start, restart, stop, resume

  public var rootEvent: Event {
    switch self {
    case .start: .startExhibitionRequested
    case .restart: .webRestartExhibitionRequested
    case .stop: .webStopExhibitionRequested
    case .resume: .webResumeExhibitionRequested
    }
  }
}

public enum RemoteProfileEdit: Codable, Equatable, Sendable {
  case startURL(String)
  case navigationMode(NavigationPolicy.Mode)
  case navigationRules([OriginRule])
  case allowsHTTP(Bool)
  case allowsScroll(Bool)
  case allowsDrag(Bool)
  case idleTimeout(Double)
  case resetMode(ResetMode)
  case exhibitionDestination(ExhibitionDestination?)
  case macOutput(MacOutputSettings?)
  case externalDisplayMode(ExternalDisplayMode?)
  case externalDisplayRotation(ExternalDisplayRotation?)

  public var changesOutput: Bool {
    switch self {
    case .exhibitionDestination, .macOutput, .externalDisplayMode,
      .externalDisplayRotation:
      true
    default: false
    }
  }
}

public struct RemoteProfilePatch: Codable, Equatable, Sendable {
  public let baseRevision: UInt64?
  public let edits: [RemoteProfileEdit]

  public init(baseRevision: UInt64?, edits: [RemoteProfileEdit]) {
    self.baseRevision = baseRevision
    self.edits = edits
  }

  public func apply(to saved: KioskProfile?) -> KioskProfile? {
    guard let saved, !edits.isEmpty,
      let revision = ProfileRevision.next(after: saved.revision)
    else { return nil }
    var result = saved
    result.revision = revision
    for edit in edits {
      switch edit {
      case .startURL(let value): result.startURL = value
      case .navigationMode(let value): result.navigation.mode = value
      case .navigationRules(let value): result.navigation.rules = value
      case .allowsHTTP(let value): result.navigation.allowsHTTP = value
      case .allowsScroll(let value): result.interaction.allowsScroll = value
      case .allowsDrag(let value): result.interaction.allowsDrag = value
      case .idleTimeout(let value): result.idleTimeout = value
      case .resetMode(let value): result.resetMode = value
      case .exhibitionDestination(let value): result.exhibitionDestination = value
      case .macOutput(let value): result.macOutput = value
      case .externalDisplayMode(let value): result.externalDisplayMode = value
      case .externalDisplayRotation(let value): result.externalDisplayRotation = value
      }
    }
    return result
  }
}

public struct RemoteEditingState: Equatable, Sendable {
  public let targetID: UUID
  public let baseProfile: KioskProfile?
  public var draft: ProfileDraft
  public var reviewOpen = false

  public init(targetID: UUID, baseProfile: KioskProfile?) {
    self.targetID = targetID
    self.baseProfile = baseProfile
    draft = ProfileDraft(
      profile: baseProfile
        ?? KioskProfile(startURL: "", navigation: .init(rules: [])))
  }

  public var hasChanges: Bool {
    guard let baseProfile else { return false }
    return draft.profile.startURL != baseProfile.startURL
      || draft.profile.navigation.mode != baseProfile.navigation.mode
      || draft.rules != ProfileDraft(profile: baseProfile).rules
      || draft.profile.navigation.allowsHTTP != baseProfile.navigation.allowsHTTP
      || draft.profile.interaction != baseProfile.interaction
      || draft.idleTimeoutText != String(baseProfile.idleTimeout)
      || draft.profile.resetMode != baseProfile.resetMode
      || draft.profile.exhibitionDestination != baseProfile.exhibitionDestination
      || draft.profile.macOutput != baseProfile.macOutput
      || draft.profile.externalDisplayMode != baseProfile.externalDisplayMode
      || draft.profile.externalDisplayRotation != baseProfile.externalDisplayRotation
  }
  public var patch: RemoteProfilePatch {
    guard let baseProfile, let validated = draft.validatedProfile else {
      return RemoteProfilePatch(baseRevision: baseProfile?.revision, edits: [])
    }
    var edits: [RemoteProfileEdit] = []
    if validated.startURL != baseProfile.startURL {
      edits.append(.startURL(validated.startURL))
    }
    if validated.navigation.mode != baseProfile.navigation.mode {
      edits.append(.navigationMode(validated.navigation.mode))
    }
    if validated.navigation.rules != baseProfile.navigation.rules {
      edits.append(.navigationRules(validated.navigation.rules))
    }
    if validated.navigation.allowsHTTP != baseProfile.navigation.allowsHTTP {
      edits.append(.allowsHTTP(validated.navigation.allowsHTTP))
    }
    if validated.interaction.allowsScroll != baseProfile.interaction.allowsScroll {
      edits.append(.allowsScroll(validated.interaction.allowsScroll))
    }
    if validated.interaction.allowsDrag != baseProfile.interaction.allowsDrag {
      edits.append(.allowsDrag(validated.interaction.allowsDrag))
    }
    if validated.idleTimeout != baseProfile.idleTimeout {
      edits.append(.idleTimeout(validated.idleTimeout))
    }
    if validated.resetMode != baseProfile.resetMode {
      edits.append(.resetMode(validated.resetMode))
    }
    if validated.exhibitionDestination != baseProfile.exhibitionDestination {
      edits.append(.exhibitionDestination(validated.exhibitionDestination))
    }
    if validated.macOutput != baseProfile.macOutput {
      edits.append(.macOutput(validated.macOutput))
    }
    if validated.externalDisplayMode != baseProfile.externalDisplayMode {
      edits.append(.externalDisplayMode(validated.externalDisplayMode))
    }
    if validated.externalDisplayRotation != baseProfile.externalDisplayRotation {
      edits.append(.externalDisplayRotation(validated.externalDisplayRotation))
    }
    return RemoteProfilePatch(baseRevision: baseProfile.revision, edits: edits)
  }
}

public struct RemoteCommandRequest: Equatable, Sendable {
  public let header: RemoteMessageHeader
  public let command: RemoteCommandPayload

  public init(header: RemoteMessageHeader, command: RemoteCommandPayload) {
    self.header = header
    self.command = command
  }
}

public struct RemoteStatusSnapshot: Codable, Equatable, Sendable {
  public let reportedAt: Int64
  public let mode: AppMode
  public let savedProfile: KioskProfile?
  public let activeRevision: UInt64?
  public let macDisplays: [DisplayDescriptor]?
  public let mobileDisplays: MobileDisplayAvailability?

  public init(
    reportedAt: Int64, mode: AppMode, savedProfile: KioskProfile?,
    activeRevision: UInt64?, macDisplays: [DisplayDescriptor]? = nil,
    mobileDisplays: MobileDisplayAvailability? = nil
  ) {
    self.reportedAt = reportedAt
    self.mode = mode
    self.savedProfile = savedProfile
    self.activeRevision = activeRevision
    self.macDisplays = macDisplays
    self.mobileDisplays = mobileDisplays
  }

  public func reported(at timestamp: Int64) -> RemoteStatusSnapshot {
    RemoteStatusSnapshot(
      reportedAt: timestamp, mode: mode,
      savedProfile: savedProfile, activeRevision: activeRevision,
      macDisplays: macDisplays, mobileDisplays: mobileDisplays)
  }
}

public enum RemoteCommandRejection: String, Codable, Equatable, Sendable {
  case notAuthorized, expired, duplicate, busy, invalidState, storageFailed
  case revisionConflict, draftConflict, invalidProfile, outputUnavailable
}

public enum RemoteCommandOutcome: Codable, Equatable, Sendable {
  case succeeded(RemoteStatusSnapshot)
  case rejected(RemoteCommandRejection)
}

public struct RemoteCommandResult: Equatable, Sendable {
  public let header: RemoteMessageHeader
  public let outcome: RemoteCommandOutcome

  public init(header: RemoteMessageHeader, outcome: RemoteCommandOutcome) {
    self.header = header
    self.outcome = outcome
  }
}

public enum RemoteCommandPhase: Equatable, Sendable {
  case idle, sending, waiting, processed, rejected, failed, unknown
}

public struct RemoteOutgoingCommand: Equatable, Sendable {
  public let requestID: UUID
  public let targetID: UUID
  public let accountIdentifier: String
  public let command: RemoteCommandPayload
  public let deadline: Double
  public var phase: RemoteCommandPhase
  public var outcome: RemoteCommandOutcome?

  public init(
    requestID: UUID, targetID: UUID, accountIdentifier: String, deadline: Double,
    command: RemoteCommandPayload = .readStatus,
    phase: RemoteCommandPhase = .sending, outcome: RemoteCommandOutcome? = nil
  ) {
    self.requestID = requestID
    self.targetID = targetID
    self.accountIdentifier = accountIdentifier
    self.command = command
    self.deadline = deadline
    self.phase = phase
    self.outcome = outcome
  }
}
