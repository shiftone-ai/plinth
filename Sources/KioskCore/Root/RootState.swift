public enum AppMode: String, Equatable, Sendable {
  case bootstrapping, administration, enteringKiosk, exhibiting, unlocking, leavingKiosk, safeHold,
    terminating
}

public enum ForegroundResumeState: Equatable, Sendable {
  case none, awaitingActivation, awaitingDisplay, awaitingStop
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
  public var unlockTimeoutOperation: OperationToken?
  public var unlockDeadline: Double?
  public var epoch: UInt64 = 1
  public var mode: AppMode = .bootstrapping
  public var savedProfile: KioskProfile?
  public var activeProfile: KioskProfile?
  public var credentialsConfigured = false
  public var displayCount = 1
  public var mobileDisplays: MobileDisplayAvailability?
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
  public var administratorSession = false
  public var presentationAcquired = false
  public var presentationOperation: OperationToken?
  public var presentationAcquisition: OperationToken?
  public var unlockID: UInt64?
  public var unlockReturnMode: AppMode?
  public var saveOperation: OperationToken?
  public var pendingProfile: KioskProfile?
  public var input = InputState()
  public init() {}
}

public struct MobileDisplayAvailability: Equatable, Sendable {
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
