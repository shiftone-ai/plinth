public struct InteractionPolicy: Equatable, Codable, Sendable {
  public var allowsScroll: Bool
  public var allowsDrag: Bool
  public init(allowsScroll: Bool = false, allowsDrag: Bool = false) {
    self.allowsScroll = allowsScroll
    self.allowsDrag = allowsDrag
  }
}

public enum InputScope: Equatable, Sendable {
  case web, authentication, administration, administratorEntry
}
public enum NativeInput: Equatable, Sendable {
  case cursorMoved, primaryDown, primaryUp, primaryDrag, scroll, otherButton, gesture, key,
    applicationShortcut, touchMoved
}

public struct InputState: Equatable, Sendable {
  public var pressedGeneration: UInt64?
  public var pressedScope: InputScope?
  public init(pressedGeneration: UInt64? = nil, pressedScope: InputScope? = nil) {
    self.pressedGeneration = pressedGeneration
    self.pressedScope = pressedScope ?? (pressedGeneration == nil ? nil : .web)
  }
}

public struct InputDecision: Equatable, Sendable {
  public let passes: Bool
  public let recordsVisitorActivity: Bool
  public let state: InputState
}

public enum InputPolicy {
  public static func evaluate(
    _ input: NativeInput, scope: InputScope, mode: AppMode,
    webAvailable: Bool, generation: UInt64,
    policy: InteractionPolicy, state: InputState
  ) -> InputDecision {
    let administratorEntry =
      scope == .administratorEntry
      && [.exhibiting, .enteringKiosk, .safeHold, .paused].contains(mode)
    if administratorEntry || (mode == .administration && scope == .administration)
      || (mode == .unlocking && scope == .authentication)
    {
      var next = state
      let passes: Bool
      switch input {
      case .primaryUp:
        passes = state.pressedScope == scope
        next.pressedScope = nil
        next.pressedGeneration = nil
      case .primaryDown:
        passes = true
        next.pressedScope = scope
        next.pressedGeneration = nil
      case .primaryDrag, .touchMoved: passes = state.pressedScope == scope
      case .applicationShortcut: passes = false
      default: passes = !administratorEntry || input == .cursorMoved
      }
      return InputDecision(passes: passes, recordsVisitorActivity: false, state: next)
    }
    var next = state
    let available = mode == .exhibiting && scope == .web && webAvailable
    var passes = false
    switch input {
    case .primaryUp:
      passes = available && state.pressedScope == .web && state.pressedGeneration == generation
      next.pressedGeneration = nil
      next.pressedScope = nil
    case .primaryDown:
      passes =
        available
        && (state.pressedScope != .web || state.pressedGeneration == generation)
      if passes {
        next.pressedGeneration = generation
        next.pressedScope = .web
      }
    case .cursorMoved: passes = available
    case .primaryDrag:
      passes =
        available && policy.allowsDrag && state.pressedScope == .web
        && state.pressedGeneration == generation
    case .touchMoved:
      passes =
        available && (policy.allowsScroll || policy.allowsDrag)
        && state.pressedScope == .web && state.pressedGeneration == generation
    case .scroll: passes = available && policy.allowsScroll
    case .otherButton, .gesture, .key, .applicationShortcut: passes = false
    }
    return InputDecision(passes: passes, recordsVisitorActivity: passes, state: next)
  }
}
