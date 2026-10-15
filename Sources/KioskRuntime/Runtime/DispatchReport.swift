import KioskCore

public nonisolated struct DispatchReport: Equatable, Sendable {
  public let eventID: UInt64
  public let source: NodeID
  public let path: [NodeID]
  public let handler: NodeID?
  public let reply: Reply?
  public let causationID: UInt64?
}
