#if os(iOS)
  import KioskCore
  import KioskRuntime
  import UIKit

  @MainActor
  final class MobilePresentationAdapter: PresentationPort, DisplayReadingPort {
    var selectedScene: (() -> UIWindowScene?)?
    var exhibitionChanged: ((Bool) -> Void)?
    var existingExhibitionScene: (() -> UIWindowScene?)?
    var pointer: MobilePointerAdapter?
    var prepareDisplayMode: ((ExternalDisplayMode?, OperationToken) async -> Bool)?
    var cancelDisplayMode: ((OperationToken) -> Void)?
    private var previousIdleTimerDisabled: Bool?
    private var rotation: ExternalDisplayRotation = .standard
    private struct PendingScene {
      let token: OperationToken
      let activityID: String
      let completion: CheckedContinuation<Bool, Never>
    }
    private var pendingScene: PendingScene?
    private static let requestIDKey = "plinthSceneRequestID"
    var count: Int { selectedScene?() == nil ? 0 : 1 }
    var exhibitionFrame: CGRect? {
      selectedScene?().map {
        let size = Self.coordinates($0).bounds.size
        return CGRect(
          origin: .zero,
          size: rotation.swapsDimensions
            ? CGSize(width: size.height, height: size.width) : size)
      }
    }

    func apply(_ request: PresentationRequest) -> Bool {
      guard let scene = selectedScene?(),
        Self.isReadyForExhibition(scene)
      else { return false }
      if previousIdleTimerDisabled == nil {
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
      }
      rotation = request.externalDisplayRotation
      UIApplication.shared.isIdleTimerDisabled = true
      exhibitionChanged?(true)
      return true
    }

    func release() {
      pointer?.release()
      if let previousIdleTimerDisabled {
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
      }
      previousIdleTimerDisabled = nil
      rotation = .standard
      exhibitionChanged?(false)
      finishScenePreparation(succeeded: false)
    }
    func capturePointer(_ token: OperationToken) async -> Bool {
      await pointer?.capture(token) ?? false
    }
    func releasePointer() { pointer?.release() }
    func cancelPointerCapture(_ token: OperationToken) { pointer?.cancel(token) }
    func prepareExternalDisplayMode(_ mode: ExternalDisplayMode?, token: OperationToken) async
      -> Bool
    {
      await prepareDisplayMode?(mode, token) ?? false
    }
    func cancelDisplayModePreparation(_ token: OperationToken) { cancelDisplayMode?(token) }

    func prepareExternalScene(_ token: OperationToken) async -> Bool {
      guard UIApplication.shared.supportsMultipleScenes, pendingScene == nil, !Task.isCancelled
      else { return false }
      return await withCheckedContinuation { continuation in
        let activityID = UUID().uuidString
        pendingScene = .init(token: token, activityID: activityID, completion: continuation)
        let activity = NSUserActivity(activityType: MobileSession.exhibitionActivity)
        activity.targetContentIdentifier = MobileSession.exhibitionActivity
        activity.userInfo = [Self.requestIDKey: activityID]
        var request =
          existingExhibitionScene?().map {
            UISceneSessionActivationRequest(session: $0.session)
          } ?? UISceneSessionActivationRequest(role: .windowApplication)
        request.userActivity = activity
        // The operator moves this interactive application window to the display.
        UIApplication.shared.activateSceneSession(for: request) { [weak self] _ in
          guard self?.pendingScene?.activityID == activityID else { return }
          self?.finishScenePreparation(succeeded: false)
        }
      }
    }

    func scenePrepared(for activity: NSUserActivity) {
      guard let activityID = activity.userInfo?[Self.requestIDKey] as? String,
        pendingScene?.activityID == activityID
      else { return }
      finishScenePreparation(succeeded: true)
    }

    func cancelScenePreparation(_ token: OperationToken) {
      guard pendingScene?.token == token else { return }
      finishScenePreparation(succeeded: false)
    }

    private func finishScenePreparation(succeeded: Bool) {
      let completion = pendingScene?.completion
      pendingScene = nil
      completion?.resume(returning: succeeded)
    }

    static func isReadyForExhibition(_ scene: UIWindowScene) -> Bool {
      guard
        scene.activationState == .foregroundActive
          || scene.activationState == .foregroundInactive
      else { return false }
      let coordinates = Self.coordinates(scene)
      let frame = coordinates.convert(coordinates.bounds, to: scene.screen.coordinateSpace)
      let screen = scene.screen.coordinateSpace.bounds
      return abs(frame.minX - screen.minX) < 1 && abs(frame.minY - screen.minY) < 1
        && abs(frame.width - screen.width) < 1 && abs(frame.height - screen.height) < 1
    }

    private static func coordinates(_ scene: UIWindowScene) -> UICoordinateSpace {
      if #available(iOS 27.0, *) { return scene.effectiveGeometry.coordinateSpace }
      // Legacy display-only Scenes use the display coordinate space rather than application-window geometry.
      if scene.session.role == .windowExternalDisplayNonInteractive { return scene.coordinateSpace }
      if #available(iOS 26.0, *) { return scene.effectiveGeometry.coordinateSpace }
      return scene.coordinateSpace
    }
  }
#endif
