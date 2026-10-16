public enum BiometricKind: String, Equatable, Sendable {
  case touchID, faceID
}

public enum BiometricUnavailableReason: String, Equatable, Sendable {
  case notAvailable, notEnrolled, lockedOut, passcodeNotSet, storageUnavailable
}

public enum BiometricAvailability: Equatable, Sendable {
  case available(BiometricKind)
  case unavailable(BiometricUnavailableReason)
}

public struct BiometricStatus: Equatable, Sendable {
  public let availability: BiometricAvailability
  public let enabled: Bool

  public init(availability: BiometricAvailability, enabled: Bool) {
    self.availability = availability
    self.enabled = enabled
  }
}

public enum BiometricChangeOutcome: Equatable, Sendable {
  case succeeded, cancelled, failed
}

public enum BiometricUnlockOutcome: Equatable, Sendable {
  case succeeded, cancelled, failed, enrollmentChanged
}
