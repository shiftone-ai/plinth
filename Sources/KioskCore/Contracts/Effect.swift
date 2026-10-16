public struct Effect: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case bootstrap
    case applyPresentation(PresentationRequest)
    case releasePresentation
    case prepareExternalScene
    case createSurface(ResetMode, interaction: InteractionPolicy = .init())
    case releaseSurface(generation: UInt64)
    case load(String)
    case controlExternalWeb(ExternalWebControl)
    case captureExternalPointer
    case releaseExternalPointer
    case confineNativePointer(SurfacePoint)
    case scheduleIdle(deadline: Double)
    case scheduleRetry(deadline: Double)
    case scheduleUnlockTimeout(deadline: Double)
    case verifyPasscode(String)
    case configurePasscode(String)
    case readBiometricStatus
    case changeBiometricUnlock(Bool)
    case performBiometricUnlock
    case saveProfile(KioskProfile)
    case startWebServer
    case stopWebServer
    case cancelOperation(OperationToken)
  }
  public let token: OperationToken
  public let kind: Kind
  public init(_ token: OperationToken, _ kind: Kind) {
    self.token = token
    self.kind = kind
  }
}
