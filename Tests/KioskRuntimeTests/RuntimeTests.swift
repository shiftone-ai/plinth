import KioskCore
import KioskMacApp
import KioskRuntime
import Testing

@MainActor
struct RuntimeTests {
  @Test func passcodeSetupUsesAdministrationInputAndPropagatesRootRejection() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    runtime.send(.passcodeEdited("short"), from: .settings)
    let rejected = runtime.send(.configurePasscodeRequested, from: .settings)
    #expect(rejected.reply == .rejected(.invalidProfile))
    #expect(fixture.port.effects.isEmpty)
    runtime.send(.passcodeEdited("current-admin-passcode"), from: .settings)
    let accepted = runtime.send(.configurePasscodeRequested, from: .settings)
    #expect(accepted.path == [.settings, .administration])
    #expect(accepted.reply == .accepted)
    #expect(fixture.port.effects.map(\.kind) == [.configurePasscode("current-admin-passcode")])
    #expect(
      runtime.reports.contains {
        $0.source == .administration && $0.handler == .root && $0.causationID == accepted.eventID
      })
  }
  @Test func administratorCanCancelUnlockWhileFirstPageIsStillLoading() throws {
    let fixture = RuntimeFixture()
    let runtime = fixture.runtime
    runtime.send(
      .bootstrapped(profile: try fixture.profile(), credentialsConfigured: true, displayCount: 1),
      from: .root)
    let presentation = try #require(runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationApplied(presentation), source: .platform)
    let create = try #require(runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.surfaceCreated(create), source: .webSurface)
    #expect(runtime.snapshot.root.mode == .enteringKiosk)
    #expect(runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    #expect(runtime.snapshot.root.mode == .unlocking)
    let load = try #require(runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.webFinished(load), source: .webSurface)
    #expect(runtime.snapshot.root.mode == .unlocking)
    runtime.send(.cancelAuthentication, from: .unlock)
    #expect(runtime.snapshot.root.mode == .exhibiting)
    #expect(runtime.snapshot.exhibition.phase == .quiescing)
    #expect(runtime.webProps.props.acceptsInput == false)
  }
  @Test func parentRejectionReachesCallerAndTraceWithoutLeavingDraftBusy() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    let profile = try fixture.profile()
    fixture.runtime.send(.profileCommitRequested(profile), from: .administration)
    fixture.runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .navigationRules)
    let reply = fixture.runtime.send(.saveDraftRequested, from: .settings)
    #expect(reply.reply == .rejected(.alreadySaving))
    #expect(fixture.runtime.snapshot.administration.saving == false)
    let recorded = try #require(fixture.runtime.reports.first { $0.eventID == reply.eventID })
    #expect(recorded.reply == reply.reply)
    #expect(fixture.port.effects.count == 1)
  }

  @Test func allNodesHaveOneReachableParentAndNoSiblingRoutes() {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    var ids: [NodeID] = []
    func visit(_ node: ComponentNode) {
      ids.append(node.id)
      for child in node.children {
        #expect(child.parent === node)
        #expect(child.id.parent == node.id)
        visit(child)
      }
    }
    visit(fixture.runtime.rootNode)
    #expect(Set(ids) == Set(NodeID.allCases))
    #expect(ids.count == NodeID.allCases.count)
    #expect(fixture.runtime.rootNode.parent == nil)
  }

  @Test func stateAndPropsCommitBeforeEffectsAndReentrantFacts() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.port.onExecute = { effect in
      if effect.kind == .applyPresentation(.init()) {
        #expect(fixture.runtime.snapshot.root.mode == .enteringKiosk)
        #expect(fixture.runtime.rootProps.props.mode == .enteringKiosk)
        fixture.port.deliver(.presentationApplied(effect.token), source: .platform)
      }
    }
    fixture.runtime.send(
      .bootstrapped(profile: try fixture.profile(), credentialsConfigured: true, displayCount: 1),
      from: .root)
    #expect(fixture.runtime.snapshot.exhibition.phase == .preparing)
    #expect(
      fixture.port.effects.map(\.kind) == [
        .applyPresentation(.init()), .createSurface(.newVisitorSession),
      ])
  }

  @Test func knownRejectedEventStopsAtOwnerAndUnownedEventBubbles() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    let edited = fixture.runtime.send(
      .draftChanged(ProfileDraft(profile: try fixture.profile())), from: .settings)
    #expect(edited.path == [.settings, .administration])
    #expect(edited.handler == .administration)
    #expect(edited.reply == .rejected(.invalidState))
    let start = fixture.runtime.send(.startExhibitionRequested, from: .settings)
    #expect(start.path == [.settings, .administration, .root])
    #expect(start.handler == .root)
    #expect(start.reply == .rejected(.invalidState))
    let fact = fixture.runtime.send(.unrelatedFact, from: .webSurface)
    #expect(fact.path == [.webSurface, .exhibition, .root])
    #expect(fact.handler == nil)
  }

  @Test func resetSuppressesInputAndOldCompletionWhileAcceptingRelease() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    let oldLoad = try #require(fixture.runtime.snapshot.exhibition.operation)
    let down = fixture.runtime.send(.nativeInput(.primaryDown, .web), from: .platform)
    guard case .input(let decision) = down.reply else {
      Issue.record("Expected synchronous input reply")
      return
    }
    #expect(decision.passes)
    let idle = try #require(fixture.runtime.snapshot.exhibition.idleOperation)
    fixture.clock.advance(by: 120)
    fixture.port.deliver(.idleDeadlineReached(idle), source: .idleClock)
    #expect(fixture.runtime.snapshot.exhibition.phase == .quiescing)
    #expect(fixture.runtime.webProps.props.acceptsInput == false)
    fixture.port.deliver(.webFinished(oldLoad), source: .webSurface)
    #expect(fixture.runtime.snapshot.exhibition.phase == .quiescing)
    let release = try #require(fixture.runtime.snapshot.exhibition.releaseOperation)
    fixture.port.deliver(.surfaceReleased(release), source: .webSurface)
    let create = try #require(fixture.runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.surfaceCreated(create), source: .webSurface)
    let load = try #require(fixture.runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.webFinished(load), source: .webSurface)
    #expect(fixture.runtime.snapshot.exhibition.phase == .ready)
    let up = fixture.runtime.send(.nativeInput(.primaryUp, .web), from: .platform)
    guard case .input(let upDecision) = up.reply else {
      Issue.record("Expected synchronous input reply")
      return
    }
    #expect(upDecision.passes == false)
    #expect(fixture.runtime.snapshot.exhibition.idleDeadline == nil)
  }

  @Test func cancelledUnlockCannotAcceptLateSuccessAndRestoresFreshVisitor() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    #expect(fixture.runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    fixture.runtime.send(.passcodeEdited("fixture"), from: .unlock)
    #expect(fixture.runtime.send(.passcodeSubmitted, from: .unlock).reply == .accepted)
    let verification = try #require(fixture.runtime.snapshot.administration.verification)
    #expect(fixture.runtime.send(.cancelAuthentication, from: .unlock).reply == .accepted)
    fixture.port.deliver(.credentialVerified(verification, succeeded: true), source: .credentials)
    #expect(fixture.runtime.snapshot.root.mode == .exhibiting)
    #expect(fixture.runtime.snapshot.root.presentationAcquired)
    #expect(fixture.runtime.snapshot.root.administratorSession == false)
    #expect(fixture.runtime.snapshot.exhibition.phase == .quiescing)
    #expect(fixture.port.effects.contains { $0.kind == .releasePresentation } == false)
  }

  @Test func successfulUnlockWaitsForWebTeardownThenPresentationRelease() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    fixture.runtime.send(.unlockRequested, from: .platform)
    fixture.runtime.send(.passcodeEdited("fixture"), from: .unlock)
    fixture.runtime.send(.passcodeSubmitted, from: .unlock)
    let verification = try #require(fixture.runtime.snapshot.administration.verification)
    fixture.port.deliver(.credentialVerified(verification, succeeded: true), source: .credentials)
    #expect(fixture.runtime.snapshot.root.mode == .leavingKiosk)
    #expect(fixture.runtime.snapshot.root.presentationAcquired)
    let release = try #require(fixture.runtime.snapshot.exhibition.releaseOperation)
    fixture.port.deliver(.surfaceReleased(release), source: .webSurface)
    let presentation = try #require(fixture.runtime.snapshot.root.presentationOperation)
    #expect(fixture.port.effects.last?.kind == .releasePresentation)
    #expect(fixture.runtime.snapshot.root.mode == .leavingKiosk)
    fixture.port.deliver(.presentationReleased(presentation), source: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .administration)
    #expect(fixture.runtime.snapshot.root.presentationAcquired == false)
    #expect(fixture.runtime.settingsProps.props.canStart)
  }

  @Test func draftSaveRoutesThroughRootAndDoesNotReissueOnProjection() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(
      .draftChanged(ProfileDraft(profile: try fixture.profile())), from: .settings)
    #expect(fixture.runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
    let effect = try #require(fixture.port.effects.last)
    guard case .saveProfile(let profile) = effect.kind else {
      Issue.record("Expected profile save")
      return
    }
    #expect(fixture.runtime.snapshot.root.savedProfile == nil)
    #expect(fixture.runtime.snapshot.administration.saving)
    #expect(
      fixture.runtime.reports.contains {
        $0.source == .administration && $0.handler == .root && $0.causationID != nil
      })
    fixture.port.deliver(.profileSaved(effect.token, profile), source: .profileRepository)
    #expect(fixture.runtime.snapshot.root.savedProfile == profile)
    #expect(fixture.runtime.snapshot.administration.hasUnsavedDraft == false)
    let count = fixture.port.effects.count
    let revision = fixture.runtime.settingsProps.revision
    for _ in 0..<20 { fixture.runtime.project() }
    #expect(fixture.port.effects.count == count)
    #expect(fixture.runtime.settingsProps.revision == revision)
  }

  @Test func explicitStopDisablesFurtherIngressAndStopsOwnedExecutor() {
    let fixture = RuntimeFixture()
    fixture.runtime.stop()
    fixture.runtime.stop()
    #expect(fixture.port.stopped)
    #expect(
      fixture.runtime.send(.unlockRequested, from: .platform).reply == .rejected(.invalidState))
    #expect(fixture.port.resultSink == nil)
  }

  @Test func reentrantResetDoesNotStartInvalidatedRetryEffect() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try fixture.startExhibiting()
    fixture.port.onExecute = { effect in
      if case .releaseSurface = effect.kind {
        fixture.runtime.send(.unlockRequested, from: .platform)
        fixture.runtime.send(.cancelAuthentication, from: .unlock)
        fixture.port.deliver(.surfaceReleased(effect.token), source: .webSurface)
      }
    }
    let load = try #require(fixture.runtime.snapshot.exhibition.operation)
    fixture.port.deliver(.webFailed(load, .network), source: .webSurface)
    #expect(fixture.runtime.snapshot.exhibition.phase == .recreatingSurface)
    #expect(
      fixture.port.effects.contains {
        if case .scheduleRetry = $0.kind { return true }
        return false
      } == false)
  }
}
