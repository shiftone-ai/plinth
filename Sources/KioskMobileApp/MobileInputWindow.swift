#if os(iOS)
  import KioskCore
  import UIKit

  @MainActor
  final class MobileInputWindow: UIWindow {
    var send: ((Event) -> Reply?)?
    var scope: (() -> InputScope)?

    override func sendEvent(_ event: UIEvent) {
      guard let defaultScope = scope?(), let send else { return super.sendEvent(event) }
      let scope =
        event.allTouches?.compactMap { touch -> InputScope? in
          var view = touch.view
          while let current = view {
            if current is AdministratorEntryButton { return .administratorEntry }
            view = current.superview
          }
          return nil
        }.first ?? defaultScope
      let native: NativeInput?
      switch event.type {
      case .hover: native = .cursorMoved
      case .scroll: native = .scroll
      case .presses: native = .key
      case .transform: native = .gesture
      default: native = nil
      }
      if let native {
        if case .input(let decision) = send(.nativeInput(native, scope)), decision.passes {
          super.sendEvent(event)
        }
        return
      }
      if !event.buttonMask.subtracting(.primary).isEmpty {
        if case .input(let decision) = send(.nativeInput(.otherButton, scope)), decision.passes {
          super.sendEvent(event)
        }
        return
      }
      guard event.type == .touches, let touches = event.allTouches, !touches.isEmpty else {
        return super.sendEvent(event)
      }
      var passes = true
      for touch in touches {
        let input: NativeInput
        switch touch.phase {
        case .began: input = .primaryDown
        case .ended, .cancelled: input = .primaryUp
        case .moved: input = .touchMoved
        case .stationary: continue
        case .regionEntered, .regionMoved, .regionExited: input = .cursorMoved
        @unknown default: input = .gesture
        }
        if case .input(let decision) = send(.nativeInput(input, scope)) {
          passes = passes && decision.passes
        } else {
          passes = false
        }
      }
      if passes { super.sendEvent(event) }
    }
  }
#endif
