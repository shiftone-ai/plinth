import KioskCore
import KioskPresentation

/// Owns the root tree, stores, clock, executor, and their explicit stop boundary.
@MainActor
public final class RootRuntime {
  public let rootNode: ComponentNode
  public let rootProps: RenderPropsStore<RootProps>
  public let settingsProps: RenderPropsStore<SettingsProps>
  public let webProps: RenderPropsStore<WebSurfaceProps>
  public let unlockProps: RenderPropsStore<UnlockProps>
  public let webAdministrationProps: RenderPropsStore<WebAdministrationProps>
  public private(set) var reports: [DispatchReport] = []
  public var snapshot: TreeSnapshot { store.snapshot }
  private let store = ScopedStateStore()
  private let nodes: [NodeID: ComponentNode]
  private let clock: any ClockPort
  private let executor: any EffectExecuting
  private let diagnostics: (any DiagnosticPort)?
  private let traceLimit: Int
  private var nextID: UInt64 = 0
  private var processing = false
  private var stopped = false
  private var queuedFacts: [(Event, NodeID)] = []

  public init(
    clock: any ClockPort, executor: any EffectExecuting, traceLimit: Int = 256,
    diagnostics: (any DiagnosticPort)? = nil
  ) {
    precondition(traceLimit >= 0)
    self.clock = clock
    self.executor = executor
    self.diagnostics = diagnostics
    self.traceLimit = traceLimit
    let root = ComponentNode(id: .root)
    var nodes: [NodeID: ComponentNode] = [.root: root]
    for id in NodeID.allCases where id != .root { nodes[id] = ComponentNode(id: id) }
    for id in NodeID.allCases {
      if let parent = id.parent, let child = nodes[id] { nodes[parent]?.attach(child) }
    }
    self.nodes = nodes
    self.rootNode = root
    rootProps = RenderPropsStore(Presenters.root(store.root))
    settingsProps = RenderPropsStore(Presenters.settings(store.root, store.administration))
    webProps = RenderPropsStore(Presenters.web(store.root, store.exhibition))
    unlockProps = RenderPropsStore(
      Presenters.unlock(
        store.root, store.administration, now: clock.now))
    webAdministrationProps = RenderPropsStore(
      Presenters.webAdministration(store.root, store.administration))
    executor.resultSink = { [weak self] event, source in self?.send(event, from: source) }
  }

  @discardableResult
  public func send(_ event: Event, from source: NodeID) -> DispatchReport {
    nextID += 1
    let envelope = EventEnvelope(
      eventID: nextID, source: source, timestamp: clock.now, event: event)
    if stopped { return report(envelope, path: [], handler: nil, reply: .rejected(.invalidState)) }
    if processing {
      if event.requiresReply {
        return report(envelope, path: [], handler: nil, reply: .rejected(.reentrantRequest))
      }
      queuedFacts.append((event, source))
      return report(envelope, path: [], handler: nil, reply: nil)
    }
    processing = true
    var effects: [Effect] = []
    var result = route(envelope, ingress: source, effects: &effects)
    project()
    if let record = DiagnosticRecord(event: event, report: result, snapshot: snapshot) {
      diagnostics?.record(record)
    }
    processing = false
    // Effects may synchronously re-enter; the complete state and Props are already committed.
    for effect in effects where !stopped && isCurrent(effect) { executor.execute(effect) }
    let facts = queuedFacts
    queuedFacts.removeAll()
    for (fact, origin) in facts { send(fact, from: origin) }
    if result.reply == nil && event.requiresReply {
      result = report(
        envelope, path: result.path, handler: result.handler, reply: .rejected(.unhandledRequest))
    }
    return result
  }

  public func project() {
    rootProps.apply(Presenters.root(store.root))
    settingsProps.apply(Presenters.settings(store.root, store.administration))
    webProps.apply(Presenters.web(store.root, store.exhibition))
    unlockProps.apply(Presenters.unlock(store.root, store.administration, now: clock.now))
    webAdministrationProps.apply(Presenters.webAdministration(store.root, store.administration))
  }

  public func stop() {
    guard !stopped else { return }
    stopped = true
    store.root.epoch += 1
    store.exhibition.epoch += 1
    store.administration.epoch += 1
    executor.stop()
    queuedFacts.removeAll()
  }

  private func isCurrent(_ effect: Effect) -> Bool {
    switch effect.kind {
    case .openInformationPage:
      store.root.mode == .administration && store.root.informationPageOperation == effect.token
    case .bootstrap: store.root.bootstrapOperation == effect.token
    case .prepareExternalScene: store.root.externalSceneOperation == effect.token
    case .captureExternalPointer: store.root.pointerCaptureOperation == effect.token
    case .releaseExternalPointer: !store.root.externalPointerLocked
    case .confineNativePointer:
      store.root.presentationAcquired
        && [.enteringKiosk, .exhibiting, .unlocking].contains(store.root.mode)
    case .applyPresentation, .releasePresentation: store.root.presentationOperation == effect.token
    case .saveProfile: store.root.saveOperation == effect.token
    case .startWebServer: store.root.webServerOperation == effect.token
    case .stopWebServer: true
    case .createSurface, .load: store.exhibition.operation == effect.token
    case .controlExternalWeb:
      store.root.mode == .exhibiting && store.root.epoch == effect.token.ownerEpoch
        && store.exhibition.generation == effect.token.webGeneration
        && store.exhibition.inputAvailable
    case .releaseSurface: store.exhibition.releaseOperation == effect.token
    case .scheduleIdle: store.exhibition.idleOperation == effect.token
    case .scheduleRetry: store.exhibition.retryOperation == effect.token
    case .scheduleUnlockTimeout: store.root.unlockTimeoutOperation == effect.token
    case .verifyPasscode:
      store.administration.verification == effect.token
        || store.administration.webVerification == effect.token
    case .configurePasscode: store.root.credentialOperation == effect.token
    case .readBiometricStatus: store.root.biometricStatusOperation == effect.token
    case .changeBiometricUnlock: store.root.biometricOperation == effect.token
    case .performBiometricUnlock: store.root.biometricUnlockOperation == effect.token
    case .cancelOperation: true
    }
  }

  private func route(_ envelope: EventEnvelope, ingress: NodeID, effects: inout [Effect])
    -> DispatchReport
  {
    var node = nodes[ingress]
    var path: [NodeID] = []
    while let current = node {
      path.append(current.id)
      let output: (Reply?, [Effect], [Event], [ChildControl])?
      switch current.id {
      case .root:
        if case .handled(let value) = RootMediator.reduce(
          store.root, envelope, context: store.context)
        {
          store.root = value.state
          output = (value.reply, value.effects, value.parentEvents, value.childControls)
        } else {
          output = nil
        }
      case .exhibition:
        if case .handled(let value) = ExhibitionMediator.reduce(store.exhibition, envelope) {
          store.exhibition = value.state
          output = (value.reply, value.effects, value.parentEvents, value.childControls)
        } else {
          output = nil
        }
      case .administration:
        if case .handled(let value) = AdministrationMediator.reduce(
          store.administration, envelope, mode: store.root.mode,
          webEnabled: store.root.savedProfile?.webAdministrationEnabled == true
            && store.root.credentialsConfigured,
          webOutputOptions: WebOutputOptions(
            macDisplays: store.root.macDisplays, mobileDisplays: store.root.mobileDisplays))
        {
          store.administration = value.state
          output = (value.reply, value.effects, value.parentEvents, value.childControls)
        } else {
          output = nil
        }
      default: output = nil
      }
      if let (reply, selected, parents, controls) = output {
        effects.append(contentsOf: selected)
        var resolvedReply = reply
        let initial = report(envelope, path: path, handler: current.id, reply: reply)
        for event in parents {
          guard let parent = current.parent else { continue }
          let derived = derivedEnvelope(event, source: current.id, cause: envelope.eventID)
          let parentReport = route(derived, ingress: parent.id, effects: &effects)
          if event.requiresReply, case .rejected = parentReport.reply {
            resolvedReply = parentReport.reply
          }
        }
        for control in controls {
          let derived = derivedEnvelope(control.event, source: current.id, cause: envelope.eventID)
          _ = route(derived, ingress: control.target, effects: &effects)
        }
        let resolved = DispatchReport(
          eventID: initial.eventID, source: initial.source, path: initial.path,
          handler: initial.handler, reply: resolvedReply, causationID: initial.causationID)
        if let index = reports.firstIndex(where: { $0.eventID == resolved.eventID }) {
          reports[index] = resolved
        }
        return resolved
      }
      node = current.parent
    }
    return report(
      envelope, path: path, handler: nil,
      reply: envelope.event.requiresReply ? .rejected(.unhandledRequest) : nil)
  }

  private func derivedEnvelope(_ event: Event, source: NodeID, cause: UInt64) -> EventEnvelope {
    nextID += 1
    return EventEnvelope(
      eventID: nextID, source: source, timestamp: clock.now, causationID: cause, event: event)
  }

  private func report(_ envelope: EventEnvelope, path: [NodeID], handler: NodeID?, reply: Reply?)
    -> DispatchReport
  {
    let result = DispatchReport(
      eventID: envelope.eventID, source: envelope.source, path: path,
      handler: handler, reply: reply, causationID: envelope.causationID)
    if traceLimit > 0 {
      if reports.count == traceLimit { reports.removeFirst() }
      reports.append(result)
    }
    return result
  }
}
