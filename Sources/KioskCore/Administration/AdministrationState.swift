public struct AdministrationState: Equatable, Sendable {
  public var passcode = ""
  public var epoch: UInt64 = 1
  public var savedProfile: KioskProfile?
  public var draft: ProfileDraft?
  public var catalogSelection: CatalogEntry?
  public var catalogNameDraft = ""
  public var catalogSelectionNameDraft = ""
  public var catalogRequiresAvailableOutput = false
  public var catalogPassphrase = ""
  public var catalogConfirmPassphrase = ""
  public var saving = false
  public var saveFailed = false
  public var unlockID: UInt64?
  public var verification: OperationToken?
  public var failedAttempts = 0
  public var cooldownUntil: Double?
  public var pendingWebLogin: String?
  public var webVerification: OperationToken?
  public var lastWebLogin: WebLoginResult?
  public var hasUnsavedDraft: Bool {
    guard let draft else { return false }
    return draft.validatedProfile != savedProfile
  }
  public init() {}
}

public struct WebLoginResult: Equatable, Sendable {
  public let token: String
  public let succeeded: Bool
  public init(token: String, succeeded: Bool) {
    self.token = token
    self.succeeded = succeeded
  }
}
