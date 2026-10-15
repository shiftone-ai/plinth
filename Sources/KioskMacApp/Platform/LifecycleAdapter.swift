import AppKit
import KioskCore
import KioskRuntime

@MainActor
public final class LifecycleAdapter {
  private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
  private let send: @MainActor (Event) -> Void
  private let displays: any DisplayReadingPort
  public init(
    displays: any DisplayReadingPort = DisplayAdapter(), send: @escaping @MainActor (Event) -> Void
  ) {
    self.send = send
    self.displays = displays
  }

  public func start() {
    guard observers.isEmpty else { return }
    observe(.default, NSApplication.didChangeScreenParametersNotification) { [displays] in
      .macDisplaysChanged(displays.availableDisplays)
    }
    observe(.default, NSApplication.didResignActiveNotification) { .applicationDeactivated }
    observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) {
      .systemWillSleep
    }
  }

  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name,
    event: @escaping @MainActor () -> Event
  ) {
    let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      // .main delivers this callback on the main queue.
      MainActor.assumeIsolated { self?.send(event()) }
    }
    observers.append((center, observer))
  }

  public func stop() {
    for (center, observer) in observers { center.removeObserver(observer) }
    observers.removeAll()
  }
}
