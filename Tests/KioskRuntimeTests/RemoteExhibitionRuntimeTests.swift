import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct RemoteExhibitionRuntimeTests {
  @Test func remoteStartUsesTheExistingRootStartConditions() throws {
    let controller = RuntimeFixture()
    let target = RuntimeFixture()
    controller.runtime.send(
      .bootstrapped(
        profile: nil,
        credentialsConfigured: false, displayCount: 1), from: .root)
    target.runtime.send(
      .bootstrapped(
        profile: nil,
        credentialsConfigured: false, displayCount: 1), from: .root)
    target.runtime.send(
      .draftEdited(.startURL("https://example.com/home")),
      from: .settings)
    #expect(
      target.runtime.send(
        .saveDraftRequested,
        from: .settings
      ).reply == .accepted)
    let save = try #require(target.runtime.snapshot.root.saveOperation)
    let profile = try #require(target.runtime.snapshot.root.pendingProfile)
    target.port.deliver(.profileSaved(save, profile), source: .profileRepository)
    #expect(
      target.runtime.send(
        .credentialConfigurationRequested("12345678"),
        from: .administration
      ).reply == .accepted)
    let credential = try #require(target.runtime.snapshot.root.credentialOperation)
    target.port.deliver(
      .credentialConfigured(credential, succeeded: true),
      source: .credentials)
    #expect(target.runtime.snapshot.root.mode == .administration)

    let controllerID = UUID()
    let targetID = UUID()
    let identity = RemoteIdentity.generate()
    let grant = RemotePeerGrant(
      id: controllerID, name: "Control iPad",
      accountIdentifier: "account-a", signingPublicKey: identity.signingPublicKey,
      agreementPublicKey: identity.agreementPublicKey, approvedAt: .now)
    let installation = RemoteInstallation(
      id: targetID,
      enabledAccountIdentifier: "account-a", approvedControllers: [controllerID: grant])
    target.runtime.send(.remoteLoadRequested, from: .root)
    let load = try #require(target.runtime.snapshot.root.remote.loadOperation)
    target.port.deliver(.remoteLoaded(load, installation), source: .cloudRemote)
    let account = try #require(target.runtime.snapshot.root.remote.accountOperation)
    target.port.deliver(
      .remoteAccountChecked(
        account,
        RemoteAccountCheck(
          availability: .available("account-a"),
          installation: installation)), source: .cloudRemote)
    let session = try #require(target.runtime.snapshot.root.remote.sessionOperation)

    let requestID = UUID()
    let header = RemoteMessageHeader(
      kind: .command,
      accountIdentifier: "account-a", senderID: controllerID,
      recipientID: targetID, requestID: requestID, expiresAt: 1_700_000_120)
    target.port.deliver(
      .remoteCommandReceived(
        session,
        RemoteCommandRequest(
          header: header, command: .exhibition(.start),
          authenticatedSigningPublicKey: identity.signingPublicKey),
        receivedAt: 1_700_000_001), source: .cloudRemote)
    let claim = try #require(target.runtime.snapshot.root.remote.commandClaimOperation)
    var claimed = installation
    claimed.processedRequestExpirations[requestID] = header.expiresAt
    target.port.deliver(
      .remoteCommandClaimed(
        claim, claimed,
        processedAt: 1_700_000_002), source: .cloudRemote)
    #expect(target.runtime.snapshot.root.mode == .enteringKiosk)
    #expect(target.runtime.snapshot.root.remote.commandResultOperation == nil)
    #expect(
      target.port.effects.contains { effect in
        if case .reportRemoteCommandProgress(_, .accepted) = effect.kind { return true }
        return false
      })
    #expect(
      target.port.effects.contains { effect in
        if case .reportRemoteCommandProgress(_, .stateChanged(let snapshot)) = effect.kind {
          return snapshot.mode == .enteringKiosk
        }
        return false
      })
    let apply = try #require(target.runtime.snapshot.root.presentationOperation)
    target.port.deliver(.presentationApplied(apply), source: .platform)
    target.port.deliver(.exhibitionReady, source: .exhibition)
    #expect(target.runtime.snapshot.root.mode == .exhibiting)
    #expect(target.runtime.snapshot.root.activeProfile == profile)
    let result = try #require(
      target.port.effects.last { effect in
        if case .sendRemoteCommandResult = effect.kind { return true }
        return false
      })
    guard case .sendRemoteCommandResult(_, let outcome) = result.kind,
      case .succeeded(let snapshot) = outcome
    else {
      Issue.record("Start did not report target completion")
      return
    }
    #expect(snapshot.mode == .exhibiting)
    #expect(controller.runtime.snapshot.root.activeProfile == nil)
  }

  @Test func stopResumeAndRestartCompleteOnlyAfterTargetTransitions() throws {
    let controller = RuntimeFixture()
    let target = RuntimeFixture()
    controller.runtime.send(
      .bootstrapped(
        profile: nil,
        credentialsConfigured: false, displayCount: 1), from: .root)
    try target.startExhibiting()
    let controllerID = UUID()
    let targetID = UUID()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let identity = RemoteIdentity.generate()
    let grant = RemotePeerGrant(
      id: controllerID, name: "Control iPad",
      accountIdentifier: "account-a", signingPublicKey: identity.signingPublicKey,
      agreementPublicKey: identity.agreementPublicKey, approvedAt: date)
    target.runtime.send(.remoteLoadRequested, from: .root)
    let load = try #require(target.runtime.snapshot.root.remote.loadOperation)
    let installation = RemoteInstallation(
      id: targetID,
      enabledAccountIdentifier: "account-a", approvedControllers: [controllerID: grant])
    target.port.deliver(.remoteLoaded(load, installation), source: .cloudRemote)
    let account = try #require(target.runtime.snapshot.root.remote.accountOperation)
    target.port.deliver(
      .remoteAccountChecked(
        account,
        RemoteAccountCheck(
          availability: .available("account-a"),
          installation: installation)), source: .cloudRemote)
    let session = try #require(target.runtime.snapshot.root.remote.sessionOperation)
    let original = try #require(target.runtime.snapshot.root.savedProfile)

    func begin(_ action: RemoteExhibitionAction) throws -> UUID {
      let id = UUID()
      let header = RemoteMessageHeader(
        kind: .command,
        accountIdentifier: "account-a", senderID: controllerID,
        recipientID: targetID, requestID: id, expiresAt: 1_700_000_120)
      target.port.deliver(
        .remoteCommandReceived(
          session,
          RemoteCommandRequest(
            header: header, command: .exhibition(action),
            authenticatedSigningPublicKey: identity.signingPublicKey),
          receivedAt: 1_700_000_001), source: .cloudRemote)
      let claim = try #require(target.runtime.snapshot.root.remote.commandClaimOperation)
      var claimed = try #require(target.runtime.snapshot.root.remote.installation)
      claimed.processedRequestExpirations[id] = header.expiresAt
      target.port.deliver(
        .remoteCommandClaimed(
          claim, claimed,
          processedAt: 1_700_000_002), source: .cloudRemote)
      #expect(target.runtime.snapshot.root.remote.pendingExhibitionAction == action)
      #expect(target.runtime.snapshot.root.remote.commandResultOperation == nil)
      return id
    }

    func finish(_ action: RemoteExhibitionAction) throws {
      let operation = try #require(target.runtime.snapshot.root.remote.commandResultOperation)
      let effect = try #require(
        target.port.effects.last { effect in
          if case .sendRemoteCommandResult = effect.kind { return true }
          return false
        })
      guard case .sendRemoteCommandResult(_, let outcome) = effect.kind,
        case .succeeded(let snapshot) = outcome
      else {
        Issue.record("Missing target transition result")
        return
      }
      #expect(snapshot.mode == (action == .stop ? .paused : .exhibiting))
      target.port.deliver(.remoteCommandResultQueued(operation), source: .cloudRemote)
    }

    let stopID = try begin(.stop)
    #expect(target.runtime.snapshot.root.mode == .leavingKiosk)
    target.port.deliver(.exhibitionStopped, source: .exhibition)
    #expect(target.runtime.snapshot.root.mode == .paused)
    try finish(.stop)
    let effectsBeforeReplay = target.port.effects.count
    let replayHeader = RemoteMessageHeader(
      kind: .command,
      accountIdentifier: "account-a", senderID: controllerID,
      recipientID: targetID, requestID: stopID, expiresAt: 1_700_000_120)
    target.port.deliver(
      .remoteCommandReceived(
        session,
        RemoteCommandRequest(
          header: replayHeader, command: .exhibition(.stop),
          authenticatedSigningPublicKey: identity.signingPublicKey),
        receivedAt: 1_700_000_003), source: .cloudRemote)
    #expect(target.port.effects.count == effectsBeforeReplay)

    _ = try begin(.resume)
    #expect(target.runtime.snapshot.root.mode == .leavingKiosk)
    let release = try #require(target.runtime.snapshot.root.presentationOperation)
    target.port.deliver(.presentationReleased(release), source: .platform)
    let apply = try #require(target.runtime.snapshot.root.presentationOperation)
    target.port.deliver(.presentationApplied(apply), source: .platform)
    target.port.deliver(.exhibitionReady, source: .exhibition)
    #expect(target.runtime.snapshot.root.mode == .exhibiting)
    try finish(.resume)

    var newer = original
    newer.revision += 1
    newer.startURL = "https://example.com/new-home"
    #expect(
      target.runtime.send(
        .profileCommitRequested(newer),
        from: .administration
      ).reply == .accepted)
    let save = try #require(target.runtime.snapshot.root.saveOperation)
    target.port.deliver(.profileSaved(save, newer), source: .profileRepository)
    #expect(target.runtime.snapshot.root.activeProfile == original)

    _ = try begin(.restart)
    target.port.deliver(.exhibitionStopped, source: .exhibition)
    let restartRelease = try #require(target.runtime.snapshot.root.presentationOperation)
    target.port.deliver(.presentationReleased(restartRelease), source: .platform)
    #expect(target.runtime.snapshot.root.activeProfile == newer)
    let restartApply = try #require(target.runtime.snapshot.root.presentationOperation)
    target.port.deliver(.presentationApplied(restartApply), source: .platform)
    target.port.deliver(.exhibitionReady, source: .exhibition)
    try finish(.restart)
    #expect(target.runtime.snapshot.root.mode == .exhibiting)
    #expect(controller.runtime.snapshot.root.savedProfile == nil)
    #expect(controller.runtime.snapshot.root.activeProfile == nil)
  }
}
