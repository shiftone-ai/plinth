import KioskCore

public nonisolated struct DiagnosticRecord: Equatable, Sendable {
  public enum Kind: String, Sendable {
    case bootstrap, lifecycle, administration, authentication, navigation, web, deadline, other
  }
  public let kind: Kind
  public let eventID: UInt64
  public let source: NodeID
  public let handler: NodeID?
  public let rejection: RejectionReason?
  public let mode: AppMode
  public let phase: ExhibitionPhase
  public let generation: UInt64
  public let operationID: UInt64?
  public let retryAttempt: Int
  public let profileRevision: UInt64?

  public init?(event: Event, report: DispatchReport, snapshot: TreeSnapshot) {
    switch event {
    case .nativeInput, .visitorActivity, .passcodeEdited, .draftChanged, .draftEdited,
      .nativePointerMoved, .externalMouseInput, .externalWebControlRequested,
      .externalWebControlExecutionRequested:
      return nil
    case .bootstrapRequested, .bootstrapFailed, .bootstrapped: kind = .bootstrap
    case .applicationDeactivated, .systemWillSleep, .displayCountChanged, .presentationApplied,
      .presentationReleased, .presentationFailed:
      kind = .lifecycle
    case .unlockRequested, .unlockCancelled, .openUnlock, .passcodeSubmitted, .credentialVerified,
      .configurePasscodeRequested, .credentialConfigurationRequested, .credentialConfigured,
      .clearPasscode, .cancelAuthentication,
      .authenticationVerified:
      kind = .authentication
    case .navigationRequested, .webCapabilityRequested: kind = .navigation
    case .webCommitted, .webNavigationBegan, .webFinished, .webFailed, .webProcessTerminated,
      .surfaceCreated,
      .surfaceReleased:
      kind = .web
    case .idleDeadlineReached, .retryDeadlineReached, .unlockDeadlineReached: kind = .deadline
    case .startExhibitionRequested, .terminateRequested, .profileCommitRequested, .profileSaved,
      .profileSaveFailed, .openAdministration, .saveDraftRequested, .discardDraftRequested,
      .addOriginRuleRequested, .removeOriginRuleRequested, .draftSaveSucceeded, .draftSaveFailed:
      kind = .administration
    default: kind = .other
    }
    eventID = report.eventID
    source = report.source
    handler = report.handler
    if case .rejected(let reason) = report.reply {
      rejection = reason
    } else if case .navigation(.cancel(let reason)) = report.reply {
      rejection = reason
    } else {
      rejection = nil
    }
    mode = snapshot.root.mode
    phase = snapshot.exhibition.phase
    generation = snapshot.exhibition.generation
    operationID = snapshot.exhibition.operation?.operationID
    retryAttempt = snapshot.exhibition.retryAttempt
    profileRevision = snapshot.root.activeProfile?.revision ?? snapshot.root.savedProfile?.revision
  }
}
