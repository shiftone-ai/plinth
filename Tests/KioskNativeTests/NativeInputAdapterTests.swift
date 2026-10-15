import AppKit
import KioskCore
import KioskMacApp
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_NATIVE_TESTS"] == "1"), .serialized)
@MainActor
struct NativeInputAdapterTests {
  @Test(arguments: [false, true])
  func releaseOutsideTheMainWindowAllowsTheNextClick(menuTracking: Bool) throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
      backing: .buffered, defer: false)
    let menuWindow = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    menuWindow.isReleasedWhenClosed = false
    defer {
      window.close()
      menuWindow.close()
    }
    var state = InputState()
    var deliveries = 0
    let adapter = NativeInputAdapter(
      window: window, scope: { .administration },
      send: { event in
        guard case .nativeInput(let input, let scope) = event else { return nil }
        deliveries += 1
        let decision = InputPolicy.evaluate(
          input, scope: scope, mode: .administration, webAvailable: false, generation: 0,
          policy: .init(), state: state)
        state = decision.state
        return .input(decision)
      })
    adapter.start()
    defer { adapter.stop() }
    let down = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
    )
    try #require(adapter.filter(down) != nil)
    #expect(state.pressedScope == .administration)
    if menuTracking {
      NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
    } else {
      let up = try #require(
        NSEvent.mouseEvent(
          with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 1,
          windowNumber: menuWindow.windowNumber, context: nil, eventNumber: 2, clickCount: 1,
          pressure: 0))
      try #require(up.window === menuWindow)
      #expect(adapter.filter(up) != nil)
    }
    #expect(state.pressedScope == nil)
    #expect(adapter.filter(down) != nil)
    adapter.stop()
    let stoppedCount = deliveries
    NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
    #expect(deliveries == stoppedCount)
  }
}
