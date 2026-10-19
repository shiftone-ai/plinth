import Foundation
import KioskCore
import KioskRuntime
import Testing

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

    #expect(fixture.runtime.remoteProps.props.visibleDevices.map(\.name) == ["Gallery iPad"])
    #expect(fixture.runtime.remoteProps.props.visibleDevices.first?.updatedAt == updated)
    #expect(fixture.runtime.remoteProps.props.accountStatus == .ready)
  }

  @Test func hidingADeviceDoesNotDisableTheExhibitionDevice() throws {
    let fixture = RuntimeFixture()
    let localID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.remoteLoadRequested, from: .root)
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
    fixture.port.deliver(
      .remoteDirectoryChanged(
        session, "account-a",
        [
          RemoteDevice(
            id: targetID, name: "Gallery iPad", platform: .ipad,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        ]), source: .cloudRemote)

    #expect(
      fixture.runtime.send(
        .remoteVisibilityRequested(id: targetID, visible: false), from: .settings
      ).reply == .accepted)
    let change = try #require(fixture.runtime.snapshot.root.remote.preferenceOperation)
    #expect(
      fixture.port.effects.contains { effect in
        if case .setRemoteVisibility(let id, let visible, let accountID) = effect.kind {
          return id == targetID && !visible && accountID == "account-a"
        }
        return false
      })
    fixture.port.deliver(
      .remoteConfigurationUpdated(
        change,
        RemoteInstallation(id: localID, hiddenDeviceIDsByAccount: ["account-a": [targetID]])),
      source: .cloudRemote)

    #expect(fixture.runtime.remoteProps.props.visibleDevices.isEmpty)
    #expect(fixture.runtime.remoteProps.props.hiddenDevices.map(\.id) == [targetID])
    #expect(fixture.runtime.snapshot.root.remote.devices.first?.id == targetID)
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
    #expect(fixture.runtime.remoteProps.props.visibleDevices.isEmpty)
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
    #expect(fixture.runtime.remoteProps.props.visibleDevices.isEmpty)
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
}
