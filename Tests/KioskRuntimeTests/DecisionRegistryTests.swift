import KioskCore
import KioskMacApp
import KioskRuntime
import Testing

@MainActor
private final class RequestReference {
  var id: UInt64 = 0
}

@MainActor
struct DecisionRegistryTests {
  @Test func removesCallbackBeforeReentrantCompletion() {
    let registry = DecisionRegistry()
    var decisions: [NavigationDecision] = []
    let request = RequestReference()
    request.id = registry.register(generation: 2) { decision in
      decisions.append(decision)
      #expect(registry.resolve(request.id, generation: 2, decision: .allow) == false)
    }
    #expect(registry.resolve(request.id, generation: 2, decision: .allow))
    #expect(registry.resolve(request.id, generation: 2, decision: .allow) == false)
    #expect(decisions == [.allow])
    #expect(registry.pendingCount == 0)
  }

  @Test func closeCancelsOutstandingAndReentrantRegistrationsExactlyOnce() {
    let registry = DecisionRegistry()
    var decisions: [NavigationDecision] = []
    registry.register(generation: 1) { decision in
      decisions.append(decision)
      registry.register(generation: 2) { decisions.append($0) }
    }
    registry.close()
    registry.close()
    #expect(decisions == [.cancel(.staleOperation), .cancel(.staleOperation)])
    #expect(registry.pendingCount == 0)
  }

  @Test func generationMismatchCancelsInsteadOfAllowing() {
    let registry = DecisionRegistry()
    var decisions: [NavigationDecision] = []
    let id = registry.register(generation: 1) { decisions.append($0) }
    registry.resolve(id, generation: 2, decision: .allow)
    #expect(decisions == [.cancel(.staleOperation)])
  }
}
