import Foundation
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
  public let webServerURL: String?
}

public struct SettingsProps: Equatable, Sendable {
  public let catalog: CatalogProps
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
  public let catalogOutputUnavailable: Bool
  public let canStart: Bool
  public let saving: Bool
  public let canPrepareExternalScene: Bool
  public let externalScenePreparationFailed: Bool
  public let macDisplays: [DisplayDescriptor]?
  public let showsExhibitionWindowPreparation: Bool
  public let supportsExternalDisplay: Bool
  public let externalDisplayModes: [ExternalDisplayMode]
  public let externalDisplayCurrentMode: ExternalDisplayMode?
  public let webServerURL: String?
  public let webServerFailure: WebServerFailure?
}

public enum CatalogDisplayValue: Equatable, Sendable {
  case text(String)
  case localized(String)
  case absent
}

public struct CatalogDifference: Equatable, Sendable, Identifiable {
  public let labelKey: String
  public let current: CatalogDisplayValue
  public let selected: CatalogDisplayValue
  public var id: String { labelKey }
}

public enum CatalogImportMatch: Equatable, Sendable {
  case alreadyPresent, separateCopy, sameName
}

public struct CatalogProps: Equatable, Sendable {
  public let syncEnabled: Bool
  public let syncStatus: CatalogSyncStatus
  public let syncConsentPending: Bool
  public let shareCandidate: CatalogEntry?
  public let conflicts: [CatalogConflict]
  public let conflictDifferences: [UUID: [CatalogDifference]]
  public let visibleEntries: [CatalogEntry]
  public let hiddenEntries: [CatalogEntry]
  public let loaded: Bool
  public let loadFailed: Bool
  public let saving: Bool
  public let saveFailed: Bool
  public let nameDraft: String
  public let canRegister: Bool
  public let selectedEntry: CatalogEntry?
  public let selectedNameDraft: String
  public let renameCandidate: CatalogRenameCandidate?
  public let updateCandidateID: UUID?
  public let differences: [CatalogDifference]
  public let contents: [CatalogDifference]
  public let canApply: Bool
  public let canManage: Bool
  public let canShare: Bool
  public let canRename: Bool
  public let canUpdate: Bool
  public let removalCandidate: CatalogEntry?
  public let passphrase: String
  public let confirmPassphrase: String
  public let canExport: Bool
  public let canImport: Bool
  public let exporting: Bool
  public let exportData: Data?
  public let exportFailed: Bool
  public let importing: Bool
  public let importPreview: [CatalogEntry]?
  public let importMatches: [UUID: CatalogImportMatch]
  public let importContents: [UUID: [CatalogDifference]]
  public let importFailed: Bool
  public let canConfirmImport: Bool
}

public struct SettingsValidationMessage: Equatable, Encodable, Sendable, Identifiable {
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

/// Credentials and credential controls never cross the remote management boundary.
public struct WebAdministrationProps: Encodable, Equatable, Sendable {
  public let mode: AppMode
  public let savedProfile: KioskProfile?
  public let draft: ProfileDraft?
  public let saving: Bool
  public let saveFailed: Bool
  public let canSave: Bool
  public let validationMessages: [SettingsValidationMessage]
  public let hasUnsavedDraft: Bool
  public let webRestartFailed: Bool
  public let macDisplays: [DisplayDescriptor]?
  public let mobileOutputAvailable: Bool
  public let supportsExternalDisplay: Bool
  public let externalDisplayModes: [ExternalDisplayMode]
  public let showsExhibitionWindowPreparation: Bool
}
