public enum ProfileRevision {
  public static func next(after revision: UInt64?) -> UInt64? {
    let current = revision ?? 0
    return current == UInt64.max ? nil : current + 1
  }
}
