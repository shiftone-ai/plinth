#if os(iOS)
  import UIKit

  /// A native input surface whose offset changes include UIKit-managed deceleration.
  @MainActor
  final class MobileScrollInputView: UIScrollView, UIScrollViewDelegate {
    var send: ((CGPoint) -> Void)?
    // Leave room in both directions; recenter only after native scrolling has stopped.
    private let origin = CGPoint(x: 500_000, y: 500_000)
    private var previous = CGPoint(x: 500_000, y: 500_000)
    private var rebasing = false
    override init(frame: CGRect) {
      super.init(frame: frame)
      contentSize = CGSize(width: 1_000_000, height: 1_000_000)
      contentOffset = origin
      contentInsetAdjustmentBehavior = .never
      showsHorizontalScrollIndicator = false
      showsVerticalScrollIndicator = false
      bounces = false
      scrollsToTop = false
      decelerationRate = .normal
      panGestureRecognizer.allowedScrollTypesMask = .all
      delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      guard !rebasing else { return }
      let next = contentOffset
      let delta = CGPoint(x: next.x - previous.x, y: next.y - previous.y)
      previous = next
      if delta != .zero { send?(delta) }
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      if !decelerate { rebase() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { rebase() }
    private func rebase() {
      rebasing = true
      previous = origin
      contentOffset = origin
      rebasing = false
    }
    func stop() {
      rebasing = true
      stopScrollingAndZooming()
      rebasing = false
      rebase()
    }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window == nil { stop() }
    }
  }
#endif
