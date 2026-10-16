import AppKit

@MainActor
final class DisplayShieldWindow: NSWindow {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(frame: CGRect, unlockTitle: String? = nil) {
    super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    isMovable = false
    backgroundColor = .black
    isOpaque = true
    hasShadow = false
    level = .mainMenu
    if let unlockTitle { showUnlockHint(unlockTitle) }
  }

  private func showUnlockHint(_ title: String) {
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 20, weight: .medium)
    titleLabel.textColor = .white.withAlphaComponent(0.8)
    titleLabel.alignment = .center
    titleLabel.setAccessibilityIdentifier("shield-unlock-title")

    let shortcutLabel = NSTextField(labelWithString: "⌘ ⌥ ⇧ K")
    shortcutLabel.font = .monospacedSystemFont(ofSize: 30, weight: .semibold)
    shortcutLabel.textColor = .white
    shortcutLabel.alignment = .center
    shortcutLabel.setAccessibilityIdentifier("shield-unlock-shortcut")

    let stack = NSStackView(views: [titleLabel, shortcutLabel])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentView?.addSubview(stack)
    guard let contentView else { return }
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      stack.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -32),
    ])
  }
}
