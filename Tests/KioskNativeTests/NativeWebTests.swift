import AppKit
import Foundation
import KioskCore
import Testing
import WebKit

@testable import KioskMacApp
@testable import KioskRuntime

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_NATIVE_TESTS"] == "1"), .serialized)
@MainActor
struct NativeWebTests {
  @Test(.timeLimit(.minutes(1)))
  func externalControlActivatesRealLinksAndKeepsNavigationPolicy() async throws {
    guard #available(macOS 15.0, *) else { throw NativeFailure.load }
    _ = NSApplication.shared
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let harness = NativeWebHarness()
    defer { harness.shutdown() }
    harness.adapter.host.frame = CGRect(x: 0, y: 0, width: 720, height: 480)
    let origin = try #require(Origin(urlString: server.origin))
    var profile = KioskProfile(
      startURL: server.origin + "/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)], allowsHTTP: true),
      interaction: .init(allowsScroll: true))
    profile.exhibitionDestination = .externalDisplay
    harness.runtime.send(
      .mobileDisplaysChanged(
        .init(
          deviceAvailable: true, externalAvailable: true,
          supportsExhibitionWindow: false, externalDisplayOnly: true)), from: .platform)
    var events = harness.events.makeAsyncIterator()
    harness.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    try await finished(&events)
    let view = try #require(harness.adapter.webView)
    let generation = harness.runtime.snapshot.exhibition.generation
    let coordinates = try #require(
      try await view.evaluateJavaScript(
        """
        (()=>{const r=document.getElementById('allowed').getBoundingClientRect();
        return [(r.x+r.width/2)/innerWidth,(r.y+r.height/2)/innerHeight]})()
        """) as? [Double])
    let point = SurfacePoint(x: coordinates[0], y: coordinates[1])
    #expect(
      harness.runtime.send(
        .externalWebControlRequested(.activate(point), generation: generation), from: .platform
      ).reply == .accepted)
    try await finished(&events)
    #expect(view.url?.absoluteString == server.origin + "/allowed")
    let blocked = try #require(
      try await view.evaluateJavaScript(
        """
        (()=>{const r=document.getElementById('blocked').getBoundingClientRect();
        return [(r.x+r.width/2)/innerWidth,(r.y+r.height/2)/innerHeight]})()
        """) as? [Double])
    harness.runtime.send(
      .externalWebControlRequested(
        .activate(.init(x: blocked[0], y: blocked[1])), generation: generation), from: .platform)
    while let event = await events.next(isolation: MainActor.shared) {
      if case .navigationRequested(let address, _, _, _, _, _) = event, address == server.blockedURL
      {
        break
      }
    }
    #expect(view.url?.absoluteString == server.origin + "/allowed")
    harness.runtime.send(.unlockRequested, from: .platform)
    await harness.adapter.control(
      .activate(point), token: .init(owner: .root, operationID: 99, webGeneration: generation))
    #expect(harness.runtime.snapshot.root.mode == .unlocking)
    #expect(view.url?.absoluteString == server.origin + "/allowed")
  }

  @Test(.timeLimit(.minutes(1)), arguments: ["/deny-redirect", "/binary"])
  func refusedInitialNavigationSettlesInSafeHold(path: String) async throws {
    guard #available(macOS 15.0, *) else { throw NativeFailure.load }
    _ = NSApplication.shared
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let harness = NativeWebHarness()
    defer { harness.shutdown() }
    let origin = try #require(Origin(urlString: server.origin))
    let profile = KioskProfile(
      startURL: server.origin + path,
      navigation: .init(rules: [.init(id: 1, origin: origin)], allowsHTTP: true))
    var events = harness.events.makeAsyncIterator()
    harness.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    var refused = false
    while let event = await events.next(isolation: MainActor.shared) {
      if case .navigationRequested(let address, _, let mainFrame, _, _, let supported) = event,
        mainFrame && (address == server.blockedURL || !supported)
      {
        refused = true
        break
      }
      if case .webFinished = event { throw NativeFailure.load }
    }
    #expect(refused)
    #expect(harness.runtime.snapshot.root.mode == .safeHold)
    #expect(harness.runtime.snapshot.exhibition.phase == .inactive)
    #expect(harness.runtime.snapshot.exhibition.retryAttempt == 0)
    #expect(harness.adapter.webView == nil)
  }

  @Test func oldNavigationStartAndFinishCannotBeRelabeledAsTheNewLoad() async throws {
    _ = NSApplication.shared
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let adapter = WebKitAdapter()
    defer { adapter.stop() }
    adapter.create(
      .init(owner: .exhibition, operationID: 1, webGeneration: 1), mode: .newVisitorSession)
    var delivered: [Event] = []
    adapter.send = { event in
      delivered.append(event)
      return .navigation(.allow)
    }
    try #require(
      adapter.load(
        server.origin + "/old",
        token: .init(owner: .exhibition, operationID: 2, webGeneration: 1)))
    let old = try #require(adapter.navigation)
    try #require(
      adapter.load(
        server.origin + "/current",
        token: .init(owner: .exhibition, operationID: 3, webGeneration: 1)))
    let current = try #require(adapter.navigation)
    let view = try #require(adapter.webView)
    delivered.removeAll()
    adapter.webView(view, didStartProvisionalNavigation: old)
    adapter.webView(view, didFinish: old)
    #expect(adapter.navigation === current)
    #expect(delivered.isEmpty)
  }
  @Test(.timeLimit(.minutes(1)))
  func realLinksRedirectsAndPopupUseCoreDecisions() async throws {
    guard #available(macOS 15.0, *) else { throw NativeFailure.load }
    _ = NSApplication.shared
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let harness = NativeWebHarness()
    defer { harness.shutdown() }
    let origin = try #require(Origin(urlString: server.origin))
    let profile = KioskProfile(
      startURL: server.origin + "/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)], allowsHTTP: true))
    var iterator = harness.events.makeAsyncIterator()
    harness.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    try await finished(&iterator)
    #expect(harness.runtime.snapshot.root.mode == .exhibiting)
    let view = try #require(harness.adapter.webView)
    try await view.evaluateJavaScript("document.getElementById('allowed').click()")
    try await finished(&iterator)
    #expect(view.url?.absoluteString == server.origin + "/allowed")
    try await view.evaluateJavaScript("document.getElementById('redirect').click()")
    try await finished(&iterator)
    #expect(view.url?.absoluteString == server.origin + "/allowed")
    try await view.evaluateJavaScript("document.getElementById('popup').click()")
    try await finished(&iterator)
    #expect(harness.adapter.webView === view)
    #expect(view.url?.absoluteString == server.origin + "/popup")
    try await view.evaluateJavaScript("document.getElementById('blocked').click()")
    while let event = await iterator.next(isolation: MainActor.shared) {
      if case .navigationRequested(let address, _, _, _, _, _) = event, address == server.blockedURL
      {
        break
      }
    }
    #expect(view.url?.absoluteString == server.origin + "/popup")
    #expect(harness.runtime.snapshot.exhibition.phase == .ready)
    try await view.evaluateJavaScript("document.getElementById('dialogs').click()")
    let dialogResult = try await view.evaluateJavaScript("document.body.dataset.result") as? String
    #expect(dialogResult == "false-null")
  }

  @available(macOS 15.0, *)
  private func finished(_ iterator: inout AsyncStream<Event>.Iterator) async throws {
    while let event = await iterator.next(isolation: MainActor.shared) {
      if case .webFinished = event { return }
      if case .webFailed(_, let failure) = event {
        Issue.record("WebKit failed: \(failure)")
        throw NativeFailure.load
      }
    }
    throw NativeFailure.load
  }
  private enum NativeFailure: Error { case load }

  @Test func surfaceRecreationHonorsWebsiteDataModeWithoutActivatingWindow() throws {
    _ = NSApplication.shared
    let adapter = WebKitAdapter()
    defer { adapter.stop() }
    let token = OperationToken(owner: .exhibition, ownerEpoch: 1, operationID: 1, webGeneration: 1)
    adapter.create(token, mode: .newVisitorSession)
    let original = try #require(adapter.webView)
    let originalData = original.configuration.websiteDataStore
    #expect(!originalData.isPersistent)
    #expect(!original.allowsMagnification)
    #expect(!original.allowsBackForwardNavigationGestures)
    #expect(original.configuration.mediaTypesRequiringUserActionForPlayback == .audio)
    adapter.create(
      .init(owner: .exhibition, ownerEpoch: 1, operationID: 2, webGeneration: 2),
      mode: .retainWebsiteData)
    let retained = try #require(adapter.webView)
    #expect(retained !== original)
    #expect(retained.configuration.websiteDataStore === originalData)
    #expect(original.superview == nil)
    #expect(original.navigationDelegate == nil)
    adapter.create(
      .init(owner: .exhibition, ownerEpoch: 1, operationID: 3, webGeneration: 3),
      mode: .newVisitorSession)
    let fresh = try #require(adapter.webView)
    #expect(fresh.configuration.websiteDataStore !== originalData)
    adapter.releaseSurface()
    #expect(adapter.webView == nil)
    #expect(adapter.host.subviews.isEmpty)
  }
}
