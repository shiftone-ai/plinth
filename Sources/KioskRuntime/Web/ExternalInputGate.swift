import Foundation
import KioskCore

/// Serializes DOM operations and keeps only the latest pending move in each input sequence.
@MainActor
final class ExternalInputGate {
  struct QueueFull: Error {}
  struct Permit: Sendable {
    let id: UUID
    let control: ExternalWebControl
  }
  private struct Waiting {
    let permit: Permit
    let completion: AsyncStream<Permit>.Continuation
  }
  private var active: UUID?
  private var waiting: [Waiting] = []
  var pendingCount: Int { waiting.count }

  func enqueue(_ control: ExternalWebControl) throws -> AsyncStream<Permit> {
    var permit = Permit(id: UUID(), control: control)
    let channel = AsyncStream<Permit>.makeStream(bufferingPolicy: .bufferingNewest(1))
    if active == nil {
      active = permit.id
      channel.continuation.yield(permit)
      channel.continuation.finish()
    } else {
      if case .move = control, let previous = waiting.last,
        case .move = previous.permit.control
      {
        waiting.removeLast().completion.finish()
      }
      if case .scroll(let dx, let dy) = control, let previous = waiting.last,
        case .scroll(let previousX, let previousY) = previous.permit.control,
        (previousX + dx).isFinite, (previousY + dy).isFinite
      {
        waiting.removeLast().completion.finish()
        permit = Permit(
          id: permit.id,
          control: .scroll(dx: previousX + dx, dy: previousY + dy))
      }
      guard waiting.count < 64 else {
        channel.continuation.finish()
        throw QueueFull()
      }
      waiting.append(.init(permit: permit, completion: channel.continuation))
    }
    return channel.stream
  }

  func finish(_ permit: Permit) {
    guard active == permit.id else { return }
    if waiting.isEmpty {
      active = nil
      return
    }
    let next = waiting.removeFirst()
    active = next.permit.id
    next.completion.yield(next.permit)
    next.completion.finish()
  }

  func reset() {
    active = nil
    let previous = waiting
    waiting.removeAll()
    for item in previous { item.completion.finish() }
  }
}
