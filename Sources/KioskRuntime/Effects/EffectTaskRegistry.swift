import KioskCore

@MainActor
public final class EffectTaskRegistry {
  private struct Record {
    let task: Task<Void, Never>
    var valid: Bool
  }
  private var records: [OperationToken: Record] = [:]
  public var pendingCount: Int { records.count }
  public init() {}

  public func start(
    _ token: OperationToken, operation: @escaping @MainActor () async -> Event?,
    completion: @escaping @MainActor (Event) -> Void
  ) {
    precondition(records[token] == nil, "An operation token may be registered only once")
    let task = Task { [weak self] in
      guard self?.records[token]?.valid == true, !Task.isCancelled else {
        self?.records.removeValue(forKey: token)
        return
      }
      let result = await operation()
      guard let self, let record = self.records.removeValue(forKey: token), record.valid else {
        return
      }
      if let result { completion(result) }
    }
    records[token] = Record(task: task, valid: true)
  }

  public func cancel(_ token: OperationToken) {
    guard var record = records[token] else { return }
    record.valid = false
    records[token] = record
    record.task.cancel()
  }

  public func cancelAll() {
    let tokens = Array(records.keys)
    for token in tokens { cancel(token) }
  }

  public func waitForOperation(_ token: OperationToken) async {
    if let task = records[token]?.task { await task.value }
  }
}
