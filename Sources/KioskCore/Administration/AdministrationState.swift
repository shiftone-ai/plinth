public struct AdministrationState: Equatable, Sendable {
  public var passcode = ""
  public var epoch: UInt64 = 1
  public var savedProfile: KioskProfile?
  public var draft: ProfileDraft?
  public var saving = false
  public var saveFailed = false
  public var unlockID: UInt64?
  public var verification: OperationToken?
  public var failedAttempts = 0
  public var cooldownUntil: Double?
  public var hasUnsavedDraft: Bool {
    guard let draft else { return false }
    return draft.validatedProfile != savedProfile
  }
  public init() {}
}
