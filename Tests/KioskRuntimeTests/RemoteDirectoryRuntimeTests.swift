import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

@MainActor
private final class RemoteDirectoryEventRecorder {
  var events: [Event] = []
}

@MainActor
struct RemoteDirectoryRuntimeTests {
  @Test func anotherDeviceCanBeFoundWithoutAProfileOnThisDevice() throws {
    let fixture = RuntimeFixture()
    let localID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)

    #expect(fixture.runtime.send(.remoteLoadRequested, from: .root).reply == .accepted)
    let load = try #require(fixture.runtime.snapshot.root.remote.loadOperation)
    fixture.port.deliver(
      .remoteLoaded(load, RemoteInstallation(id: localID)), source: .cloudRemote)
    let account = try #require(fixture.runtime.snapshot.root.remote.accountOperation)
    fixture.port.deliver(
      .remoteAccountChecked(
        account,
        .init(
          availability: .available("account-a"), installation: RemoteInstallation(id: localID))),
      source: .cloudRemote)
    let session = try #require(fixture.runtime.snapshot.root.remote.sessionOperation)

    let updated = Date(timeIntervalSince1970: 1_700_000_000)
    fixture.port.deliver(
      .remoteDirectoryChanged(
        session, "account-a",
        [
          RemoteDevice(id: localID, name: "This Mac", platform: .mac, updatedAt: updated),
          RemoteDevice(id: targetID, name: "Gallery iPad", platform: .ipad, updatedAt: updated),
        ]), source: .cloudRemote)
    fixture.port.deliver(.remoteDirectoryStatusChanged(session, .ready), source: .cloudRemote)

    #expect(fixture.runtime.remoteProps.props.devices.map(\.name) == ["Gallery iPad"])
    #expect(fixture.runtime.remoteProps.props.devices.first?.updatedAt == updated)
    #expect(fixture.runtime.remoteProps.props.accountStatus == .ready)
  }

  @Test func accountChangeDropsOldDevicesAndLateUpdates() throws {
    let fixture = RuntimeFixture()
    let localID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.remoteLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.remote.loadOperation)
    fixture.port.deliver(
      .remoteLoaded(load, RemoteInstallation(id: localID)),
      source: .cloudRemote)
    let account = try #require(fixture.runtime.snapshot.root.remote.accountOperation)
    fixture.port.deliver(
      .remoteAccountChecked(
        account,
        .init(
          availability: .available("account-a"), installation: RemoteInstallation(id: localID))),
      source: .cloudRemote)
    let oldSession = try #require(fixture.runtime.snapshot.root.remote.sessionOperation)
    let device = RemoteDevice(
      id: targetID, name: "Gallery iPad", platform: .ipad,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    fixture.port.deliver(
      .remoteDirectoryChanged(oldSession, "account-a", [device]),
      source: .cloudRemote)
    fixture.runtime.send(.remoteTabSelected(.otherDevices), from: .settings)
    fixture.runtime.send(.remoteDeviceSelected(targetID), from: .settings)

    fixture.port.deliver(.remoteAccountAvailabilityChanged, source: .cloudRemote)
    #expect(fixture.runtime.remoteProps.props.devices.isEmpty)
    #expect(fixture.runtime.remoteProps.props.selectedDeviceID == nil)
    #expect(fixture.runtime.remoteProps.props.accountStatus == .checking)
    #expect(
      fixture.runtime.send(
        .remoteDirectoryChanged(oldSession, "account-a", [device]), from: .cloudRemote
      ).reply == .rejected(.staleOperation))

    let newAccount = try #require(fixture.runtime.snapshot.root.remote.accountOperation)
    fixture.port.deliver(
      .remoteAccountChecked(
        newAccount,
        .init(
          availability: .available("account-b"), installation: RemoteInstallation(id: localID))),
      source: .cloudRemote)
    #expect(fixture.runtime.remoteProps.props.devices.isEmpty)
    #expect(fixture.runtime.snapshot.root.remote.accountIdentifier == "account-b")
  }

  @Test func aDeviceWithoutAdministratorAuthenticationCannotEnableRemoteControl() throws {
    let fixture = RuntimeFixture()
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    #expect(
      fixture.runtime.send(
        .remoteEnabledRequested(true), from: .settings
      ).reply == .rejected(.unauthenticated))
  }

  @Test func firstRunPasscodeConfigurationCanEnableThisDevice() throws {
    let fixture = RuntimeFixture()
    fixture.runtime.send(
      .bootstrapped(
        profile: nil,
        credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.remoteLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.remote.loadOperation)
    let installation = RemoteInstallation(id: UUID())
    fixture.port.deliver(.remoteLoaded(load, installation), source: .cloudRemote)
    let account = try #require(fixture.runtime.snapshot.root.remote.accountOperation)
    fixture.port.deliver(
      .remoteAccountChecked(
        account,
        RemoteAccountCheck(
          availability: .available("account-a"),
          installation: installation)), source: .cloudRemote)
    #expect(
      fixture.runtime.send(
        .remoteEnabledRequested(true),
        from: .settings
      ).reply == .rejected(.unauthenticated))
    fixture.runtime.send(
      .credentialConfigurationRequested("12345678"),
      from: .administration)
    let credential = try #require(fixture.runtime.snapshot.root.credentialOperation)
    fixture.port.deliver(
      .credentialConfigured(credential, succeeded: true),
      source: .credentials)
    #expect(fixture.runtime.snapshot.root.administratorSession)
    #expect(fixture.runtime.remoteProps.props.canChangeThisDevice)
    #expect(
      fixture.runtime.send(
        .remoteEnabledRequested(true),
        from: .settings
      ).reply == .accepted)
  }

  @Test func installationIdentitySurvivesRestartAndStartsDisabled() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-remote-directory-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("remote-management.json")
    let first = RemoteDirectoryCloudSync(
      stateURL: url, displayName: "Gallery iPad", platform: .ipad, sendEvent: { _ in })
    let initial = try await first.load()
    #expect(initial.enabledAccountIdentifier == nil)
    let reopened = RemoteDirectoryCloudSync(
      stateURL: url, displayName: "Gallery iPad", platform: .ipad, sendEvent: { _ in })
    #expect(try await reopened.load() == initial)
  }

  @Test(arguments: [false, true])
  func accountCheckCanBeRetriedWithoutADirectorySession(failed: Bool) throws {
    let fixture = RuntimeFixture()
    let installation = RemoteInstallation(id: UUID())
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.remoteLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.remote.loadOperation)
    fixture.port.deliver(.remoteLoaded(load, installation), source: .cloudRemote)
    let first = try #require(fixture.runtime.snapshot.root.remote.accountOperation)
    if failed {
      fixture.port.deliver(.remoteAccountCheckFailed(first), source: .cloudRemote)
    } else {
      fixture.port.deliver(
        .remoteAccountChecked(
          first, .init(availability: .transient, installation: installation)),
        source: .cloudRemote)
    }
    #expect(fixture.runtime.snapshot.root.remote.sessionOperation == nil)
    #expect(fixture.runtime.remoteProps.props.canRefresh)
    #expect(fixture.runtime.send(.remoteRefreshRequested, from: .settings).reply == .accepted)
    let retry = try #require(fixture.runtime.snapshot.root.remote.accountOperation)
    #expect(retry != first)
    fixture.port.deliver(
      .remoteAccountChecked(
        retry, .init(availability: .available("account-a"), installation: installation)),
      source: .cloudRemote)
    #expect(fixture.runtime.snapshot.root.remote.sessionOperation != nil)
  }

  @Test func unusuallyLongDeviceNamesRemainDiscoverable() async {
    let combinedEmoji = "👨‍👩‍👧‍👦"
    let directory = RemoteDirectoryCloudSync(
      stateURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
      displayName: String(repeating: combinedEmoji, count: 80), platform: .ipad,
      sendEvent: { _ in })
    let name = await directory.displayName
    #expect(!name.isEmpty)
    #expect(name.utf8.count <= 320)
    #expect(name.count <= 80)
  }

  @Test func anApprovedDeviceCanRequestApprovalAgainAfterRevocation() throws {
    let fixture = RuntimeFixture()
    let target = RemoteDevice(
      id: UUID(), name: "Gallery iPad", platform: .ipad, updatedAt: .now,
      signingPublicKey: Data(repeating: 3, count: 32),
      agreementPublicKey: Data(repeating: 4, count: 32))
    let grant = RemotePeerGrant(
      id: target.id, name: target.name, accountIdentifier: "account-a",
      signingPublicKey: try #require(target.signingPublicKey),
      agreementPublicKey: try #require(target.agreementPublicKey), approvedAt: .now)
    let installation = RemoteInstallation(
      id: UUID(), approvedTargets: [target.id: grant])
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.remoteLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.remote.loadOperation)
    fixture.port.deliver(.remoteLoaded(load, installation), source: .cloudRemote)
    let account = try #require(fixture.runtime.snapshot.root.remote.accountOperation)
    fixture.port.deliver(
      .remoteAccountChecked(
        account, .init(availability: .available("account-a"), installation: installation)),
      source: .cloudRemote)
    let session = try #require(fixture.runtime.snapshot.root.remote.sessionOperation)
    fixture.port.deliver(
      .remoteDirectoryChanged(session, "account-a", [target]), source: .cloudRemote)
    fixture.port.deliver(.remoteDirectoryStatusChanged(session, .ready), source: .cloudRemote)
    fixture.runtime.send(.remoteTabSelected(.otherDevices), from: .settings)
    fixture.runtime.send(.remoteDeviceSelected(target.id), from: .settings)
    #expect(fixture.runtime.remoteProps.props.selectedDevicePaired)
    fixture.runtime.send(.remotePairingCodeEdited("12345678"), from: .settings)
    #expect(fixture.runtime.remoteProps.props.canRequestPairing)
    #expect(
      fixture.runtime.send(
        .remotePairingRequestRequested(UUID()), from: .settings
      ).reply == .accepted)
  }

  @Test func rebuildingTheSharedEngineDoesNotPublishAnEmptyDirectory() async {
    let recorder = RemoteDirectoryEventRecorder()
    let directory = RemoteDirectoryCloudSync(
      stateURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
      displayName: "Controller", platform: .mac,
      sendEvent: { event in recorder.events.append(event) })
    let session = OperationToken(owner: .cloudRemote, operationID: 1)
    let device = RemoteDevice(id: UUID(), name: "Gallery", platform: .ipad, updatedAt: .now)
    await directory.seedDirectoryForTest(session: session, device: device)
    await directory.adoptSharedEngine(nil, fullFetch: true)
    #expect(
      !recorder.events.contains(where: { event in
        if case .remoteDirectoryChanged = event { return true }
        return false
      }))
    await directory.completeFetchForTest(device: device)
    await directory.publishDevices(session: session, accountIdentifier: "account-a")
    #expect(recorder.events.contains(.remoteDirectoryChanged(session, "account-a", [device])))
  }
}

extension RemoteDirectoryCloudSync {
  fileprivate func seedDirectoryForTest(session: OperationToken, device: RemoteDevice) {
    self.session = session
    accountIdentifier = "account-a"
    devices = [device.id: device]
  }

  fileprivate func completeFetchForTest(device: RemoteDevice) {
    awaitingInitialFetch = false
    devices = [device.id: device]
  }
}
