import AppKit
import KioskCore
import KioskRuntime

@MainActor
public final class PresentationAdapter: PresentationPort {
  private let window: NSWindow
  private let preview: Bool
  private let displays: any DisplayReadingPort
  private var previousOptions: NSApplication.PresentationOptions?
  private var previousFrame: NSRect?
  private var previousStyle: NSWindow.StyleMask?
  private var previousMovable: Bool?
  private var shields: [DisplayShieldWindow] = []
  private let pointer = MacPointerAdapter()
  public var pointerEvents: ((Event) -> Void)? {
    didSet { pointer.send = pointerEvents }
  }
  public init(window: NSWindow, preview: Bool, displays: any DisplayReadingPort = DisplayAdapter())
  {
    self.window = window
    self.preview = preview
    self.displays = displays
  }

  public func apply(_ request: PresentationRequest) -> Bool {
    guard previousFrame == nil, displays.count > 0,
      let frame = displays.frame(for: request.displayID)
    else { return false }
    previousFrame = window.frame
    previousStyle = window.styleMask
    previousMovable = window.isMovable
    if !preview && request.mode == .fixedFullscreen {
      previousOptions = NSApplication.shared.presentationOptions
      NSApplication.shared.presentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching,
      ]
      window.styleMask = [.borderless]
      window.isMovable = false
      window.setFrame(frame, display: true)
      window.level = .mainMenu
      pointer.start(frame: frame, displayID: request.displayID)
      for display in displays.availableDisplays where display.id != request.displayID {
        guard let shieldFrame = displays.frame(for: display.id), shieldFrame != frame else {
          continue
        }
        let shield = DisplayShieldWindow(frame: shieldFrame)
        shields.append(shield)
        shield.orderFrontRegardless()
      }
    }
    window.acceptsMouseMovedEvents = true
    return true
  }

  public func prepareExternalScene(_ token: OperationToken) async -> Bool { false }
  public func cancelScenePreparation(_ token: OperationToken) {}
  public func confinePointer(_ point: SurfacePoint) -> Bool { pointer.confine(point) }

  public func release() {
    pointer.stop()
    for shield in shields {
      shield.orderOut(nil)
      shield.close()
    }
    shields.removeAll()
    if let options = previousOptions { NSApplication.shared.presentationOptions = options }
    if let style = previousStyle { window.styleMask = style }
    if let movable = previousMovable { window.isMovable = movable }
    window.level = .normal
    if let frame = previousFrame { window.setFrame(frame, display: true) }
    previousOptions = nil
    previousFrame = nil
    previousStyle = nil
    previousMovable = nil
  }
}
