import AppKit
import KioskCore

/// Samples native cursor position; Root chooses any correction to the selected output.
@MainActor
final class MacPointerAdapter {
  var send: ((Event) -> Void)?
  private var timer: Timer?
  private var monitor: Any?
  private var frame: CGRect?
  private var lastPoint: SurfacePoint?
  private var displayID: CGDirectDisplayID?

  func start(frame: CGRect, displayID: String?) {
    stop()
    guard let displayID,
      let number = UInt32(displayID.replacingOccurrences(of: "display-", with: ""))
    else { return }
    self.frame = frame
    self.displayID = number
    // Event delivery handles movement while the pointer is over this app. Sampling also covers other screens.
    monitor = NSEvent.addLocalMonitorForEvents(matching: [
      .mouseMoved, .leftMouseDragged, .leftMouseDown,
    ]) { [weak self] event in
      MainActor.assumeIsolated { self?.sample() }
      return event
    }
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.sample() }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func sample() {
    guard NSApplication.shared.isActive, let frame, frame.width > 0, frame.height > 0 else {
      return
    }
    let point = NSEvent.mouseLocation
    let normalized = SurfacePoint(
      x: (point.x - frame.minX) / frame.width,
      y: 1 - (point.y - frame.minY) / frame.height)
    guard normalized != lastPoint else { return }
    lastPoint = normalized
    send?(.nativePointerMoved(normalized))
  }

  func confine(_ point: SurfacePoint) -> Bool {
    guard point.isValid, let displayID, let frame else { return false }
    // Convert the selected region's Cocoa coordinates to coordinates of this physical display.
    guard
      let screen = NSScreen.screens.first(where: {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          == displayID
      })
    else { return false }
    let x = frame.minX - screen.frame.minX + point.x * max(0, frame.width - 1)
    let y = screen.frame.maxY - frame.maxY + point.y * max(0, frame.height - 1)
    return CGDisplayMoveCursorToPoint(displayID, .init(x: x, y: y)) == .success
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    frame = nil
    displayID = nil
    lastPoint = nil
  }
}
