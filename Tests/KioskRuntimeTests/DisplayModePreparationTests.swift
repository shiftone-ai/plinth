import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
private final class ModePresentation: PresentationPort {
  var immediateResult: Bool?
  private var pending: CheckedContinuation<Bool, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var requested: [ExternalDisplayMode?] = []
  private(set) var applied: [PresentationRequest] = []
  private(set) var cancelled: [OperationToken] = []

  func apply(_ request: PresentationRequest) -> Bool {
    applied.append(request)
    return true
  }
  func release() { finish(false) }
  func prepareExternalScene(_ token: OperationToken) async -> Bool { false }
  func cancelScenePreparation(_ token: OperationToken) {}
  func prepareExternalDisplayMode(_ mode: ExternalDisplayMode?, token: OperationToken) async -> Bool
  {
    requested.append(mode)
    if let immediateResult { return immediateResult }
    return await withCheckedContinuation { continuation in
      pending = continuation
      let started = waiters
      waiters.removeAll()
      for waiter in started { waiter.resume() }
    }
  }
  func waitUntilPreparing() async {
    if pending != nil { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func finish(_ result: Bool) {
    let continuation = pending
    pending = nil
    continuation?.resume(returning: result)
  }
  func cancelDisplayModePreparation(_ token: OperationToken) {
    cancelled.append(token)
    finish(false)
  }
}

@MainActor
private final class ModeWeb: WebSurfacePort {
  func create(_ token: OperationToken, mode: ResetMode, interaction: InteractionPolicy) {}
  func load(_ address: String, token: OperationToken) -> Bool { true }
  func releaseSurface() {}
  func stop() {}
}

@MainActor
private final class ModeDisplay: DisplayReadingPort {
  let count = 1
  let exhibitionFrame: CGRect? = .init(x: 0, y: 0, width: 1920, height: 1080)
}

@MainActor
struct DisplayModePreparationTests {
  private func executor(_ presentation: ModePresentation) -> EffectExecutor {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-mode-\(UUID())")
    return EffectExecutor(
      port: NativeEffectPort(
        web: ModeWeb(), presentation: presentation,
        repository: ProfileRepository(fileURL: directory.appendingPathComponent("profile.json")),
        credentials: CredentialStore(service: "ai.shiftone.plinth.tests.\(UUID())"),
        clock: FakeClock(), displays: ModeDisplay()))
  }

  @Test(arguments: [false, true], [false, true])
  func presentationStartsOnlyAfterSuccessfulModePreparation(succeeded: Bool, explicitMode: Bool)
    async
  {
    let presentation = ModePresentation()
    presentation.immediateResult = succeeded
    let executor = executor(presentation)
    defer { executor.stop() }
    let mode = explicitMode ? ExternalDisplayMode(width: 1920, height: 1080) : nil
    let request = PresentationRequest(externalDisplayMode: mode, usesExternalDisplay: true)
    let token = OperationToken(owner: .root, operationID: 1)
    var events: [Event] = []
    executor.resultSink = { event, _ in events.append(event) }
    executor.execute(.init(token, .applyPresentation(request)))
    await executor.registry.waitForOperation(token)
    #expect(presentation.requested == [mode])
    #expect(presentation.applied == (succeeded ? [request] : []))
    #expect(events == [succeeded ? .presentationApplied(token) : .presentationFailed(token)])
    #expect(executor.registry.pendingCount == 0)
  }

  @Test func cancellingPreparationCannotStartPresentationOrDeliverALateSuccess() async {
    let presentation = ModePresentation()
    let executor = executor(presentation)
    defer { executor.stop() }
    let token = OperationToken(owner: .root, operationID: 1)
    var events: [Event] = []
    executor.resultSink = { event, _ in events.append(event) }
    executor.execute(
      .init(
        token,
        .applyPresentation(
          .init(
            externalDisplayMode: .init(width: 1920, height: 1080)))))
    await presentation.waitUntilPreparing()
    executor.execute(.init(.init(owner: .root, operationID: 2), .cancelOperation(token)))
    await executor.registry.waitForOperation(token)
    presentation.finish(true)
    #expect(presentation.cancelled.contains(token))
    #expect(presentation.applied.isEmpty)
    #expect(events.isEmpty)
    #expect(executor.registry.pendingCount == 0)
  }
}
