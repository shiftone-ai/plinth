import OSLog

@MainActor
public protocol DiagnosticPort: AnyObject {
  func record(_ record: DiagnosticRecord)
}

@MainActor
public final class DiagnosticLogAdapter: DiagnosticPort {
  private let logger = Logger(subsystem: "ai.shiftone.plinth", category: "runtime")
  public init() {}
  public func record(_ record: DiagnosticRecord) {
    logger.notice(
      "event=\(record.kind.rawValue, privacy: .public) id=\(record.eventID) source=\(record.source.rawValue, privacy: .public) handler=\(record.handler?.rawValue ?? "none", privacy: .public) rejection=\(record.rejection?.rawValue ?? "none", privacy: .public) mode=\(record.mode.rawValue, privacy: .public) phase=\(record.phase.rawValue, privacy: .public) generation=\(record.generation) operation=\(record.operationID ?? 0) attempt=\(record.retryAttempt) revision=\(record.profileRevision ?? 0)"
    )
  }
}
