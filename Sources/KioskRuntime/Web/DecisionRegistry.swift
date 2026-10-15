import KioskCore

/// Native callbacks stay on MainActor and are removed before they are invoked.
@MainActor
public final class DecisionRegistry {
  private struct Entry {
    let generation: UInt64
    let reply: @MainActor (NavigationDecision) -> Void
  }
  private var entries: [UInt64: Entry] = [:]
  private var nextID: UInt64 = 0
  private var closed = false
  public var pendingCount: Int { entries.count }
  public init() {}

  @discardableResult
  public func register(generation: UInt64, reply: @escaping @MainActor (NavigationDecision) -> Void)
    -> UInt64
  {
    nextID += 1
    let id = nextID
    if closed {
      reply(.cancel(.staleOperation))
    } else {
      entries[id] = Entry(generation: generation, reply: reply)
    }
    return id
  }

  @discardableResult
  public func resolve(_ id: UInt64, generation: UInt64, decision: NavigationDecision) -> Bool {
    guard let entry = entries.removeValue(forKey: id) else { return false }
    entry.reply(entry.generation == generation && !closed ? decision : .cancel(.staleOperation))
    return true
  }

  public func close() {
    closed = true
    let pending = entries
    entries.removeAll()
    for entry in pending.values { entry.reply(.cancel(.staleOperation)) }
  }
}
