import KioskCore
import KioskMacApp
import KioskRuntime
import Testing

@MainActor
private final class OperationGate {
  private var result: CheckedContinuation<Event?, Never>?
  private var started: [CheckedContinuation<Void, Never>] = []
  private var hasStarted = false
  func operation() async -> Event? {
    await withCheckedContinuation { continuation in
      result = continuation
      hasStarted = true
      let waiters = started
      started.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }
  func waitUntilStarted() async {
    if hasStarted { return }
    await withCheckedContinuation { started.append($0) }
  }
  func finish(_ event: Event?) {
    let continuation = result
    result = nil
    continuation?.resume(returning: event)
  }
}

@MainActor
private final class PendingScenePort: EffectPort {
  let gate = OperationGate()
  private(set) var cancelled: [OperationToken] = []
  func perform(_ effect: Effect) async -> Event? { await gate.operation() }
  func cancel(_ token: OperationToken) {
    cancelled.append(token)
    gate.finish(.externalScenePreparationFailed(token))
  }
  func stop() { gate.finish(nil) }
}

@MainActor
struct EffectTaskRegistryTests {
  @Test func cancellationInvalidatesCompletionBeforeClosingTheNativeWaiter() async {
    let port = PendingScenePort()
    let executor = EffectExecutor(port: port)
    defer { executor.stop() }
    let token = OperationToken(owner: .root, operationID: 1)
    var events: [Event] = []
    executor.resultSink = { event, _ in events.append(event) }
    executor.execute(.init(token, .prepareExternalScene))
    await port.gate.waitUntilStarted()
    executor.execute(.init(.init(owner: .root, operationID: 2), .cancelOperation(token)))
    await executor.registry.waitForOperation(token)
    #expect(port.cancelled == [token])
    #expect(events.isEmpty)
    #expect(executor.registry.pendingCount == 0)
  }
  @Test func cancellationBeforeStartPreventsPerformingOperation() async {
    let registry = EffectTaskRegistry()
    let token = OperationToken(owner: .root, operationID: 1)
    var performed = false
    registry.start(
      token,
      operation: {
        performed = true
        return nil
      },
      completion: { _ in Issue.record("Cancelled completion delivered") }
    )
    registry.cancel(token)
    await registry.waitForOperation(token)
    #expect(performed == false)
    #expect(registry.pendingCount == 0)
  }

  @Test func cancellationRejectsResultEvenWhenOperationIgnoresCancellation() async {
    let registry = EffectTaskRegistry()
    let gate = OperationGate()
    let token = OperationToken(owner: .administration, operationID: 1)
    var results: [Event] = []
    registry.start(token, operation: { await gate.operation() }, completion: { results.append($0) })
    await gate.waitUntilStarted()
    registry.cancel(token)
    gate.finish(.authenticationVerified(unlockID: 1))
    await registry.waitForOperation(token)
    #expect(results.isEmpty)
    #expect(registry.pendingCount == 0)
  }

  @Test func completionWaitIncludesDeliveryAndKeepsOtherOwnersIndependent() async {
    let registry = EffectTaskRegistry()
    let first = OperationGate()
    let second = OperationGate()
    let firstToken = OperationToken(owner: .exhibition, operationID: 1, webGeneration: 1)
    let secondToken = OperationToken(owner: .administration, operationID: 1)
    var results: [Event] = []
    registry.start(
      firstToken, operation: { await first.operation() }, completion: { results.append($0) })
    registry.start(
      secondToken, operation: { await second.operation() }, completion: { results.append($0) })
    await first.waitUntilStarted()
    await second.waitUntilStarted()
    registry.cancel(firstToken)
    first.finish(.exhibitionReady)
    second.finish(.authenticationVerified(unlockID: 5))
    await registry.waitForOperation(firstToken)
    await registry.waitForOperation(secondToken)
    #expect(results == [.authenticationVerified(unlockID: 5)])
    #expect(registry.pendingCount == 0)
  }
}
