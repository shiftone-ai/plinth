import AppKit
import KioskCore
import KioskRuntime

@MainActor
public final class NativeInputAdapter {
  private var monitor: Any?
  private var menuObserver: (any NSObjectProtocol)?
  private let window: NSWindow
  private let send: @MainActor (Event) -> Reply?
  private let scope: @MainActor () -> InputScope
  private let requestTermination: @MainActor () -> Void
  public init(
    window: NSWindow, scope: @escaping @MainActor () -> InputScope,
    send: @escaping @MainActor (Event) -> Reply?,
    requestTermination: @escaping @MainActor () -> Void = {}
  ) {
    self.window = window
    self.scope = scope
    self.send = send
    self.requestTermination = requestTermination
  }

  public func start() {
    guard monitor == nil else { return }
    // AppKit menu tracking may consume the release without delivering it to the host window.
    menuObserver = NotificationCenter.default.addObserver(
      forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        _ = self.send(.nativeInput(.primaryUp, self.scope()))
      }
    }
    let mask: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown,
      .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged,
      .scrollWheel, .magnify, .rotate, .swipe, .beginGesture, .endGesture,
      .smartMagnify, .pressure, .keyDown, .keyUp, .flagsChanged,
    ]
    // AppKit invokes local monitors synchronously on the application's event loop.
    monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      let passes = MainActor.assumeIsolated { self?.filter(event) != nil }
      return passes ? event : nil
    }
  }

  public func filter(_ event: NSEvent) -> NSEvent? {
    if event.type == .keyDown,
      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
      ["q", "w"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "")
    {
      requestTermination()
      return nil
    }
    if event.type == .keyDown, event.charactersIgnoringModifiers?.lowercased() == "k",
      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .option, .shift]
    {
      _ = send(.unlockRequested)
      return nil
    }
    // Keys may target the application's menu before a window receives them.
    guard event.window == nil || event.window === window else {
      if event.type == .leftMouseUp {
        _ = send(.nativeInput(.primaryUp, scope()))
      }
      return event
    }
    let input = Self.classify(event)
    guard case .input(let decision) = send(.nativeInput(input, scope())) else { return nil }
    return decision.passes ? event : nil
  }

  public static func classify(_ event: NSEvent) -> NativeInput {
    switch event.type {
    case .mouseMoved: .cursorMoved
    case .leftMouseDown:
      event.modifierFlags.contains(.control) ? .otherButton : .primaryDown
    case .leftMouseUp: .primaryUp
    case .leftMouseDragged: .primaryDrag
    case .scrollWheel: .scroll
    case .flagsChanged: .key
    case .keyDown, .keyUp:
      if event.modifierFlags.contains(.command),
        !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control),
        ["a", "z", "x", "c", "v"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "")
      {
        .key
      } else {
        event.modifierFlags.contains(.command) ? .applicationShortcut : .key
      }
    case .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .otherMouseDown, .otherMouseUp, .otherMouseDragged:
      .otherButton
    default: .gesture
    }
  }

  public func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
    menuObserver = nil
  }
}
