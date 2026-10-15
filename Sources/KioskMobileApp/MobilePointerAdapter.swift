#if os(iOS)
  import GameController
  import KioskCore
  import UIKit

  /// Root-owned native mouse and pointer-lock resources. All decisions remain in RootMediator.
  @MainActor
  final class MobilePointerAdapter {
    var send: ((Event) -> Reply?)?
    var bodyScene: (() -> UIWindowScene?)?
    var requestLock: ((Bool) -> Void)?
    var viewport: (() -> CGSize?)?
    var generation: (() -> UInt64)?
    private var observers: [NSObjectProtocol] = []
    private var mice: [GCMouse] = []
    private var captureOperation: OperationToken?
    private var changes: AsyncStream<Bool>.Continuation?

    func start() {
      guard observers.isEmpty else { return }
      for name in [Notification.Name.GCMouseDidConnect, .GCMouseDidDisconnect] {
        observers.append(
          NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.connectMice() }
          })
      }
      observers.append(
        NotificationCenter.default.addObserver(
          forName: UIPointerLockState.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            guard let self, let scene = self.bodyScene?()
            else { return }
            let locked = scene.pointerLockState?.isLocked == true
            self.changes?.yield(locked)
            if !locked, scene.activationState != .foregroundActive {
              _ = self.send?(.applicationDeactivated)
            }
            _ = self.send?(.externalPointerCaptureChanged(locked: locked))
          }
        })
      connectMice()
    }

    private func connectMice() {
      clearHandlers()
      mice = GCMouse.mice()
      for mouse in mice {
        // GCDevice documents this queue as the queue used for every value-change handler.
        mouse.handlerQueue = .main
        guard let input = mouse.mouseInput else { continue }
        input.mouseMovedHandler = { [weak self] _, dx, dy in
          MainActor.assumeIsolated {
            guard let self, let size = self.viewport?(), size.width > 0, size.height > 0 else {
              return
            }
            self.input(.move(dx: Double(dx) / size.width, dy: -Double(dy) / size.height))
          }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
          MainActor.assumeIsolated { self?.input(.primaryButton(pressed: pressed)) }
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
          if pressed { MainActor.assumeIsolated { self?.input(.unlock) } }
        }
        // UIKit's pan recognizer delivers scrolling even while locked. Subscribing here doubles it.
      }
      _ = send?(.externalMouseAvailabilityChanged(!mice.isEmpty))
    }

    private func input(_ input: ExternalMouseInput) {
      _ = send?(.externalMouseInput(input, generation: generation?() ?? 0))
    }

    func capture(_ token: OperationToken) async -> Bool {
      guard captureOperation == nil, let scene = bodyScene?(), scene.pointerLockState != nil,
        scene.activationState == .foregroundActive,
        MobilePresentationAdapter.isReadyForExhibition(scene)
      else { return false }
      captureOperation = token
      let channel = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
      changes = channel.continuation
      requestLock?(true)
      if scene.pointerLockState?.isLocked == true { changes?.yield(true) }
      let acquired = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
          for await locked in channel.stream where locked { return true }
          return false
        }
        group.addTask {
          do { try await Task.sleep(for: .seconds(2)) } catch { return false }
          return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
      }
      guard captureOperation == token, !Task.isCancelled else { return false }
      captureOperation = nil
      changes?.finish()
      changes = nil
      let locked =
        acquired && scene.pointerLockState?.isLocked == true
        && scene.activationState == .foregroundActive
        && MobilePresentationAdapter.isReadyForExhibition(scene)
      if !locked { requestLock?(false) }
      return locked
    }

    func release() {
      captureOperation = nil
      changes?.finish()
      changes = nil
      requestLock?(false)
    }
    func cancel(_ token: OperationToken) {
      if captureOperation == token { release() }
    }
    private func clearHandlers() {
      for mouse in mice {
        mouse.mouseInput?.mouseMovedHandler = nil
        mouse.mouseInput?.leftButton.pressedChangedHandler = nil
        mouse.mouseInput?.rightButton?.pressedChangedHandler = nil
      }
      mice.removeAll()
    }
    func stop() {
      release()
      clearHandlers()
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers.removeAll()
      send = nil
      bodyScene = nil
      requestLock = nil
      viewport = nil
      generation = nil
    }
  }
#endif
