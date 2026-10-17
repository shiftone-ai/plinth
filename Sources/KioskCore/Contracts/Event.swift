import Foundation

public enum Event: Equatable, Sendable {
  // Root requests and facts.
  case bootstrapped(profile: KioskProfile?, credentialsConfigured: Bool, displayCount: Int)
  case bootstrapRequested
  case bootstrapFailed(
    OperationToken, displayCount: Int, credentialsConfigured: Bool, profileCorrupt: Bool)
  case applicationDeactivated
  case applicationActivated
  case systemWillSleep
  case systemDidWake
  case startExhibitionRequested
  case webRestartExhibitionRequested
  case webStopExhibitionRequested
  case webResumeExhibitionRequested
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
  case catalogLoadRequested
  case catalogLoaded(OperationToken, SettingsCatalog)
  case catalogLoadFailed(OperationToken)
  case catalogRegisterRequested(id: UUID, name: String)
  case catalogRegistrationRequested(id: UUID, name: String, profile: KioskProfile)
  case catalogSelectRequested(UUID)
  case catalogSelectionOpened(CatalogEntry)
  case catalogSelectionDismissed
  case catalogApplyRequested
  case catalogSelectionApplied(CatalogEntry)
  case catalogRenameRequested(id: UUID, name: String)
  case catalogRenameConfirmed(UUID)
  case catalogRenameCancelled
  case catalogUpdateRequested(UUID)
  case catalogUpdateConfirmed(UUID)
  case catalogUpdateCancelled
  case catalogVisibilityRequested(id: UUID, visible: Bool)
  case catalogRemoveConfirmed(UUID)
  case catalogRemovePromptRequested(UUID)
  case catalogRemovePromptCancelled
  case catalogNameEdited(String)
  case catalogSelectionNameEdited(String)
  case catalogRegistrationSucceeded(UUID)
  case catalogPassphraseEdited(String)
  case catalogConfirmPassphraseEdited(String)
  case catalogPassphraseCleared
  case catalogExportRequested(ids: [UUID])
  case catalogExportOperationRequested(ids: [UUID], passphrase: String)
  case catalogExportPrepared(OperationToken, Data)
  case catalogExportFailed(OperationToken)
  case catalogExportDismissed
  case catalogFileExportCompleted(Bool)
  case catalogImportFileRequested(URL)
  case catalogImportOperationRequested(URL, passphrase: String)
  case catalogImportPreviewReady(OperationToken, [CatalogEntry])
  case catalogImportFailed(OperationToken)
  case catalogImportConfirmed(replacementIDs: [UUID])
  case catalogImportCancelled
  case catalogSaved(OperationToken, SettingsCatalog)
  case catalogSaveFailed(OperationToken)
  case catalogSyncEnableRequested
  case catalogSyncEnableConfirmed
  case catalogSyncEnableCancelled
  case catalogSyncDisableRequested
  case catalogSyncRetryRequested
  case catalogAccountChecked(OperationToken, String?)
  case catalogCloudStatus(OperationToken, CatalogSyncStatus)
  case catalogCloudChanges(OperationToken, String, [CatalogCloudChange])
  case catalogCloudAcknowledged(OperationToken, String, [UUID: UInt64])
  case catalogCloudDeletionsAcknowledged(OperationToken, String, [UUID])
  case catalogCloudAccountChanged(OperationToken)
  case catalogSharePromptRequested(UUID)
  case catalogSharePromptCancelled
  case catalogShareConfirmed(UUID)
  case catalogConflictResolved(UUID, useRemote: Bool)
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
  case initializeWebDraft(KioskProfile?)
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
  case webLoginRequested(password: String, candidate: String)
  case webLoginStatusRequested(String)
  case webAuthenticationVerified(String)
  case webSessionRequested(String, activity: Bool)
  case webServerStarted(OperationToken, WebServerEndpoint)
  case webServerFailed(OperationToken, WebServerFailure)
  case webServerStoppedUnexpectedly(WebServerFailure)
  case webServerAddressChanged(WebServerEndpoint)
  case localWebServerOriginsChanged([Origin])
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
  case invalidateWebAuthentication
  case cancelAuthentication
  case unrelatedFact

  public var requiresReply: Bool {
    switch self {
    case .startExhibitionRequested, .webRestartExhibitionRequested,
      .webStopExhibitionRequested, .webResumeExhibitionRequested,
      .unlockRequested, .unlockCancelled, .terminateRequested,
      .nativeInput, .externalWebControlRequested, .externalWebControlExecutionRequested,
      .externalMouseInput,
      .navigationRequested, .profileCommitRequested, .draftChanged, .draftEdited,
      .saveDraftRequested, .passcodeSubmitted, .cancelAuthentication, .configurePasscodeRequested,
      .passcodeEdited, .discardDraftRequested, .webCapabilityRequested, .addOriginRuleRequested,
      .removeOriginRuleRequested, .prepareExternalSceneRequested, .credentialConfigurationRequested,
      .biometricStatusRequested, .biometricChangeRequested, .biometricChangeCancelled,
      .biometricUnlockRequested, .biometricUnlockCancelled,
      .webLoginRequested, .webLoginStatusRequested, .webSessionRequested:
      true
    case .catalogLoadRequested, .catalogRegisterRequested, .catalogRegistrationRequested,
      .catalogSelectRequested, .catalogSelectionDismissed, .catalogApplyRequested,
      .catalogRenameRequested, .catalogRenameConfirmed, .catalogRenameCancelled,
      .catalogUpdateRequested, .catalogUpdateConfirmed, .catalogUpdateCancelled,
      .catalogVisibilityRequested, .catalogRemoveConfirmed,
      .catalogRemovePromptRequested, .catalogRemovePromptCancelled,
      .catalogNameEdited, .catalogSelectionNameEdited:
      true
    case .catalogPassphraseEdited, .catalogConfirmPassphraseEdited,
      .catalogExportRequested, .catalogExportOperationRequested,
      .catalogExportDismissed, .catalogFileExportCompleted,
      .catalogImportFileRequested, .catalogImportOperationRequested,
      .catalogImportConfirmed, .catalogImportCancelled:
      true
    case .catalogSyncEnableRequested, .catalogSyncEnableConfirmed,
      .catalogSyncEnableCancelled, .catalogSyncDisableRequested, .catalogSyncRetryRequested,
      .catalogSharePromptRequested, .catalogSharePromptCancelled,
      .catalogShareConfirmed, .catalogConflictResolved:
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
