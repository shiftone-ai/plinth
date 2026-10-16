import AppKit
import KioskCore
import KioskRuntime
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import Observation
import SwiftUI

/// The credential adapter owns each LAContext. This bridge only mounts its matching view.
@MainActor @Observable
final class MacBiometricDisplay: BiometricUnlockPresentationPort {
  struct Request {
    let token: OperationToken
    let view: LAAuthenticationView
  }

  private(set) var request: Request?
  @ObservationIgnored private var waiting: CheckedContinuation<Bool, Never>?

  func prepare(_ context: LAContext, token: OperationToken) async -> Bool {
    if let current = request { dismiss(current.token) }
    request = Request(token: token, view: LAAuthenticationView(context: context))
    return await withCheckedContinuation { waiting = $0 }
  }

  func attached(_ token: OperationToken) {
    guard request?.token == token else { return }
    waiting?.resume(returning: true)
    waiting = nil
  }

  func dismiss(_ token: OperationToken) {
    guard request?.token == token else { return }
    request = nil
    waiting?.resume(returning: false)
    waiting = nil
  }
}

struct MacBiometricHost: View {
  let display: MacBiometricDisplay

  var body: some View {
    if let request = display.request {
      MountedAuthenticationView(request: request) { display.attached(request.token) }
        .frame(width: 56, height: 56)
        .accessibilityIdentifier("embedded-touch-id")
    }
  }
}

private struct MountedAuthenticationView: NSViewRepresentable {
  let request: MacBiometricDisplay.Request
  let attached: @MainActor () -> Void

  func makeNSView(context: Context) -> AuthenticationMount {
    let mount = AuthenticationMount()
    mount.install(request.view)
    mount.onAttach = attached
    return mount
  }

  func updateNSView(_ mount: AuthenticationMount, context: Context) {
    mount.install(request.view)
    mount.onAttach = attached
    if mount.window != nil { attached() }
  }
}

private final class AuthenticationMount: NSView {
  var onAttach: (@MainActor () -> Void)?
  private weak var authenticationView: LAAuthenticationView?

  func install(_ view: LAAuthenticationView) {
    guard authenticationView !== view else { return }
    authenticationView?.removeFromSuperview()
    authenticationView = view
    addSubview(view)
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      view.centerXAnchor.constraint(equalTo: centerXAnchor),
      view.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil { onAttach?() }
  }
}
