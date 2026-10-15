#if os(iOS)
  import SwiftUI
  import UIKit

  @MainActor
  final class MobileHostingController<Content: View>: UIHostingController<Content> {
    var externalRegistration: (any ExternalDisplayRegistration)?
    var pointerLockRequested = false {
      didSet { setNeedsUpdateOfPrefersPointerLocked() }
    }
    override var prefersPointerLocked: Bool { pointerLockRequested }
    @available(iOS 26.0, *)
    override func updateProperties() {
      super.updateProperties()
      // Reading inside UIKit's tracking phase subscribes to system availability changes.
      _ = externalRegistration?.isAvailable
    }
    var exhibiting = false {
      didSet {
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
      }
    }
    override var prefersStatusBarHidden: Bool { exhibiting }
    override var prefersHomeIndicatorAutoHidden: Bool { exhibiting }
  }
#endif
