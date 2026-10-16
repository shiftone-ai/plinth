#if os(iOS) && DEBUG
  import Foundation
  import KioskCore
  import KioskRuntime

  /// Available only with an isolated UI-test credential service in a Debug build.
  @MainActor
  final class MobileBiometricTestPort: BiometricCredentialPort {
    private let kind: BiometricKind
    private let result: BiometricUnlockOutcome
    private var enabled = false
    private var pending:
      (OperationToken, CheckedContinuation<(BiometricStatus, BiometricUnlockOutcome), Never>)?

    static func make(service: String) -> MobileBiometricTestPort? {
      guard service.hasPrefix("ai.shiftone.plinth.tests."),
        let name = ProcessInfo.processInfo.environment["PLINTH_TEST_BIOMETRIC_RESULT"],
        let kindName = ProcessInfo.processInfo.environment["PLINTH_TEST_BIOMETRIC_KIND"]
      else { return nil }
      let result: BiometricUnlockOutcome
      switch name {
      case "succeeded": result = .succeeded
      case "failed": result = .failed
      case "cancelled": result = .cancelled
      case "enrollmentChanged": result = .enrollmentChanged
      default: return nil
      }
      let kind: BiometricKind
      switch kindName {
      case "faceID": kind = .faceID
      case "touchID": kind = .touchID
      default: return nil
      }
      return MobileBiometricTestPort(kind: kind, result: result)
    }

    private init(kind: BiometricKind, result: BiometricUnlockOutcome) {
      self.kind = kind
      self.result = result
    }

    func status() -> BiometricStatus {
      .init(availability: .available(kind), enabled: enabled)
    }

    func changeEnabled(_ value: Bool, token: OperationToken) async
      -> (BiometricStatus, BiometricChangeOutcome)
    {
      enabled = value
      return (status(), .succeeded)
    }

    func unlock(_ token: OperationToken) async -> (BiometricStatus, BiometricUnlockOutcome) {
      if result == .cancelled {
        return await withCheckedContinuation { pending = (token, $0) }
      }
      if result == .enrollmentChanged { enabled = false }
      return (status(), result)
    }

    func cancel(_ token: OperationToken) {
      guard pending?.0 == token else { return }
      pending?.1.resume(returning: (status(), .cancelled))
      pending = nil
    }

    func cancelAll() {
      if let token = pending?.0 { cancel(token) }
    }
  }
#endif
