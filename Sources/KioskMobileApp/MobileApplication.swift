#if os(iOS)
  import KioskCore
  import KioskPresentation
  import KioskRuntime
  import KioskUI
  import SwiftUI
  import UIKit

  @MainActor
  public final class MobileApplication: NSObject, UIApplicationDelegate {
    public private(set) var session: MobileSession?

    public func application(
      _ application: UIApplication,
      configurationForConnecting connectingSceneSession: UISceneSession,
      options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
      let configuration = UISceneConfiguration(
        name: "Plinth", sessionRole: connectingSceneSession.role)
      configuration.delegateClass = MobileSceneDelegate.self
      return configuration
    }

    public func connect(_ scene: UIWindowScene, exhibitionWindow: Bool) -> UIWindow {
      if session == nil { session = MobileSession() }
      return session!.connect(scene, exhibitionWindow: exhibitionWindow)
    }

    public func applicationWillTerminate(_ application: UIApplication) { session?.stop() }

    func disconnect(_ scene: UIWindowScene) {
      guard let session else { return }
      if session.disconnect(scene) {
        session.stop()
        self.session = nil
      }
    }
  }

  @MainActor
  public final class MobileSceneDelegate: NSObject, UIWindowSceneDelegate {
    public var window: UIWindow?

    public func scene(
      _ scene: UIScene, willConnectTo session: UISceneSession,
      options connectionOptions: UIScene.ConnectionOptions
    ) {
      guard let scene = scene as? UIWindowScene,
        let app = UIApplication.shared.delegate as? MobileApplication
      else { return }
      let exhibition =
        session.role == .windowExternalDisplayNonInteractive
        || connectionOptions.userActivities.contains {
          $0.activityType == MobileSession.exhibitionActivity
        } || session.stateRestorationActivity?.activityType == MobileSession.exhibitionActivity
      window = app.connect(scene, exhibitionWindow: exhibition)
      for activity in connectionOptions.userActivities {
        app.session?.continueActivity(activity, in: scene)
      }
    }

    public func sceneDidBecomeActive(_ scene: UIScene) {
      owner?.displaysChanged()
      if owner?.isExhibitionScene(scene) == false { owner?.applicationActivated() }
    }
    public func sceneWillEnterForeground(_ scene: UIScene) { owner?.displaysChanged() }
    public func sceneDidDisconnect(_ scene: UIScene) {
      if let scene = scene as? UIWindowScene {
        (UIApplication.shared.delegate as? MobileApplication)?.disconnect(scene)
      }
      window = nil
    }
    public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
      owner?.continueActivity(userActivity, in: scene)
    }
    public func sceneDidEnterBackground(_ scene: UIScene) {
      if let scene = scene as? UIWindowScene { owner?.backgrounded(scene) }
    }
    @available(iOS 26.0, *)
    public func windowScene(
      _ windowScene: UIWindowScene,
      didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry
    ) { owner?.displaysChanged() }

    public func windowScene(
      _ windowScene: UIWindowScene, didUpdate coordinateSpace: UICoordinateSpace,
      interfaceOrientation: UIInterfaceOrientation, traitCollection: UITraitCollection
    ) {
      if #unavailable(iOS 26.0) { owner?.displaysChanged() }
    }

    public func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
      owner?.isExhibitionScene(scene) == true
        ? NSUserActivity(activityType: MobileSession.exhibitionActivity) : nil
    }

    private var owner: MobileSession? {
      (UIApplication.shared.delegate as? MobileApplication)?.session
    }
  }
#endif
