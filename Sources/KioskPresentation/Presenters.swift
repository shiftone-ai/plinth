import KioskCore

public enum Presenters {
  public static func root(_ state: RootState) -> RootProps {
    RootProps(
      mode: state.mode, showsAdministration: state.mode == .administration,
      showsUnlock: state.mode == .unlocking,
      exhibitionDestination: state.activeProfile?.exhibitionDestination ?? .device,
      administrationAvailable: state.mobileDisplays?.deviceAvailable ?? true,
      externalDisplayOnly: state.mobileDisplays?.externalDisplayOnly == true,
      externalDisplayRotation: state.activeProfile?.exhibitionDestination == .externalDisplay
        ? state.activeProfile?.externalDisplayRotation ?? .standard : .standard,
      externalPointer: state.mode == .exhibiting ? state.externalPointer : nil,
      externalAllowsDrag: state.activeProfile?.interaction.allowsDrag == true,
      externalPointerLocked: state.externalPointerLocked,
      showsPointerSetupHelp: state.mode == .safeHold && state.pointerCaptureFailed)
  }

  public static func settings(_ root: RootState, _ administration: AdministrationState)
    -> SettingsProps
  {
    SettingsProps(
      draft: administration.draft
        ?? ProfileDraft(profile: KioskProfile(startURL: "", navigation: .init(rules: []))),
      passcode: administration.passcode,
      credentialsConfigured: root.credentialsConfigured,
      configuringCredential: root.credentialOperation != nil,
      credentialConfigurationFailed: root.credentialConfigurationFailed,
      biometricLabelKey: biometricLabel(root.biometricStatus),
      biometricUnavailableKey: biometricUnavailable(root.biometricStatus),
      biometricEnabled: root.biometricStatus?.enabled == true,
      biometricChanging: root.biometricOperation != nil,
      canChangeBiometric: canChangeBiometric(root),
      biometricChangeFailed: root.biometricChangeFailed,
      biometricEnrollmentChanged: root.biometricEnrollmentChanged,
      saveFailed: administration.saveFailed,
      validationMessages: settingsValidation(root, administration),
      startURL: administration.draft?.profile.startURL ?? "",
      automaticallyAllowedAddress: administration.draft?.profile.automaticallyAllowedOrigin.map {
        let defaultPort = $0.scheme == "https" ? 443 : 80
        return $0.port == defaultPort
          ? String($0.urlString.dropLast(":\($0.port)".count)) : $0.urlString
      },
      idleTimeout: administration.draft?.idleTimeoutText ?? "",
      canSave: root.mode == .administration && !administration.saving
        && ProfileRevision.next(after: root.savedProfile?.revision) != nil
        && administration.hasUnsavedDraft && administration.draft?.validatedProfile != nil,
      canStart: root.mode == .administration && root.credentialsConfigured
        && root.savedProfile.map(root.canPresent) == true
        && !administration.hasUnsavedDraft && root.saveOperation == nil
        && root.credentialOperation == nil && root.biometricOperation == nil
        && root.externalSceneOperation == nil
        && root.savedProfile?.validationIssues.isEmpty == true,
      saving: administration.saving,
      canPrepareExternalScene: root.mode == .administration
        && root.mobileDisplays?.canPrepareExhibitionWindow == true
        && root.externalSceneOperation == nil,
      externalScenePreparationFailed: root.externalScenePreparationFailed,
      macDisplays: root.macDisplays,
      showsExhibitionWindowPreparation: root.mobileDisplays?.canPrepareExhibitionWindow == true,
      supportsExternalDisplay: root.mobileDisplays?.supportsExternalDisplay == true,
      externalDisplayModes: root.mobileDisplays?.displayModes ?? [],
      externalDisplayCurrentMode: root.mobileDisplays?.currentMode
    )
  }

  private static func biometricLabel(_ status: BiometricStatus?) -> String {
    switch status?.availability {
    case .available(.faceID): "Unlock with Face ID"
    case .available(.touchID): "Unlock with Touch ID"
    default: "Biometric unlock"
    }
  }

  private static func biometricUnavailable(_ status: BiometricStatus?) -> String? {
    switch status?.availability {
    case nil: "Checking biometrics"
    case .available: nil
    case .unavailable(.notAvailable): "Biometrics are not available on this device"
    case .unavailable(.notEnrolled): "Set up Face ID or Touch ID on this device first"
    case .unavailable(.lockedOut): "Biometrics are locked. Unlock the device and try again"
    case .unavailable(.passcodeNotSet): "Set a device passcode to use biometrics"
    case .unavailable(.storageUnavailable): "Biometric settings are unavailable"
    case .unavailable(.disconnected): "Touch ID keyboard is disconnected"
    case .unavailable(.notPaired): "Touch ID keyboard is not paired"
    }
  }

  private static func canChangeBiometric(_ root: RootState) -> Bool {
    guard root.mode == .administration, root.credentialsConfigured,
      root.biometricOperation == nil, let status = root.biometricStatus
    else { return false }
    if status.enabled { return true }
    if case .available = status.availability { return true }
    return false
  }

  private static func validationMessage(_ issue: ProfileIssue) -> String {
    switch issue {
    case .unsupportedSchema: "Could not read the settings format"
    case .invalidRevision: "Could not read settings"
    case .invalidNavigationRules: "Check the domain"
    case .homeNotAllowed: "The start URL is not allowed by the navigation rules"
    case .invalidIdleTimeout: "Enter an idle time greater than zero"
    case .invalidRecoveryPolicy: "Check retry count and interval"
    case .invalidDisplayMode: "Check the resolution"
    }
  }

  private static func settingsValidation(_ root: RootState, _ administration: AdministrationState)
    -> [SettingsValidationMessage]
  {
    var messages = (administration.draft?.validationIssues ?? []).map {
      SettingsValidationMessage(id: $0, textKey: validationMessage($0))
    }
    if ProfileRevision.next(after: root.savedProfile?.revision) == nil {
      messages.removeAll { $0.id == .invalidRevision }
      messages.append(.init(id: .invalidRevision, textKey: "Settings have reached the save limit"))
    }
    return messages
  }

  public static func web(_ root: RootState, _ exhibition: ExhibitionState) -> WebSurfaceProps {
    WebSurfaceProps(
      generation: exhibition.generation,
      acceptsInput: root.mode == .exhibiting && exhibition.inputAvailable,
      phase: exhibition.phase, pageLoad: exhibition.pageLoad)
  }

  public static func unlock(
    _ root: RootState, _ administration: AdministrationState, now: Double
  ) -> UnlockProps {
    let biometricLabelKey: String?
    if root.biometricStatus?.enabled == true {
      switch root.biometricStatus?.availability {
      case .available(.faceID): biometricLabelKey = "Unlock with Face ID"
      case .available(.touchID): biometricLabelKey = "Unlock with Touch ID"
      default: biometricLabelKey = nil
      }
    } else {
      biometricLabelKey = nil
    }
    return UnlockProps(
      passcode: administration.passcode,
      failedAttempts: administration.failedAttempts,
      verifying: administration.verification != nil,
      cooldownRemaining: max(0, (administration.cooldownUntil ?? now) - now),
      biometricLabelKey: biometricLabelKey,
      biometricVerifying: root.biometricUnlockOperation != nil,
      biometricFailed: root.biometricUnlockFailed)
  }
}
