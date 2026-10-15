import AppKit
import Foundation
import KioskCore
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_NATIVE_TESTS"] == "1"), .serialized)
@MainActor
struct NativeExternalScrollTests {
  @Test(.timeLimit(.minutes(1)), arguments: [false, true])
  func pixelScrollDistanceIsIndependentOfViewportAndTargetsNestedContent(portrait: Bool)
    async throws
  {
    guard #available(macOS 15.0, *) else { throw LoadFailure.failed }
    _ = NSApplication.shared
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let harness = NativeWebHarness()
    defer { harness.shutdown() }
    harness.adapter.host.frame = CGRect(
      x: 0, y: 0, width: portrait ? 480 : 720, height: portrait ? 720 : 480)
    let origin = try #require(Origin(urlString: server.origin))
    var profile = KioskProfile(
      startURL: server.origin + "/scroll",
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
    let viewport = try await view.evaluateJavaScript("[innerWidth, innerHeight]") as? [Double]
    #expect(viewport == (portrait ? [480, 720] : [720, 480]))
    let token = OperationToken(
      owner: .root, operationID: 90,
      webGeneration: harness.runtime.snapshot.exhibition.generation)
    await harness.adapter.control(.scroll(dx: 0, dy: 120), token: token)
    let pageOffset = try await view.evaluateJavaScript("scrollY") as? Double
    #expect(pageOffset == 120)

    _ = try await view.evaluateJavaScript(
      """
      const nested = document.createElement('div'); nested.id = 'nested';
      nested.style = 'position:fixed;inset:0;overflow:scroll';
      nested.innerHTML = '<div style="width:3000px;height:3000px"></div>';
      document.body.append(nested);
      """)
    await harness.adapter.control(.move(.init(x: 0.5, y: 0.5)), token: token)
    await harness.adapter.control(.scroll(dx: 40, dy: 80), token: token)
    await harness.adapter.control(.scroll(dx: -10, dy: -20), token: token)
    let offsets =
      try await view.evaluateJavaScript(
        "[scrollY, document.getElementById('nested').scrollLeft, document.getElementById('nested').scrollTop]"
      ) as? [Double]
    #expect(offsets == [120, 30, 60])
  }

  @available(macOS 15.0, *)
  private func finished(_ events: inout AsyncStream<Event>.Iterator) async throws {
    while let event = await events.next(isolation: MainActor.shared) {
      if case .webFinished = event { return }
      if case .webFailed = event { throw LoadFailure.failed }
    }
    throw LoadFailure.failed
  }

  private enum LoadFailure: Error { case failed }
}
