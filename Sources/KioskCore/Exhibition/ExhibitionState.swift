public enum ExhibitionPhase: String, Sendable {
  case inactive, preparing, ready, quiescing, recreatingSurface, loadingHome, recovering,
    unavailable
}

public enum PageLoadPhase: String, Sendable { case loading, settled }

public struct ExhibitionState: Equatable, Sendable {
  public var epoch: UInt64 = 1
  public var phase: ExhibitionPhase = .inactive
  public var pageLoad: PageLoadPhase = .settled
  public var profile: KioskProfile?
  public var generation: UInt64 = 0
  public var operation: OperationToken?
  public var releaseOperation: OperationToken?
  public var idleOperation: OperationToken?
  public var retryOperation: OperationToken?
  public var idleDeadline: Double?
  public var retryDeadline: Double?
  public var retryDue = false
  public var retryAttempt = 0
  public var surfaceExists = false
  public var stopping = false
  public var resetMode: ResetMode = .newVisitorSession
  public var currentURL: String?
  public var inputAvailable: Bool { phase == .ready }
  public init() {}
}
