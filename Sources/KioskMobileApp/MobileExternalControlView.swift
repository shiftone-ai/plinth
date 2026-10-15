#if os(iOS)
  import KioskCore
  import SwiftUI
  import UIKit

  struct PassiveExternalControl: UIViewRepresentable {
    let enabled: Bool
    let allowsDrag: Bool
    let pointerCaptured: Bool
    let send: (ExternalWebControl) -> Void
    func makeUIView(context: Context) -> MobileExternalControlView { MobileExternalControlView() }
    func updateUIView(_ view: MobileExternalControlView, context: Context) {
      view.isUserInteractionEnabled = enabled
      view.send = send
      view.allowsDrag = allowsDrag
      view.pointerCaptured = pointerCaptured
    }
  }

  /// Renders the device's input surface and emits typed intents; owns no browser state.
  @MainActor
  final class MobileExternalControlView: UIView {
    var send: ((ExternalWebControl) -> Void)?
    var pointerCaptured = false
    var allowsDrag = false { didSet { dragGesture.isEnabled = allowsDrag } }
    private lazy var dragGesture = UILongPressGestureRecognizer(
      target: self, action: #selector(drag(_:)))
    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .black
      isAccessibilityElement = true
      accessibilityLabel = "外部展示の操作"
      accessibilityIdentifier = "external-control"
      addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
      addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(activate(_:))))
      dragGesture.minimumPressDuration = 0.25
      dragGesture.isEnabled = false
      addGestureRecognizer(dragGesture)
      let pan = UIPanGestureRecognizer(target: self, action: #selector(scroll(_:)))
      pan.minimumNumberOfTouches = 1
      pan.allowedScrollTypesMask = .all
      pan.require(toFail: dragGesture)
      addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { nil }

    private func point(_ location: CGPoint) -> SurfacePoint {
      .init(
        x: min(1, max(0, Double(location.x / max(1, bounds.width)))),
        y: min(1, max(0, Double(location.y / max(1, bounds.height)))))
    }
    @objc private func hover(_ recognizer: UIHoverGestureRecognizer) {
      guard !pointerCaptured else { return }
      guard recognizer.state == .began || recognizer.state == .changed else { return }
      send?(.move(point(recognizer.location(in: self))))
    }
    @objc private func drag(_ recognizer: UILongPressGestureRecognizer) {
      let position = point(recognizer.location(in: self))
      switch recognizer.state {
      case .began: send?(.press(position))
      case .changed: send?(.move(position))
      case .ended: send?(.release(position))
      case .cancelled: send?(.cancelPress)
      default: break
      }
    }
    @objc private func activate(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .ended else { return }
      send?(.activate(point(recognizer.location(in: self))))
    }
    @objc private func scroll(_ recognizer: UIPanGestureRecognizer) {
      guard recognizer.state == .changed else { return }
      let delta = recognizer.translation(in: self)
      recognizer.setTranslation(.zero, in: self)
      send?(.scroll(dx: -Double(delta.x), dy: -Double(delta.y)))
    }
  }
#endif
