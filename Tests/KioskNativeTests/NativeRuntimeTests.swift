import AppKit
import Foundation
import KioskCore
import KioskMacApp
import KioskRuntime
import LocalAuthentication
import Security
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_NATIVE_TESTS"] == "1"), .serialized)
@MainActor
struct NativeRuntimeTests {
  @Test(.timeLimit(.minutes(1)))
  func realConnectionFailuresRetryOnlyToTheConfiguredLimit() async throws {
    guard #available(macOS 15.0, *) else { throw FixtureFailure.unsupportedOS }
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-native-failure-\(UUID())")
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    defer {
      let context = LAContext()
      context.interactionNotAllowed = true
      let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword, kSecAttrService: service,
        kSecAttrAccount: "administrator-verifier", kSecUseAuthenticationContext: context,
      ]
      let status = SecItemDelete(query as CFDictionary)
      #expect(status == errSecSuccess || status == errSecItemNotFound)
      try? FileManager.default.removeItem(at: directory)
    }
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let web = WebKitAdapter()
    let displays = FixtureDisplay()
    let credentials = CredentialStore(service: service)
    let repository = ProfileRepository(fileURL: directory.appendingPathComponent("profile.json"))
    let origin = try #require(Origin(urlString: server.origin))
    let profile = KioskProfile(
      startURL: server.origin + "/network-failure",
      navigation: .init(rules: [.init(id: 1, origin: origin)], allowsHTTP: true),
      recovery: .init(maximumAttempts: 2, delay: 0.05))
    try await credentials.configure("fixture-admin-passcode")
    try await repository.save(profile)
    let port = NativeEffectPort(
      web: web,
      presentation: PresentationAdapter(window: window, preview: true, displays: displays),
      repository: repository, credentials: credentials,
      biometrics: BiometricCredentialAdapter(
        service: "ai.shiftone.plinth.tests.\(UUID())",
        enableReason: { "Enable administrator unlock with biometrics" },
        unlockReason: { "Unlock administrator settings" }),
      clock: MonotonicClock(), displays: displays)
    let executor = EffectExecutor(port: port)
    let runtime = RootRuntime(clock: MonotonicClock(), executor: executor)
    defer { runtime.stop() }
    let stream = AsyncStream<Event>.makeStream()
    defer { stream.continuation.finish() }
    web.send = { [weak runtime] event in
      let reply = runtime?.send(event, from: .webSurface).reply
      stream.continuation.yield(event)
      return reply
    }
    var events = stream.stream.makeAsyncIterator()
    runtime.send(.bootstrapRequested, from: .root)
    var failures = 0
    while let event = await events.next(isolation: MainActor.shared) {
      if case .webFailed(_, let failure) = event {
        #expect(failure == .network)
        failures += 1
        if failures == 3 { break }
      }
    }
    #expect(failures == 3)
    #expect(runtime.snapshot.root.mode == .safeHold)
    #expect(runtime.snapshot.exhibition.retryAttempt == 2)
    if let release = runtime.snapshot.exhibition.releaseOperation {
      await executor.registry.waitForOperation(release)
    }
    #expect(runtime.snapshot.exhibition.phase == .inactive)
    #expect(runtime.snapshot.exhibition.retryOperation == nil)
    #expect(web.webView == nil)
  }
  @Test(.timeLimit(.minutes(1)))
  func realPortsSaveExhibitResetAndAuthenticateWithoutChangingPresentation() async throws {
    guard #available(macOS 15.0, *) else { throw FixtureFailure.unsupportedOS }
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-native-runtime-\(UUID())")
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    defer {
      let context = LAContext()
      context.interactionNotAllowed = true
      let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword, kSecAttrService: service,
        kSecAttrAccount: "administrator-verifier", kSecUseAuthenticationContext: context,
      ]
      let status = SecItemDelete(query as CFDictionary)
      #expect(status == errSecSuccess || status == errSecItemNotFound)
      try? FileManager.default.removeItem(at: directory)
    }
    let originalPresentation = NSApplication.shared.presentationOptions
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let web = WebKitAdapter()
    let clock = ControlledNativeClock()
    let repository = ProfileRepository(fileURL: directory.appendingPathComponent("profile.json"))
    let credentials = CredentialStore(service: service)
    let displays = FixtureDisplay()
    let port = NativeEffectPort(
      web: web,
      presentation: PresentationAdapter(window: window, preview: true, displays: displays),
      repository: repository, credentials: credentials,
      biometrics: BiometricCredentialAdapter(
        service: "ai.shiftone.plinth.tests.\(UUID())",
        enableReason: { "Enable administrator unlock with biometrics" },
        unlockReason: { "Unlock administrator settings" }),
      clock: clock, displays: displays)
    let executor = EffectExecutor(port: port)
    let runtime = RootRuntime(clock: clock, executor: executor)
    defer { runtime.stop() }
    let stream = AsyncStream<Event>.makeStream()
    defer { stream.continuation.finish() }
    web.send = { [weak runtime] event in
      let reply = runtime?.send(event, from: .webSurface).reply
      stream.continuation.yield(event)
      return reply
    }
    var pages = stream.stream.makeAsyncIterator()
    runtime.send(.bootstrapRequested, from: .root)
    let bootstrap = try #require(runtime.snapshot.root.bootstrapOperation)
    await executor.registry.waitForOperation(bootstrap)
    #expect(runtime.snapshot.root.mode == .administration)
    runtime.send(.passcodeEdited("fixture-admin-passcode"), from: .settings)
    runtime.send(.configurePasscodeRequested, from: .settings)
    let setup = try #require(runtime.snapshot.root.credentialOperation)
    await executor.registry.waitForOperation(setup)
    try #require(runtime.snapshot.root.credentialsConfigured)
    let origin = try #require(Origin(urlString: server.origin))
    let profile = KioskProfile(
      startURL: server.origin + "/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)], allowsHTTP: true),
      idleTimeout: 86_400)
    runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .settings)
    runtime.send(.saveDraftRequested, from: .settings)
    let save = try #require(runtime.snapshot.root.saveOperation)
    await executor.registry.waitForOperation(save)
    #expect(try await repository.load() == profile)
    try #require(runtime.settingsProps.props.canStart)
    runtime.send(.startExhibitionRequested, from: .settings)
    try await finished(&pages)
    #expect(runtime.snapshot.root.mode == .exhibiting)
    #expect(NSApplication.shared.presentationOptions == originalPresentation)
    let firstView = try #require(web.webView)
    try await firstView.evaluateJavaScript("document.getElementById('allowed').click()")
    try await finished(&pages)
    #expect(runtime.snapshot.exhibition.currentURL == server.origin + "/allowed")
    let idle = try #require(runtime.snapshot.exhibition.idleOperation)
    clock.now = profile.idleTimeout
    runtime.send(.idleDeadlineReached(idle), from: .idleClock)
    await executor.registry.waitForOperation(idle)
    try await finished(&pages)
    #expect(web.webView !== firstView)
    #expect(runtime.snapshot.exhibition.currentURL == server.origin + "/home")
    #expect(runtime.snapshot.exhibition.idleOperation == nil)
    let beforeShortcut = try #require(web.webView)
    try await beforeShortcut.evaluateJavaScript("document.getElementById('allowed').click()")
    try await finished(&pages)
    #expect(runtime.snapshot.exhibition.currentURL == server.origin + "/allowed")
    #expect(runtime.send(.shortcutResetRequested, from: .platform).reply == .accepted)
    #expect(
      runtime.send(.shortcutResetRequested, from: .platform).reply == .rejected(.invalidState))
    try await finished(&pages)
    #expect(web.webView !== beforeShortcut)
    #expect(runtime.snapshot.exhibition.currentURL == server.origin + "/home")
    #expect(runtime.snapshot.root.mode == .exhibiting)
    #expect(runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    runtime.send(.passcodeEdited("incorrect-passcode"), from: .unlock)
    runtime.send(.passcodeSubmitted, from: .unlock)
    let rejected = try #require(runtime.snapshot.administration.verification)
    await executor.registry.waitForOperation(rejected)
    #expect(runtime.snapshot.root.mode == .unlocking)
    #expect(runtime.snapshot.administration.failedAttempts == 1)
    runtime.send(.cancelAuthentication, from: .unlock)
    try await finished(&pages)
    #expect(runtime.snapshot.root.mode == .exhibiting)
    runtime.send(.unlockRequested, from: .platform)
    runtime.send(.passcodeEdited("fixture-admin-passcode"), from: .unlock)
    runtime.send(.passcodeSubmitted, from: .unlock)
    let authentication = try #require(runtime.snapshot.administration.verification)
    await executor.registry.waitForOperation(authentication)
    // Successful authentication starts ordered surface and Presentation release effects.
    if let release = runtime.snapshot.exhibition.releaseOperation {
      await executor.registry.waitForOperation(release)
    }
    if let release = runtime.snapshot.root.presentationOperation {
      await executor.registry.waitForOperation(release)
    }
    #expect(runtime.snapshot.root.mode == .administration)
    #expect(runtime.snapshot.root.administratorSession)
    #expect(web.webView == nil)
    #expect(NSApplication.shared.presentationOptions == originalPresentation)
  }

  @available(macOS 15.0, *)
  private func finished(_ iterator: inout AsyncStream<Event>.Iterator) async throws {
    while let event = await iterator.next(isolation: MainActor.shared) {
      if case .webFinished = event { return }
      if case .webFailed = event { throw FixtureFailure.webLoad }
    }
    throw FixtureFailure.webLoad
  }
  private enum FixtureFailure: Error { case unsupportedOS, webLoad }
}

@MainActor
private final class ControlledNativeClock: ClockPort {
  var now: Double = 0
}

@MainActor
private final class FixtureDisplay: DisplayReadingPort {
  let count = 1
  let exhibitionFrame: NSRect? = NSRect(x: 0, y: 0, width: 800, height: 600)
}
