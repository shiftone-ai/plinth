import AppKit
import Foundation
import KioskCore
import Testing
import WebKit

@testable import KioskMacApp
@testable import KioskRuntime

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_NATIVE_TESTS"] == "1"))
@MainActor
struct NativeIframeNavigationTests {
  @Test(.timeLimit(.minutes(1)))
  func exhibitionPageCannotOpenLocalManagementOrigin() async throws {
    guard #available(macOS 15.0, *) else { throw NavigationFailure.load }
    _ = NSApplication.shared
    let exhibition = try FixtureServer()
    let management = try FixtureServer()
    defer {
      exhibition.stop()
      management.stop()
    }
    try await exhibition.start()
    try await management.start()
    let harness = NativeWebHarness()
    defer { harness.shutdown() }
    let exhibitionOrigin = try #require(Origin(urlString: exhibition.origin))
    let managementOrigin = try #require(Origin(urlString: management.origin))
    var profile = KioskProfile(
      startURL: exhibition.origin + "/home",
      navigation: .init(rules: [.init(id: 1, origin: exhibitionOrigin)], allowsHTTP: true))
    profile.webAdministrationEnabled = true
    var events = harness.events.makeAsyncIterator()
    harness.runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    try await finished(&events)
    let start = try #require(harness.runtime.snapshot.root.webServerOperation)
    harness.runtime.send(
      .webServerStarted(start, .init(url: management.origin + "/", origins: [managementOrigin])),
      from: .webAdministration)
    let view = try #require(harness.adapter.webView)
    try await view.evaluateJavaScript(
      "document.body.insertAdjacentHTML('beforeend', '<a id=management href=\"\(management.origin)/allowed\">Open</a>'); "
        + "document.getElementById('management').click()")
    while let event = await events.next(isolation: MainActor.shared) {
      if case .navigationRequested(let address, _, let mainFrame, _, _, _) = event,
        address == management.origin + "/allowed"
      {
        #expect(mainFrame)
        break
      }
    }
    #expect(
      harness.runtime.reports.contains {
        $0.reply == .navigation(.cancel(.urlBlocked)) && $0.source == .webSurface
      })
    #expect(view.url?.absoluteString == exhibition.origin + "/home")
  }

  @Test(.timeLimit(.minutes(1)))
  func iframeCannotNavigateToLocalManagementOrigin() async throws {
    guard #available(macOS 15.0, *) else { return }
    _ = NSApplication.shared
    let exhibition = try FixtureServer()
    let management = try FixtureServer()
    defer {
      exhibition.stop()
      management.stop()
    }
    try await exhibition.start()
    try await management.start()
    let harness = NativeWebHarness()
    defer { harness.shutdown() }
    let adminOrigin = try #require(Origin(urlString: management.origin))
    let profile = try exhibitionProfile(origin: exhibition.origin)
    var events = harness.events.makeAsyncIterator()
    harness.runtime.send(
      .bootstrapped(
        profile: profile, credentialsConfigured: true,
        displayCount: 1), from: .root)
    let view = try #require(harness.adapter.webView)
    try await finished(&events)
    let start = try #require(harness.runtime.snapshot.root.webServerOperation)
    harness.runtime.send(
      .webServerStarted(
        start,
        .init(url: management.origin + "/", origins: [adminOrigin])), from: .webAdministration)
    try await view.evaluateJavaScript(
      """
      const frame = document.createElement('iframe');
      frame.src = '\(management.origin)/allowed';
      document.body.append(frame);
      """)
    while let event = await events.next(isolation: MainActor.shared) {
      if case .navigationRequested(let address, _, let mainFrame, _, _, _) = event,
        address == management.origin + "/allowed"
      {
        #expect(!mainFrame)
        break
      }
    }
    #expect(
      harness.runtime.reports.contains {
        $0.reply == .navigation(.cancel(.urlBlocked)) && $0.source == .webSurface
      })
    #expect(view.url?.absoluteString == exhibition.origin + "/home")
  }

  private func exhibitionProfile(origin: String) throws -> KioskProfile {
    let allowed = try #require(Origin(urlString: origin))
    var profile = KioskProfile(
      startURL: origin + "/home",
      navigation: .init(rules: [.init(id: 1, origin: allowed)], allowsHTTP: true))
    profile.webAdministrationEnabled = true
    return profile
  }

  @available(macOS 15.0, *)
  private func finished(_ iterator: inout AsyncStream<Event>.Iterator) async throws {
    while let event = await iterator.next(isolation: MainActor.shared) {
      if case .webFinished = event { return }
      if case .webFailed(_, let failure) = event {
        Issue.record("WebKit failed: \(failure)")
        throw NavigationFailure.load
      }
    }
    throw NavigationFailure.load
  }

  private enum NavigationFailure: Error { case load }

}
