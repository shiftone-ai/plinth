public enum Event: Equatable, Sendable {
  // Root requests and facts.
  case bootstrapped(profile: KioskProfile?, credentialsConfigured: Bool, displayCount: Int)
  case bootstrapRequested
  case bootstrapFailed(OperationToken, displayCount: Int)
  case applicationDeactivated
  case applicationActivated
  case systemWillSleep
  case startExhibitionRequested
  case unlockRequested
  case unlockCancelled
  case unlockDeadlineReached(OperationToken)
  case terminateRequested
  case displayCountChanged(Int)
  case mobileDisplaysChanged(MobileDisplayAvailability)
  case macDisplaysChanged([DisplayDescriptor])
  case prepareExternalSceneRequested
  case externalScenePrepared(OperationToken)
  case externalScenePreparationFailed(OperationToken)
  case nativeInput(NativeInput, InputScope)
  case externalWebControlRequested(ExternalWebControl, generation: UInt64)
  case externalWebControlExecutionRequested(OperationToken)
  case externalWebControlDeliveryFailed(OperationToken)
  case externalMouseAvailabilityChanged(Bool)
  case externalPointerCaptureChanged(locked: Bool)
  case externalPointerCaptureCompleted(OperationToken, succeeded: Bool)
  case externalMouseInput(ExternalMouseInput, generation: UInt64)
  case nativePointerMoved(SurfacePoint)
  case nativePointerConstraintFailed
  case presentationApplied(OperationToken)
  case presentationFailed(OperationToken)
  case presentationReleased(OperationToken)
  case exhibitionReady
  case exhibitionStopped
  case exhibitionUnavailable
  case authenticationVerified(unlockID: UInt64)
  case profileCommitRequested(KioskProfile)
  case profileSaved(OperationToken, KioskProfile)
  case profileSaveFailed(OperationToken)
  // Exhibition controls and adapter facts.
  case activateExhibition(KioskProfile)
  case stopExhibition
  case resetExhibition(ResetMode)
  case visitorActivity
  case surfaceCreated(OperationToken)
  case surfaceReleased(OperationToken)
  case navigationRequested(
    url: String, generation: UInt64, mainFrame: Bool, newWindow: Bool, isGET: Bool,
    supportedContent: Bool = true)
  case webCommitted(OperationToken, url: String)
  case webNavigationBegan(OperationToken)
  case webFinished(OperationToken)
  case webFailed(OperationToken, WebFailure)
  case webProcessTerminated(generation: UInt64)
  case webCapabilityRequested(WebCapability, generation: UInt64)
  case idleDeadlineReached(OperationToken)
  case retryDeadlineReached(OperationToken)
  // Administration controls and adapter facts.
  case openAdministration(KioskProfile?)
  case draftChanged(ProfileDraft)
  case draftEdited(ProfileDraftEdit)
  case saveDraftRequested
  case discardDraftRequested
  case addOriginRuleRequested
  case removeOriginRuleRequested(UInt64)
  case draftSaveSucceeded(KioskProfile)
  case draftSaveFailed
  case openUnlock(unlockID: UInt64)
  case passcodeSubmitted
  case credentialVerified(OperationToken, succeeded: Bool)
  case configurePasscodeRequested
  case credentialConfigurationRequested(String)
  case credentialConfigured(OperationToken, succeeded: Bool)
  case biometricStatusRequested
  case biometricStatusRead(OperationToken, BiometricStatus)
  case biometricChangeRequested(Bool)
  case biometricChangeCompleted(OperationToken, BiometricStatus, BiometricChangeOutcome)
  case biometricChangeCancelled
  case biometricUnlockRequested
  case biometricUnlockCancelled
  case biometricUnlockCompleted(OperationToken, BiometricStatus, BiometricUnlockOutcome)
  case biometricAuthenticationVerified
  case passcodeEdited(String)
  case clearPasscode
  case cancelAuthentication
  case unrelatedFact

  public var requiresReply: Bool {
    switch self {
    case .startExhibitionRequested, .unlockRequested, .unlockCancelled, .terminateRequested,
      .nativeInput, .externalWebControlRequested, .externalWebControlExecutionRequested,
      .externalMouseInput,
      .navigationRequested, .profileCommitRequested, .draftChanged, .draftEdited,
      .saveDraftRequested, .passcodeSubmitted, .cancelAuthentication, .configurePasscodeRequested,
      .passcodeEdited, .discardDraftRequested, .webCapabilityRequested, .addOriginRuleRequested,
      .removeOriginRuleRequested, .prepareExternalSceneRequested, .credentialConfigurationRequested,
      .biometricStatusRequested, .biometricChangeRequested, .biometricChangeCancelled,
      .biometricUnlockRequested, .biometricUnlockCancelled:
      true
    default: false
    }
  }
}

public enum WebCapability: String, CaseIterable, Sendable {
  case download, fileSelection, mediaCapture, geolocation, alert, confirm, prompt,
    httpAuthentication
}

public enum WebFailure: Equatable, Sendable {
  case network, timeout, processTerminated, tls, policyDenied
  public var canRetry: Bool {
    switch self {
    case .network, .timeout, .processTerminated: true
    case .tls, .policyDenied: false
    }
  }
}
