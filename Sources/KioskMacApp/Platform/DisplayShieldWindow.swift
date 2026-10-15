import AppKit

@MainActor
final class DisplayShieldWindow: NSWindow {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(frame: CGRect) {
    super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    isMovable = false
    backgroundColor = .black
    isOpaque = true
    hasShadow = false
    level = .mainMenu
  }
}
