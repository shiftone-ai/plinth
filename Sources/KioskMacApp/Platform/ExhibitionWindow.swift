import AppKit
import KioskRuntime

final class ExhibitionWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
