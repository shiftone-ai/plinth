public enum NodeID: String, CaseIterable, Codable, Sendable {
  case root, platform, exhibition, webSurface, statusOverlay, idleClock
  case administration, unlock, settings, credentials, persistence, profileRepository,
    catalogRepository, cloudCatalog, diagnostics
  case navigationRules, interactionPolicy, resetPolicy

  public var parent: NodeID? {
    switch self {
    case .root: nil
    case .platform, .exhibition, .administration, .persistence: .root
    case .webSurface, .statusOverlay, .idleClock: .exhibition
    case .unlock, .settings, .credentials: .administration
    case .profileRepository, .catalogRepository, .cloudCatalog, .diagnostics: .persistence
    case .navigationRules, .interactionPolicy, .resetPolicy: .settings
    }
  }
}

public struct OperationToken: Hashable, Sendable {
  public let owner: NodeID
  public let ownerEpoch: UInt64
  public let operationID: UInt64
  public let webGeneration: UInt64?

  public init(
    owner: NodeID, ownerEpoch: UInt64 = 1, operationID: UInt64, webGeneration: UInt64? = nil
  ) {
    self.owner = owner
    self.ownerEpoch = ownerEpoch
    self.operationID = operationID
    self.webGeneration = webGeneration
  }
}

public struct EventEnvelope: Equatable, Sendable {
  public let eventID: UInt64
  public let source: NodeID
  public let sourceEpoch: UInt64
  public let timestamp: Double
  public let causationID: UInt64?
  public let event: Event

  public init(
    eventID: UInt64, source: NodeID, sourceEpoch: UInt64 = 1, timestamp: Double,
    causationID: UInt64? = nil, event: Event
  ) {
    self.eventID = eventID
    self.source = source
    self.sourceEpoch = sourceEpoch
    self.timestamp = timestamp
    self.causationID = causationID
    self.event = event
  }

  public func token(owner: NodeID, epoch: UInt64, generation: UInt64? = nil) -> OperationToken {
    OperationToken(owner: owner, ownerEpoch: epoch, operationID: eventID, webGeneration: generation)
  }
}
