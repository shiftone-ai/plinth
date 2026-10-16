#if os(iOS) && DEBUG
  import KioskCore
  import KioskRuntime

  /// A deterministic Port for the Simulator UI workflow. It is available only with
  /// an isolated test credential service and never enters a distribution build.
  @MainActor
  final class MobileBiometricTestPort: BiometricCredentialPort {
    enum UnlockResult: String {
      case succeeded, failed, cancelled, enrollmentChanged
    }

    private let result: UnlockResult
    private let kind: BiometricKind
    private var enabled = false
    private var pending: [OperationToken: CheckedContinuation<Void, Never>] = [:]

    init(result: UnlockResult, kind: BiometricKind) {
      self.result = result
      self.kind = kind
    }

    func status() -> BiometricStatus {
      BiometricStatus(availability: .available(kind), enabled: enabled)
    }

    func changeEnabled(_ enabled: Bool, token: OperationToken) async
      -> (BiometricStatus, BiometricChangeOutcome)
    {
      self.enabled = enabled
      return (status(), .succeeded)
    }

    func unlock(_ token: OperationToken) async -> (BiometricStatus, BiometricUnlockOutcome) {
      switch result {
      case .succeeded: return (status(), .succeeded)
      case .failed: return (status(), .failed)
      case .enrollmentChanged:
        enabled = false
        return (status(), .enrollmentChanged)
      case .cancelled:
        await withCheckedContinuation { continuation in pending[token] = continuation }
        return (status(), .cancelled)
      }
    }

    func cancel(_ token: OperationToken) {
      pending.removeValue(forKey: token)?.resume()
    }

    func cancelAll() {
      for token in Array(pending.keys) { cancel(token) }
    }
  }
#endif
