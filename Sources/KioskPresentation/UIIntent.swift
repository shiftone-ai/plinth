import KioskCore

public enum SettingsIntent: Sendable {
  case edit(ProfileDraftEdit)
  case editPasscode(String)
  case save, discard
  case configurePasscode
  case changeBiometricUnlock(Bool)
  case cancelBiometricChange
  case start, quit
  case prepareExternalScene
  case addOriginRule
  case removeOriginRule(UInt64)
}

public enum UnlockIntent: Sendable {
  case editPasscode(String)
  case submit
  case cancel
}

public enum RootIntent: Sendable { case unlock }
