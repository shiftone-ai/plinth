import AppKit
import KioskCore
import KioskRuntime

@MainActor
public final class DisplayAdapter: DisplayReadingPort {
  private let exhibitionInset: Double
  public var count: Int { NSScreen.screens.count }
  public var availableDisplays: [DisplayDescriptor] {
    NSScreen.screens.compactMap { screen in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return nil }
      return DisplayDescriptor(
        id: "display-\(number.uint32Value)", name: screen.localizedName,
        builtIn: CGDisplayIsBuiltin(number.uint32Value) != 0,
        frame: .init(
          x: screen.frame.minX + exhibitionInset, y: screen.frame.minY + exhibitionInset,
          width: screen.frame.width - 2 * exhibitionInset,
          height: screen.frame.height - 2 * exhibitionInset))
    }
  }
  public var exhibitionFrame: NSRect? {
    guard let display = DisplaySelection.select(.init(), from: availableDisplays) else {
      return nil
    }
    return frame(for: display.id)
  }
  public func frame(for displayID: String?) -> CGRect? {
    guard let displayID else { return exhibitionFrame }
    return NSScreen.screens.first { screen in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return false }
      return "display-\(number.uint32Value)" == displayID
    }?.frame.insetBy(dx: exhibitionInset, dy: exhibitionInset)
  }
  public init(exhibitionInset: Double = 0) { self.exhibitionInset = exhibitionInset }
}
