import KioskCore

public struct RootProps: Equatable, Sendable {
  public let mode: AppMode
  public let showsAdministration: Bool
  public let showsUnlock: Bool
  public let exhibitionDestination: ExhibitionDestination
  public let administrationAvailable: Bool
  public let externalDisplayOnly: Bool
  public let externalDisplayRotation: ExternalDisplayRotation
  public let externalPointer: SurfacePoint?
  public let externalAllowsDrag: Bool
  public let externalPointerLocked: Bool
  public let showsPointerSetupHelp: Bool
}

public struct SettingsProps: Equatable, Sendable {
  public let draft: ProfileDraft
  public let passcode: String
  public let credentialsConfigured: Bool
  public let configuringCredential: Bool
  public let credentialConfigurationFailed: Bool
  public let biometricLabelKey: String
  public let biometricUnavailableKey: String?
  public let biometricEnabled: Bool
  public let biometricChanging: Bool
  public let canChangeBiometric: Bool
  public let biometricChangeFailed: Bool
  public let biometricEnrollmentChanged: Bool
  public let saveFailed: Bool
  public let validationMessages: [SettingsValidationMessage]
  public let startURL: String
  public let automaticallyAllowedAddress: String?
  public let idleTimeout: String
  public let canSave: Bool
  public let canStart: Bool
  public let saving: Bool
  public let canPrepareExternalScene: Bool
  public let externalScenePreparationFailed: Bool
  public let macDisplays: [DisplayDescriptor]?
  public let showsExhibitionWindowPreparation: Bool
  public let supportsExternalDisplay: Bool
  public let externalDisplayModes: [ExternalDisplayMode]
  public let externalDisplayCurrentMode: ExternalDisplayMode?
}

public struct SettingsValidationMessage: Equatable, Sendable, Identifiable {
  public let id: ProfileIssue
  public let textKey: String
}

public struct WebSurfaceProps: Equatable, Sendable {
  public let generation: UInt64
  public let acceptsInput: Bool
  public let phase: ExhibitionPhase
  public let pageLoad: PageLoadPhase
}

public struct UnlockProps: Equatable, Sendable {
  public let passcode: String
  public let failedAttempts: Int
  public let verifying: Bool
  public let cooldownRemaining: Double
  public let biometricLabelKey: String?
  public let biometricVerifying: Bool
  public let biometricFailed: Bool
}
