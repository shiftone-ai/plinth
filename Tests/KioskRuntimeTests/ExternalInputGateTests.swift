import KioskCore
import Testing

@testable import KioskRuntime

@MainActor
struct ExternalInputGateTests {
  @Test func coalescingPreservesPressReleaseOrderAndBoundsPendingMotion() async throws {
    let gate = ExternalInputGate()
    var initial = try gate.enqueue(.press(.init(x: 0.1, y: 0.1))).makeAsyncIterator()
    let pressed = try #require(await initial.next())
    var old = try gate.enqueue(.move(.init(x: 0.2, y: 0.2))).makeAsyncIterator()
    for index in 3..<1000 { _ = try gate.enqueue(.move(.init(x: Double(index) / 1000, y: 0.5))) }
    var latest = try gate.enqueue(.move(.init(x: 1, y: 0.5))).makeAsyncIterator()
    var release = try gate.enqueue(.release(.init(x: 1, y: 0.5))).makeAsyncIterator()
    #expect(gate.pendingCount == 2)
    #expect(await old.next() == nil)
    gate.finish(pressed)
    let moved = try #require(await latest.next())
    #expect(moved.control == .move(.init(x: 1, y: 0.5)))
    gate.finish(moved)
    let released = try #require(await release.next())
    #expect(released.control == .release(.init(x: 1, y: 0.5)))
    gate.finish(released)
    #expect(gate.pendingCount == 0)
  }

  @Test func resetFinishesWaitersAndOldCompletionCannotAdvanceNewSurface() async throws {
    let gate = ExternalInputGate()
    var initial = try gate.enqueue(.move(.init(x: 0.1, y: 0.1))).makeAsyncIterator()
    let old = try #require(await initial.next())
    var waiting = try gate.enqueue(.activate(.init(x: 0.5, y: 0.5))).makeAsyncIterator()
    gate.reset()
    #expect(await waiting.next() == nil)
    var current = try gate.enqueue(.press(.init(x: 0.5, y: 0.5))).makeAsyncIterator()
    let active = try #require(await current.next())
    var release = try gate.enqueue(.release(.init(x: 0.5, y: 0.5))).makeAsyncIterator()
    gate.finish(old)
    #expect(gate.pendingCount == 1)
    gate.finish(active)
    #expect(await release.next() != nil)
    gate.reset()
  }
  @Test func aBlockedPageCannotAccumulateUnboundedClicks() throws {
    let gate = ExternalInputGate()
    defer { gate.reset() }
    let point = SurfacePoint(x: 0.5, y: 0.5)
    _ = try gate.enqueue(.press(point))
    for _ in 0..<64 { _ = try gate.enqueue(.activate(point)) }
    #expect(gate.pendingCount == 64)
    #expect(throws: ExternalInputGate.QueueFull.self) { _ = try gate.enqueue(.release(point)) }
  }

}
