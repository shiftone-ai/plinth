import Foundation

public enum RejectionReason: String, Codable, Sendable {
  case invalidState, wrongSource, staleOperation, invalidProfile, unsavedDraft, unauthenticated
  case unsupportedDisplays, invalidURL, httpDisabled, urlBlocked, unsupportedWindow, cooldown
  case alreadySaving, unhandledRequest, reentrantRequest
}

public enum Reply: Equatable, Sendable {
  case accepted
  case rejected(RejectionReason)
  case navigation(NavigationDecision)
  case input(InputDecision)
}

public struct ChildControl: Equatable, Sendable {
  public let target: NodeID
  public let event: Event
  public init(_ target: NodeID, _ event: Event) {
    self.target = target
    self.event = event
  }
}

public struct Transition<State: Equatable & Sendable>: Equatable, Sendable {
  public var state: State
  public var reply: Reply?
  public var effects: [Effect]
  public var parentEvents: [Event]
  public var childControls: [ChildControl]

  public init(
    _ state: State, reply: Reply? = nil, effects: [Effect] = [],
    parentEvents: [Event] = [], childControls: [ChildControl] = []
  ) {
    self.state = state
    self.reply = reply
    self.effects = effects
    self.parentEvents = parentEvents
    self.childControls = childControls
  }
}

public enum Mediation<State: Equatable & Sendable>: Equatable, Sendable {
  case bubble
  case handled(Transition<State>)

  public static func reject(_ state: State, _ reason: RejectionReason) -> Self {
    .handled(Transition(state, reply: .rejected(reason)))
  }
}

public struct ReadonlyContext: Sendable {
  public var webAvailable: Bool
  public var webGeneration: UInt64
  public var hasUnsavedDraft: Bool
  public var catalogSelectionID: UUID?
  public var catalogRequiresAvailableOutput: Bool

  public init(
    webAvailable: Bool = false, webGeneration: UInt64 = 0, hasUnsavedDraft: Bool = false,
    catalogSelectionID: UUID? = nil, catalogRequiresAvailableOutput: Bool = false
  ) {
    self.webAvailable = webAvailable
    self.webGeneration = webGeneration
    self.hasUnsavedDraft = hasUnsavedDraft
    self.catalogSelectionID = catalogSelectionID
    self.catalogRequiresAvailableOutput = catalogRequiresAvailableOutput
  }
}
