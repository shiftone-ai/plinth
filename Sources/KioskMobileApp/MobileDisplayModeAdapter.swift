#if os(iOS)
  import KioskCore
  import UIKit

  @MainActor
  final class MobileDisplayModeAdapter {
    var selectedWindow: (() -> UIWindow?)?
    var changed: (() -> Void)?
    var canConfigure: (() -> Bool)?
    private var applyingMode = false
    private struct Pending {
      let token: OperationToken
      var scene: UIWindowScene?
      let mode: ExternalDisplayMode?
      let completion: CheckedContinuation<Bool, Never>
      var applied = false
    }
    private var pending: Pending?
    private var observers: [NSObjectProtocol] = []
    private struct StableGeometry: Equatable {
      let scene: ObjectIdentifier
      let screen: ObjectIdentifier
      let bounds: CGRect
      let screenBounds: CGRect
      let mode: ExternalDisplayMode?
    }
    private var stableGeometry: StableGeometry?
    private var settlingTimer: Timer?
    private var settlingEpoch: UInt64 = 0

    init() {
      for name in [UIScreen.modeDidChangeNotification, UIApplication.didBecomeActiveNotification] {
        observers.append(
          NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed?() }
          })
      }
    }

    func availability(
      in scenes: [(scene: UIWindowScene, exhibition: Bool)], deviceScreen: UIScreen?
    ) -> MobileDisplayAvailability {
      let device = scenes.contains { !$0.exhibition && $0.scene.screen === deviceScreen }
      let external = scenes.contains {
        $0.exhibition && deviceScreen != nil && $0.scene.screen !== deviceScreen
          && MobilePresentationAdapter.isReadyForExhibition($0.scene)
      }
      let displayOnly = scenes.contains {
        $0.scene.session.role == .windowExternalDisplayNonInteractive
      }
      let externalScene = scenes.first {
        $0.scene.session.role == .windowExternalDisplayNonInteractive
      }?.scene
      let modes =
        externalScene.map {
          Array(Set($0.screen.availableModes.map(MobileDisplayModeAdapter.describe)))
            .sorted {
              ($0.width, $0.height, $0.pixelAspectRatio) < (
                $1.width, $1.height, $1.pixelAspectRatio
              )
            }
        } ?? []
      return .init(
        deviceAvailable: device, externalAvailable: external,
        supportsExhibitionWindow: UIApplication.shared.supportsMultipleScenes
          && !ProcessInfo.processInfo.isiOSAppOnMac,
        externalDisplayOnly: displayOnly,
        supportsExternalDisplay: !ProcessInfo.processInfo.isiOSAppOnMac,
        externalConnected: scenes.contains {
          $0.exhibition && $0.scene.screen !== deviceScreen
        },
        displayModes: modes,
        currentMode: externalScene?.screen.currentMode.map(MobileDisplayModeAdapter.describe))
    }

    static func describe(_ mode: UIScreenMode) -> ExternalDisplayMode {
      .init(
        width: Int(mode.size.width), height: Int(mode.size.height),
        pixelAspectRatio: mode.pixelAspectRatio)
    }

    func prepare(_ mode: ExternalDisplayMode?, token: OperationToken) async -> Bool {
      guard !Task.isCancelled, pending == nil else { return false }
      return await withCheckedContinuation { continuation in
        pending = .init(token: token, mode: mode, completion: continuation)
        refresh()
      }
    }

    func refresh() {
      guard !applyingMode, let operation = pending,
        let window = selectedWindow?(), let scene = window.windowScene,
        UIApplication.shared.applicationState == .active, canConfigure?() == true,
        Self.isForeground(scene)
      else {
        cancelSettling()
        return
      }
      if operation.scene !== scene {
        cancelSettling()
        pending?.scene = scene
        pending?.applied = false
      }
      if pending?.applied == false {
        applyMode(operation.mode, to: window, scene: scene)
        return
      }
      if #unavailable(iOS 27.0) { window.frame = scene.screen.bounds }
      if operation.mode == nil || scene.screen.currentMode.map(Self.describe) == operation.mode,
        MobilePresentationAdapter.isReadyForExhibition(scene)
      {
        settle(scene, token: operation.token)
      } else {
        cancelSettling()
      }
    }

    private func applyMode(_ mode: ExternalDisplayMode?, to window: UIWindow, scene: UIWindowScene)
    {
      let nativeMode: UIScreenMode?
      if let mode = mode {
        guard scene.session.role == .windowExternalDisplayNonInteractive,
          let supported = scene.screen.availableModes.first(where: {
            Self.describe($0) == mode
          })
        else {
          finish(false)
          return
        }
        nativeMode = supported
      } else {
        nativeMode = nil
      }
      pending?.applied = true
      applyingMode = true
      if let nativeMode {
        // UIKit requires selecting a mode before associating the screen with a window.
        window.isHidden = true
        window.windowScene = nil
        scene.screen.currentMode = nativeMode
        window.windowScene = scene
        window.frame = scene.screen.bounds
        window.makeKeyAndVisible()
      }
      if scene.session.role == .windowExternalDisplayNonInteractive {
        scene.screen.overscanCompensation = .none
      }
      applyingMode = false
      changed?()
    }

    private func geometry(_ scene: UIWindowScene) -> StableGeometry {
      .init(
        scene: ObjectIdentifier(scene), screen: ObjectIdentifier(scene.screen),
        bounds: scene.coordinateSpace.bounds, screenBounds: scene.screen.bounds,
        mode: scene.screen.currentMode.map(Self.describe))
    }

    private func settle(_ scene: UIWindowScene, token: OperationToken) {
      let candidate = geometry(scene)
      guard stableGeometry != candidate else { return }
      cancelSettling()
      stableGeometry = candidate
      let epoch = settlingEpoch
      // Peripheral discovery can replace a ready external Scene shortly after activation.
      // Keep the existing bounded preparation operation until its geometry has settled.
      let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.pending?.token == token, self.settlingEpoch == epoch else { return }
          guard let window = self.selectedWindow?(), let current = window.windowScene,
            self.pending?.scene === current, self.stableGeometry == self.geometry(current),
            UIApplication.shared.applicationState == .active, self.canConfigure?() == true,
            Self.isForeground(current),
            MobilePresentationAdapter.isReadyForExhibition(current)
          else {
            self.cancelSettling()
            self.refresh()
            return
          }
          self.finish(true)
        }
      }
      settlingTimer = timer
      RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelSettling() {
      settlingEpoch += 1
      settlingTimer?.invalidate()
      settlingTimer = nil
      stableGeometry = nil
    }

    private static func isForeground(_ scene: UIWindowScene) -> Bool {
      scene.activationState == .foregroundActive
        || (scene.session.role == .windowExternalDisplayNonInteractive
          && scene.activationState == .foregroundInactive)
    }

    func cancel(_ token: OperationToken) {
      if pending?.token == token { finish(false) }
    }

    func disconnect(_ scene: UIWindowScene) {
      // A mode change can replace the external Scene. Keep the same bounded operation,
      // and release the old Scene while waiting for its replacement.
      if pending?.scene === scene {
        cancelSettling()
        pending?.scene = nil
        pending?.applied = false
      }
    }

    private func finish(_ succeeded: Bool) {
      cancelSettling()
      let completion = pending?.completion
      pending = nil
      completion?.resume(returning: succeeded)
    }

    func stop() {
      finish(false)
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers.removeAll()
      selectedWindow = nil
      changed = nil
      canConfigure = nil
    }
  }
#endif
