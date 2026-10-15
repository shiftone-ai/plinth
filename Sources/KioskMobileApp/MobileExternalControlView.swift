import KioskLocalization

#if os(iOS)
  import KioskCore
  import SwiftUI
  import UIKit

  struct PassiveExternalControl: UIViewRepresentable {
    @Environment(\.locale) private var locale
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
      view.accessibilityLabel = L10n.string("外部展示の操作", locale: locale)
    }
  }

  /// Renders the device's input surface and emits typed intents; owns no browser state.
  @MainActor
  final class MobileExternalControlView: UIView {
    var send: ((ExternalWebControl) -> Void)?
    var pointerCaptured = false
    var allowsDrag = false { didSet { dragGesture.isEnabled = allowsDrag } }
    private let scrolling = MobileScrollInputView()
    private lazy var dragGesture = UILongPressGestureRecognizer(
      target: self, action: #selector(drag(_:)))
    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .black
      isAccessibilityElement = true
      accessibilityIdentifier = "external-control"
      addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
      addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(activate(_:))))
      dragGesture.minimumPressDuration = 0.25
      dragGesture.isEnabled = false
      addGestureRecognizer(dragGesture)
      scrolling.panGestureRecognizer.require(toFail: dragGesture)
      scrolling.send = { [weak self] delta in
        guard let self else { return }
        #if DEBUG
          if ProcessInfo.processInfo.environment["PLINTH_TEST_SCROLL_DIAGNOSTICS"] == "1",
            self.scrolling.isDecelerating
          {
            self.accessibilityValue = "momentum"
          }
        #endif
        self.send?(.scroll(dx: Double(delta.x), dy: Double(delta.y)))
      }
      addSubview(scrolling)
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
    override func layoutSubviews() {
      super.layoutSubviews()
      scrolling.frame = bounds
    }
    override var isUserInteractionEnabled: Bool {
      didSet { if !isUserInteractionEnabled { scrolling.stop() } }
    }
  }

#endif
