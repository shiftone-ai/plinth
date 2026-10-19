#if DEBUG && os(iOS)
  import Foundation
  import KioskCore
  import KioskRuntime

  /// Isolated UI fixture activated only by a dedicated test credential service.
  @MainActor final class RemoteDirectoryUITestFixture: RemoteDirectoryPort {
    enum Failure: Error { case invalidRequest }

    private let accountIdentifier = "ui-test-account"
    private let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000060")!
    private let targetIdentity = RemoteIdentity.generate()
    private let sendEvent: @MainActor @Sendable (Event) -> Void
    private var installation: RemoteInstallation
    private var session: OperationToken?
    private var profile: KioskProfile
    private var mode: AppMode = .exhibiting

    init(sendEvent: @escaping @MainActor @Sendable (Event) -> Void) {
      self.sendEvent = sendEvent
      let identity = targetIdentity
      installation = RemoteInstallation(
        id: UUID(),
        approvedTargets: [
          targetID:
            RemotePeerGrant(
              id: targetID, name: "Gallery iPad",
              accountIdentifier: accountIdentifier,
              signingPublicKey: identity.signingPublicKey,
              agreementPublicKey: identity.agreementPublicKey,
              approvedAt: .now)
        ])
      let origin = Origin(urlString: "https://example.com")!
      profile = KioskProfile(
        startURL: "https://example.com/home",
        navigation: .init(rules: [.init(id: 1, origin: origin)]))
    }

    func load() throws -> RemoteInstallation { installation }
    func accountAvailability() async -> RemoteAccountAvailability {
      .available(accountIdentifier)
    }
    func checkAccount() throws -> RemoteAccountCheck {
      RemoteAccountCheck(
        availability: .available(accountIdentifier),
        installation: installation)
    }
    func start(
      accountIdentifier: String, installation: RemoteInstallation,
      session: OperationToken
    ) async {
      guard accountIdentifier == self.accountIdentifier else { return }
      self.installation = installation
      self.session = session
      await sendEvent(.remoteDirectoryChanged(session, accountIdentifier, [device]))
      await sendEvent(.remoteDirectoryStatusChanged(session, .ready))
    }
    func stop(command: OperationToken?) { session = nil }
    func refresh(session: OperationToken) async {
      guard self.session == session else { return }
      await sendEvent(.remoteDirectoryChanged(session, accountIdentifier, [device]))
    }
    func setEnabled(_ enabled: Bool, accountIdentifier: String) throws -> RemoteInstallation {
      guard accountIdentifier == self.accountIdentifier else { throw Failure.invalidRequest }
      installation.enabledAccountIdentifier = enabled ? accountIdentifier : nil
      return installation
    }
    func setVisibility(
      _ id: UUID, visible: Bool,
      accountIdentifier: String
    ) throws -> RemoteInstallation {
      guard accountIdentifier == self.accountIdentifier else { throw Failure.invalidRequest }
      var hidden = installation.hiddenDeviceIDsByAccount[accountIdentifier] ?? []
      if visible { hidden.remove(id) } else { hidden.insert(id) }
      installation.hiddenDeviceIDsByAccount[accountIdentifier] = hidden
      return installation
    }
    func sendPairingRequest(
      target: RemoteDevice, code: String, requestID: UUID,
      accountIdentifier: String, command: OperationToken
    ) throws { throw Failure.invalidRequest }
    func respondToPairing(
      _ proposal: RemotePairingProposal,
      approved: Bool
    ) throws -> RemoteInstallation { throw Failure.invalidRequest }
    func saveTargetGrant(
      _ grant: RemotePeerGrant,
      requestID: UUID
    ) throws -> RemoteInstallation { throw Failure.invalidRequest }
    func revokeController(
      _ id: UUID,
      accountIdentifier: String
    ) throws -> RemoteInstallation { throw Failure.invalidRequest }
    func sendCommand(
      target: RemotePeerGrant, command: RemoteCommandPayload,
      requestID: UUID, accountIdentifier: String, operation: OperationToken
    ) async throws {
      guard target.id == targetID, accountIdentifier == self.accountIdentifier,
        let session
      else { throw Failure.invalidRequest }
      await sendEvent(.remoteCommandCloudSaved(operation, requestID))
      let outcome: RemoteCommandOutcome
      switch command {
      case .readStatus:
        outcome = .succeeded(snapshot)
      case .saveProfile(let patch):
        if patch.baseRevision == profile.revision,
          let saved = patch.apply(to: profile), saved.validationIssues.isEmpty
        {
          profile = saved
          outcome = .succeeded(snapshot)
        } else {
          outcome = .rejected(.invalidProfile)
        }
      case .exhibition(let action):
        switch action {
        case .stop: mode = .paused
        case .start, .restart, .resume: mode = .exhibiting
        }
        outcome = .succeeded(snapshot)
      }
      let now = Int64(Date().timeIntervalSince1970)
      let header = RemoteMessageHeader(
        kind: .result,
        accountIdentifier: accountIdentifier, senderID: targetID,
        recipientID: installation.id, requestID: requestID,
        expiresAt: now + 120)
      await sendEvent(
        .remoteCommandResultReceived(
          session,
          RemoteCommandResult(header: header, outcome: outcome), receivedAt: now))
    }
    func claimCommand(_ request: RemoteCommandRequest) throws -> RemoteInstallation {
      throw Failure.invalidRequest
    }
    func sendResult(
      for request: RemoteCommandRequest,
      outcome: RemoteCommandOutcome
    ) throws { throw Failure.invalidRequest }

    private var device: RemoteDevice {
      RemoteDevice(
        id: targetID, name: "Gallery iPad", platform: .ipad,
        updatedAt: .now, signingPublicKey: targetIdentity.signingPublicKey,
        agreementPublicKey: targetIdentity.agreementPublicKey)
    }
    private var snapshot: RemoteStatusSnapshot {
      RemoteStatusSnapshot(
        reportedAt: Int64(Date().timeIntervalSince1970),
        mode: mode, savedProfile: profile, activeRevision: profile.revision,
        mobileDisplays: MobileDisplayAvailability(
          deviceAvailable: true,
          externalAvailable: false))
    }
  }
#endif
