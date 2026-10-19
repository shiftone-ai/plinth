import Foundation

public enum AppMode: String, Codable, Equatable, Sendable {
  case bootstrapping, administration, enteringKiosk, exhibiting, unlocking, leavingKiosk, safeHold,
    paused, terminating
}

public enum ForegroundResumeState: Equatable, Sendable {
  case none, awaitingActivation, awaitingDisplay, awaitingStop
}

public enum WebExitDestination: Equatable, Sendable {
  case restart, paused
}

public struct RootState: Equatable, Sendable {
  public var credentialOperation: OperationToken?
  public var credentialConfigurationFailed = false
  public var biometricStatus: BiometricStatus?
  public var biometricStatusOperation: OperationToken?
  public var biometricOperation: OperationToken?
  public var biometricChangeFailed = false
  public var biometricUnlockOperation: OperationToken?
  public var biometricUnlockFailed = false
  public var biometricEnrollmentChanged = false
  public var bootstrapOperation: OperationToken?
  public var bootstrapReadFailed = false
  public var unlockTimeoutOperation: OperationToken?
  public var unlockDeadline: Double?
  public var epoch: UInt64 = 1
  public var mode: AppMode = .bootstrapping
  public var savedProfile: KioskProfile?
  public var remote = RemoteManagementState()
  public var profileCorrupt = false
  public var webSession: WebAdministrationSession?
  public var webServerOperation: OperationToken?
  public var pendingWebServerEndpoint: WebServerEndpoint?
  public var webServerRunning = false
  public var webServerURL: String?
  public var localWebServerOrigins: [Origin] = []
  public var webServerFailure: WebServerFailure?
  public var webExitDestination: WebExitDestination?
  public var webRestartInProgress = false
  public var webRestartFailed = false
  public var activeProfile: KioskProfile?
  public var catalog = SettingsCatalog()
  public var catalogLoaded = false
  public var catalogLoadFailed = false
  public var catalogCorrupt = false
  public var catalogRecoveryPending = false
  public var catalogLoadOperation: OperationToken?
  public var catalogSaveOperation: OperationToken?
  public var pendingCatalog: SettingsCatalog?
  public var pendingCatalogRegistrationID: UUID?
  public var catalogRemovalCandidateID: UUID?
  public var catalogRenameCandidate: CatalogRenameCandidate?
  public var catalogUpdateCandidateID: UUID?
  public var catalogSaveFailed = false
  public var catalogExportCandidateIDs: [UUID]?
  public var catalogExportOperation: OperationToken?
  public var catalogExportData: Data?
  public var catalogExportFailed = false
  public var catalogImportOperation: OperationToken?
  public var catalogImportSelectedURL: URL?
  public var catalogImportPreview: [CatalogEntry]?
  public var catalogImportFailed = false
  public var pendingCatalogImport = false
  public var catalogSyncStatus: CatalogSyncStatus = .disabled
  public var catalogCloudAvailable = true
  public var catalogAccountCheckOperation: OperationToken?
  public var catalogCloudSessionOperation: OperationToken?
  public var catalogSyncConsentPending = false
  public var catalogShareCandidateID: UUID?
  public var pendingCatalogPublishes = true
  public var catalogCheckAfterSave = false
  public var catalogStartAfterSave = false
  public var queuedCatalogCloudChanges: [CatalogCloudChange] = []
  public var queuedCatalogAcknowledgements: [UUID: UInt64] = [:]
  public var queuedCatalogDeletionAcknowledgements: Set<UUID> = []
  public var catalogQueuedReconcileAttempted = false
  public var catalogCloudReadyAfterSave = false
  public var credentialsConfigured = false
  public var displayCount = 1
  public var mobileDisplays: MobileDisplayAvailability?
  public var mobileForeground = true
  public var macDisplays: [DisplayDescriptor]?
  public var externalSceneOperation: OperationToken?
  public var externalScenePreparationFailed = false
  public var externalPointer: SurfacePoint?
  public var externalButtonDown = false
  public var externalPressGeneration: UInt64?
  public var externalMouseConnected = false
  public var externalPointerLocked = false
  public var pointerCaptureFailed = false
  public var foregroundResume: ForegroundResumeState = .none
  public var pointerCaptureOperation: OperationToken?

  public func canPresent(_ profile: KioskProfile) -> Bool {
    if let macDisplays {
      return DisplaySelection.select(profile.macOutput ?? .init(), from: macDisplays) != nil
    }
    if let mobileDisplays {
      if profile.exhibitionDestination != .externalDisplay { return mobileDisplays.deviceAvailable }
      guard mobileDisplays.externalAvailable && mobileDisplays.supportsExternalDisplay else {
        return false
      }
      if let mode = profile.externalDisplayMode {
        return mobileDisplays.externalDisplayOnly && mobileDisplays.displayModes.contains(mode)
      }
      return true
    }
    return displayCount > 0 && profile.exhibitionDestination != .externalDisplay
  }

  public func remoteOutputAvailable(_ profile: KioskProfile) -> Bool {
    if let macDisplays {
      guard let selectedID = profile.macOutput?.displayID else { return canPresent(profile) }
      return macDisplays.contains(where: { $0.id == selectedID }) && canPresent(profile)
    }
    if let mobileDisplays {
      if profile.exhibitionDestination == .externalDisplay {
        guard mobileDisplays.externalAvailable,
          mobileDisplays.supportsExternalDisplay
        else { return false }
        if let mode = profile.externalDisplayMode,
          !mobileDisplays.displayModes.contains(mode)
        {
          return false
        }
      }
      return canPresent(profile)
    }
    return canPresent(profile)
  }
  public func catalogEntryAvailable(_ entry: CatalogEntry) -> Bool {
    entry.scope == .device
      || (catalogCloudAvailable && catalog.syncEnabled
        && entry.accountIdentifier == catalog.accountIdentifier
        && catalogSyncStatus != .checking
        && catalogSyncStatus != .accountChanged
        && catalogSyncStatus != .signInRequired)
  }

  public func catalogConflictAvailable(_ conflict: CatalogConflict) -> Bool {
    guard catalogCloudAvailable, catalog.syncEnabled,
      let accountID = catalog.accountIdentifier,
      catalogSyncStatus != .checking, catalogSyncStatus != .accountChanged,
      catalogSyncStatus != .signInRequired
    else { return false }
    return catalog.conflictBelongsToAccount(conflict, accountIdentifier: accountID)
  }

  public var catalogCanShare: Bool {
    guard catalog.syncEnabled, catalog.accountIdentifier != nil,
      catalogCloudSessionOperation != nil
    else { return false }
    switch catalogSyncStatus {
    case .ready, .pending, .offline: return true
    case .disabled, .checking, .signInRequired, .accountChanged, .failed: return false
    }
  }
  public var administratorSession = false
  public var presentationAcquired = false
  public var presentationOperation: OperationToken?
  public var presentationAcquisition: OperationToken?
  public var unlockID: UInt64?
  public var unlockReturnMode: AppMode?
  public var saveOperation: OperationToken?
  public var informationPageOperation: OperationToken?
  public var licenseSheetPresented = false
  public var pendingProfile: KioskProfile?
  public var input = InputState()
  public init() {}
}

public enum WebServerFailure: Error, Equatable, Sendable {
  case portInUse, unavailable
}

public struct WebAdministrationSession: Equatable, Sendable {
  public let token: String
  public let createdAt: Double
  public var lastActivityAt: Double

  public init(token: String, createdAt: Double) {
    self.token = token
    self.createdAt = createdAt
    self.lastActivityAt = createdAt
  }

  public func isValid(at time: Double) -> Bool {
    time >= lastActivityAt && time - lastActivityAt < 15 * 60
      && time >= createdAt && time - createdAt < 8 * 60 * 60
  }
}

public struct MobileDisplayAvailability: Codable, Equatable, Sendable {
  public let deviceAvailable: Bool
  public let externalAvailable: Bool
  public let supportsExhibitionWindow: Bool
  public let externalDisplayOnly: Bool
  public let supportsExternalDisplay: Bool
  public let externalConnected: Bool
  public let displayModes: [ExternalDisplayMode]
  public let currentMode: ExternalDisplayMode?
  public var canPrepareExhibitionWindow: Bool {
    supportsExternalDisplay && supportsExhibitionWindow && !externalAvailable
      && !externalDisplayOnly
  }
  public init(
    deviceAvailable: Bool, externalAvailable: Bool, supportsExhibitionWindow: Bool = true,
    externalDisplayOnly: Bool = false, supportsExternalDisplay: Bool = true,
    externalConnected: Bool? = nil, displayModes: [ExternalDisplayMode] = [],
    currentMode: ExternalDisplayMode? = nil
  ) {
    self.deviceAvailable = deviceAvailable
    self.externalAvailable = externalAvailable
    self.supportsExhibitionWindow = supportsExhibitionWindow
    self.externalDisplayOnly = externalDisplayOnly
    self.supportsExternalDisplay = supportsExternalDisplay
    self.externalConnected = externalConnected ?? externalAvailable
    self.displayModes = displayModes
    self.currentMode = currentMode
  }
}
