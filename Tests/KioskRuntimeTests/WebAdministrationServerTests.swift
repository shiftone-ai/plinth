import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

@MainActor
struct WebAdministrationServerTests {
  @Test func secondaryAddressChangeUpdatesNavigationProtection() async throws {
    let server = WebAdministrationServer(port: 0)
    defer { server.stop() }
    guard case .success = await server.start() else {
      Issue.record("Listener did not start")
      return
    }
    let port = try #require(server.listeningPort)
    var changes: [WebServerEndpoint] = []
    server.addressChanged = { changes.append($0) }
    server.updateAddressCatalog(
      NetworkAddressCatalog(addresses: ["192.0.2.1", "192.0.2.2", "127.0.0.1", "::1"]))
    let first = try #require(changes.last)
    server.updateAddressCatalog(
      NetworkAddressCatalog(addresses: ["192.0.2.1", "192.0.2.3", "127.0.0.1", "::1"]))
    let second = try #require(changes.last)
    #expect(changes.count == 2)
    #expect(second.url == first.url)
    #expect(second.origins.contains(try #require(Origin(urlString: "http://192.0.2.3:\(port)/"))))
    #expect(!second.origins.contains(try #require(Origin(urlString: "http://192.0.2.2:\(port)/"))))
  }

  @Test func occupiedPortReportsTheConflict() async throws {
    let first = WebAdministrationServer(port: 0)
    defer { first.stop() }
    guard case .success = await first.start() else {
      Issue.record("First listener did not start")
      return
    }
    let port = try #require(first.listeningPort)
    let second = WebAdministrationServer(port: port)
    defer { second.stop() }
    guard case .failure(let failure) = await second.start() else {
      Issue.record("Second listener unexpectedly bound to the same port")
      return
    }
    #expect(failure == .portInUse)
  }

  @Test func addressChangeDuringStartWinsOverInitialEndpoint() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let operation = try #require(fixture.runtime.snapshot.root.webServerOperation)
    let initial = WebServerEndpoint(url: "http://192.0.2.1:47623/", origins: [])
    let changed = WebServerEndpoint(url: "http://192.0.2.2:47623/", origins: [])
    fixture.port.deliver(.webServerAddressChanged(changed), source: .webAdministration)
    fixture.port.deliver(.webServerStarted(operation, initial), source: .webAdministration)
    #expect(fixture.runtime.snapshot.root.webServerURL == changed.url)
  }

  @Test func concurrentStartsShareOneListenerAndStoppedPortCanRestart() async throws {
    let port: UInt16 = 47624
    let server = WebAdministrationServer(port: port)
    defer { server.stop() }
    let pendingA = Task { await server.start() }
    let pendingB = Task { await server.start() }
    #expect((await pendingA.value).isSuccess)
    #expect((await pendingB.value).isSuccess)
    #expect(server.listeningPort == port)
    let base = try #require(URL(string: "http://127.0.0.1:\(port)/"))
    #expect(try await request(base).status == 503)

    server.stop()
    guard case .success = await server.start() else {
      Issue.record("Listener could not restart on the same port")
      return
    }
    #expect(server.listeningPort == port)
    #expect(try await request(base).status == 503)
  }

  // One session checks the full token replacement and expiry sequence.
  // swiftlint:disable:next function_body_length
  @Test func liveHTTPRejectsUntrustedHostAndOriginAndRequiresASession() async throws {
    let fixture = RuntimeFixture()
    let server = WebAdministrationServer(port: 0)
    server.attach(runtime: fixture.runtime, locale: { Locale(identifier: "en") })
    defer {
      server.stop()
      fixture.runtime.stop()
    }
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let started = try #require(fixture.port.effects.first { $0.kind == .startWebServer })
    guard case .success(let endpoint) = await server.start() else {
      Issue.record("Listener did not start")
      return
    }
    let port = try #require(server.listeningPort)
    fixture.port.deliver(
      .webServerStarted(started.token, endpoint),
      source: .webAdministration)
    let base = try #require(URL(string: "http://127.0.0.1:\(port)"))

    let publicPage = try await request(base.appendingPathComponent("/"))
    #expect(publicPage.status == 200)
    #expect(!publicPage.text.contains(profile.startURL))
    let anonymous = try await request(base.appendingPathComponent("/api/state"))
    #expect(anonymous.status == 401)
    #expect(!anonymous.text.contains(profile.startURL))

    let wrongHost = try await request(
      base.appendingPathComponent("/api/state"),
      headers: ["Host": "attacker.example:\(port)"])
    #expect(wrongHost.status == 403)
    let missingOrigin = try await request(
      base.appendingPathComponent("/api/login"),
      method: "POST", body: #"{"password":"correct"}"#)
    #expect(missingOrigin.status == 403)
    let nullOrigin = try await request(
      base.appendingPathComponent("/api/login"),
      method: "POST", headers: ["Origin": "null"],
      body: #"{"password":"correct"}"#)
    #expect(nullOrigin.status == 403)
    let otherOrigin = try await request(
      base.appendingPathComponent("/api/login"),
      method: "POST", headers: ["Origin": "http://attacker.example"],
      body: #"{"password":"correct"}"#)
    #expect(otherOrigin.status == 403)
    #expect(otherOrigin.headers["Access-Control-Allow-Origin"] == nil)

    fixture.port.onExecute = { effect in
      if case .verifyPasscode = effect.kind {
        fixture.port.deliver(
          .credentialVerified(effect.token, succeeded: true),
          source: .credentials)
      }
    }
    let origin = "http://127.0.0.1:\(port)"
    let login = try await request(
      base.appendingPathComponent("/api/login"),
      method: "POST", headers: ["Origin": origin],
      body: #"{"password":"correct"}"#)
    #expect(login.status == 202)
    let ticket = try #require(JSONSerialization.jsonObject(with: login.data) as? [String: String])
    let token = try #require(ticket["token"])
    let status = try await request(
      base.appendingPathComponent("/api/login/status"),
      method: "POST", headers: ["Origin": origin],
      body: #"{"token":"\#(token)"}"#)
    #expect(status.status == 200)
    #expect(status.text.contains("authenticated"))
    let authenticated = try await request(
      base.appendingPathComponent("/api/state"),
      headers: ["Authorization": "Bearer \(token)"])
    #expect(authenticated.status == 200)
    #expect(authenticated.text.contains("example.com"))
    #expect(authenticated.headers["Access-Control-Allow-Origin"] == nil)
    let mismatchedOrigin = try await request(
      base.appendingPathComponent("/api/state"),
      headers: ["Authorization": "Bearer \(token)", "Origin": "http://attacker.example"])
    #expect(mismatchedOrigin.status == 403)
    #expect(!mismatchedOrigin.text.contains("example.com"))
    let invalid = try await request(
      base.appendingPathComponent("/api/state"),
      headers: ["Authorization": "Bearer invalid"])
    #expect(invalid.status == 401)
    let replacement = try await request(
      base.appendingPathComponent("/api/login"),
      method: "POST", headers: ["Origin": origin],
      body: #"{"password":"correct"}"#)
    let newTicket = try #require(
      JSONSerialization.jsonObject(with: replacement.data) as? [String: String])
    let newToken = try #require(newTicket["token"])
    #expect(newToken != token)
    let oldSession = try await request(
      base.appendingPathComponent("/api/state"),
      headers: ["Authorization": "Bearer \(token)"])
    #expect(oldSession.status == 401)
    #expect(!oldSession.text.contains("example.com"))
    fixture.clock.advance(by: 15 * 60 - 1)
    let polling = try await request(
      base.appendingPathComponent("/api/state"),
      headers: ["Authorization": "Bearer \(newToken)"])
    #expect(polling.status == 200)
    fixture.clock.advance(by: 2)
    let expired = try await request(
      base.appendingPathComponent("/api/state"),
      headers: ["Authorization": "Bearer \(newToken)"])
    #expect(expired.status == 401)
    #expect(!expired.text.contains("example.com"))
  }

}

@MainActor
struct WebAdministrationEditingHTTPTests {
  // One session checks the same draft through validation, save and the Root result.
  // swiftlint:disable:next function_body_length
  @Test func liveHTTPEditsTheNativeDraftAndSavesThroughRoot() async throws {
    let fixture = RuntimeFixture()
    let server = WebAdministrationServer(port: 0)
    server.attach(runtime: fixture.runtime, locale: { Locale(identifier: "en") })
    defer {
      server.stop()
      fixture.runtime.stop()
    }
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.passcodeEdited("correct-passcode"), from: .settings)
    #expect(
      fixture.runtime.send(.configurePasscodeRequested, from: .settings).reply
        == .accepted)
    let credential = try #require(fixture.runtime.snapshot.root.credentialOperation)
    fixture.port.deliver(.credentialConfigured(credential, succeeded: true), source: .credentials)
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    fixture.runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .settings)
    #expect(fixture.runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
    let initialSave = try #require(
      fixture.port.effects.last { effect in
        if case .saveProfile = effect.kind { return true }
        return false
      })
    guard case .saveProfile(let initialProfile) = initialSave.kind else { return }
    fixture.port.deliver(
      .profileSaved(initialSave.token, initialProfile),
      source: .profileRepository)
    let start = try #require(fixture.runtime.snapshot.root.webServerOperation)
    guard case .success(let endpoint) = await server.start() else {
      Issue.record("Listener did not start")
      return
    }
    fixture.port.deliver(.webServerStarted(start, endpoint), source: .webAdministration)
    let port = try #require(server.listeningPort)
    let base = try #require(URL(string: "http://127.0.0.1:\(port)"))
    let origin = "http://127.0.0.1:\(port)"

    let anonymous = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST", headers: ["Origin": origin],
      body: #"{"field":"startURL","value":"https://example.com/next"}"#)
    #expect(anonymous.status == 401)
    let anonymousStart = try await request(
      base.appendingPathComponent("/api/exhibition/start"),
      method: "POST", headers: ["Origin": origin], body: "{}")
    #expect(anonymousStart.status == 401)
    fixture.port.onExecute = { effect in
      if case .verifyPasscode = effect.kind {
        fixture.port.deliver(
          .credentialVerified(effect.token, succeeded: true),
          source: .credentials)
      }
    }
    let login = try await request(
      base.appendingPathComponent("/api/login"),
      method: "POST", headers: ["Origin": origin], body: #"{"password":"correct"}"#)
    let ticket = try #require(JSONSerialization.jsonObject(with: login.data) as? [String: String])
    let token = try #require(ticket["token"])
    let authorization = ["Origin": origin, "Authorization": "Bearer \(token)"]
    let wrongStartOrigin = try await request(
      base.appendingPathComponent("/api/exhibition/start"),
      method: "POST",
      headers: ["Origin": "http://attacker.example", "Authorization": "Bearer \(token)"],
      body: "{}")
    #expect(wrongStartOrigin.status == 403)
    let wrongOrigin = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST",
      headers: [
        "Origin": "http://attacker.example",
        "Authorization": "Bearer \(token)",
      ],
      body: #"{"field":"startURL","value":"https://example.com/next"}"#)
    #expect(wrongOrigin.status == 403)
    let forbidden = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST", headers: authorization,
      body: #"{"field":"webAdministrationEnabled","value":false}"#)
    #expect(forbidden.status == 403)
    let smuggled = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST", headers: authorization,
      body: #"{"field":"startURL","value":"https://example.com/next","password":"new"}"#)
    #expect(smuggled.status == 403)
    let invalid = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST", headers: authorization,
      body: #"{"field":"startURL","value":"not-a-url"}"#)
    #expect(invalid.status == 200)
    #expect(invalid.text.contains("homeNotAllowed"))
    let invalidSave = try await request(
      base.appendingPathComponent("/api/draft/save"),
      method: "POST", headers: authorization, body: "{}")
    #expect(invalidSave.status == 422)

    let edited = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST", headers: authorization,
      body: #"{"field":"startURL","value":"https://example.com/next"}"#)
    #expect(edited.status == 200)
    #expect(
      fixture.runtime.snapshot.administration.draft?.profile.startURL
        == "https://example.com/next")
    let unsavedStart = try await request(
      base.appendingPathComponent("/api/exhibition/start"),
      method: "POST", headers: authorization, body: "{}")
    #expect(unsavedStart.status == 409)
    #expect(unsavedStart.text.contains("unsavedDraft"))
    fixture.runtime.send(
      .macDisplaysChanged([
        .init(id: "screen-1", name: "Current display", builtIn: true)
      ]), from: .platform)
    let unavailableOutput = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST", headers: authorization,
      body: #"{"field":"macDisplayID","value":"missing"}"#)
    #expect(unavailableOutput.status == 409)
    #expect(unavailableOutput.text.contains("unsupportedDisplays"))
    let selectedOutput = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST", headers: authorization,
      body: #"{"field":"macDisplayID","value":"screen-1"}"#)
    #expect(selectedOutput.status == 200)
    let saving = try await request(
      base.appendingPathComponent("/api/draft/save"),
      method: "POST", headers: authorization, body: "{}")
    #expect(saving.status == 202)
    let editWhileSaving = try await request(
      base.appendingPathComponent("/api/draft/edit"),
      method: "POST", headers: authorization,
      body: #"{"field":"startURL","value":"https://example.com/later"}"#)
    #expect(editWhileSaving.status == 409)
    let save = try #require(
      fixture.port.effects.last { effect in
        if case .saveProfile = effect.kind { return true }
        return false
      })
    guard case .saveProfile(let saved) = save.kind else { return }
    fixture.port.deliver(.profileSaved(save.token, saved), source: .profileRepository)
    #expect(
      fixture.runtime.snapshot.root.savedProfile?.startURL
        == "https://example.com/next")
    #expect(fixture.runtime.snapshot.root.savedProfile?.macOutput?.displayID == "screen-1")
    #expect(
      fixture.runtime.snapshot.administration.draft?.profile.startURL
        == "https://example.com/next")
    let startResponse = try await request(
      base.appendingPathComponent("/api/exhibition/start"),
      method: "POST", headers: authorization, body: "{}")
    #expect(startResponse.status == 202)
    #expect(fixture.runtime.snapshot.root.mode == .enteringKiosk)
    #expect(!fixture.runtime.snapshot.root.administratorSession)
    let presentation = try #require(fixture.runtime.snapshot.root.presentationOperation)
    fixture.port.deliver(.presentationFailed(presentation), source: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .safeHold)
    #expect(fixture.runtime.snapshot.root.webRestartFailed)
  }

}

extension Result where Success == WebServerEndpoint, Failure == WebServerFailure {
  fileprivate var isSuccess: Bool {
    if case .success = self { return true }
    return false
  }
}
