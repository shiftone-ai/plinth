#if os(iOS)
  import UIKit

  @MainActor
  protocol ExternalDisplayRegistration: AnyObject {
    var isAvailable: Bool { get }
    func stop()
  }

  /// Owned by the main scene's composition, rather than a SwiftUI render callback.
  @available(iOS 27.0, *)
  @MainActor
  final class MobileExternalDisplayRegistration: ExternalDisplayRegistration {
    private weak var controller: UIViewController?
    private var registration: UISceneAccessoryRegistration?
    var isAvailable: Bool { registration?.isAvailable == true }

    init(controller: UIViewController) {
      self.controller = controller
      let configuration = UISceneConfiguration(
        name: "Plinth", sessionRole: .windowExternalDisplayNonInteractive)
      configuration.delegateClass = MobileSceneDelegate.self
      let registration = controller.registerSceneAccessory(
        .externalNonInteractive(sceneConfiguration: configuration))
      registration.isEnabled = true
      self.registration = registration
    }

    func stop() {
      guard let registration else { return }
      self.registration = nil
      registration.isEnabled = false
      controller?.unregisterSceneAccessory(registration)
      controller = nil
    }
  }
#endif
