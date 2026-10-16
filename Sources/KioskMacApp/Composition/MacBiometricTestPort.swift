#if DEBUG
  import Foundation
  import KioskCore
  import KioskRuntime

  /// Only isolated GUI fixtures can select this port.
  @MainActor
  final class MacBiometricTestPort: BiometricCredentialPort {
    private let result: BiometricUnlockOutcome
    private var enabled = false
    private var pending:
      (OperationToken, CheckedContinuation<(BiometricStatus, BiometricUnlockOutcome), Never>)?

    static func make(service: String) -> MacBiometricTestPort? {
      guard service.hasPrefix("ai.shiftone.plinth.tests."),
        let name = ProcessInfo.processInfo.environment["PLINTH_TEST_BIOMETRIC_RESULT"]
      else { return nil }
      let result: BiometricUnlockOutcome
      switch name {
      case "succeeded": result = .succeeded
      case "failed": result = .failed
      case "cancelled": result = .cancelled
      default: return nil
      }
      return MacBiometricTestPort(result: result)
    }

    private init(result: BiometricUnlockOutcome) { self.result = result }

    func status() -> BiometricStatus {
      .init(availability: .available(.touchID), enabled: enabled)
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
