import CloudKit
import KioskCore

@MainActor
public final class RemoteCloudEventBridge {
  public weak var runtime: RootRuntime?
  private var accountObserver: NSObjectProtocol?

  public init() {
    accountObserver = NotificationCenter.default.addObserver(
      forName: .CKAccountChanged, object: nil, queue: nil
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.send(.remoteAccountAvailabilityChanged) }
    }
  }

  isolated deinit {
    if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
  }

  public func send(_ event: Event) {
    runtime?.send(event, from: .cloudRemote)
  }
}
