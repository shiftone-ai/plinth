import AppKit
import Foundation
import KioskCore
import Testing
import WebKit

@testable import KioskRuntime

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_NATIVE_TESTS"] == "1"), .serialized)
@MainActor
struct ExternalInputTests {
  @Test(.timeLimit(.minutes(1)))
  func hoverPointerCaptureDragDropAndActivationUseActualWebKit() async throws {
    guard #available(macOS 15.0, *) else { throw InputFailure.load }
    _ = NSApplication.shared
    let server = try FixtureServer()
    defer { server.stop() }
    try await server.start()
    let harness = NativeWebHarness()
    defer { harness.shutdown() }
    harness.adapter.host.frame = CGRect(x: 0, y: 0, width: 720, height: 640)
    let origin = try #require(Origin(urlString: server.origin))
    var profile = KioskProfile(
      startURL: server.origin + "/input",
      navigation: .init(rules: [.init(id: 1, origin: origin)], allowsHTTP: true),
      interaction: .init(allowsScroll: true, allowsDrag: true))
    profile.exhibitionDestination = .externalDisplay
    harness.runtime.send(
      .mobileDisplaysChanged(
        .init(
          deviceAvailable: true,
          externalAvailable: true, externalDisplayOnly: true)), from: .platform)
    var events = harness.events.makeAsyncIterator()
    harness.runtime.send(
      .bootstrapped(
        profile: profile, credentialsConfigured: true,
        displayCount: 1), from: .root)
    while let event = await events.next(isolation: MainActor.shared) {
      if case .webFinished = event { break }
      if case .webFailed = event { throw InputFailure.load }
    }
    let view = try #require(harness.adapter.webView)
    try #require(harness.runtime.snapshot.root.mode == .exhibiting)
    let generation = harness.runtime.snapshot.exhibition.generation
    let token = OperationToken(
      owner: .root, ownerEpoch: harness.runtime.snapshot.root.epoch, operationID: 999,
      webGeneration: generation)
    func point(_ id: String) async throws -> SurfacePoint {
      let values = try #require(
        try await view.callAsyncJavaScript(
          "const r=document.getElementById(id).getBoundingClientRect(); return [(r.x+r.width/2)/innerWidth,(r.y+r.height/2)/innerHeight]",
          arguments: ["id": id], in: nil, contentWorld: .page) as? [Double])
      return .init(x: values[0], y: values[1])
    }
    let hover = try await point("hover")
    await harness.adapter.control(.move(hover), token: token)
    #expect(
      try await view.evaluateJavaScript(
        "getComputedStyle(document.getElementById('hover')).backgroundColor") as? String
        == "rgb(255, 0, 0)")
    let canvas = try await point("canvas")
    await harness.adapter.control(.press(canvas), token: token)
    await harness.adapter.control(.move(.init(x: 0.9, y: canvas.y)), token: token)
    #expect(
      try await view.evaluateJavaScript("document.getElementById('pointer-result').textContent")
        as? String == "Pointer dragged")
    await harness.adapter.control(.release(.init(x: 0.9, y: canvas.y)), token: token)
    #expect(
      try await view.evaluateJavaScript("document.getElementById('pointer-result').textContent")
        as? String == "Pointer released")
    let source = try await point("drag-source")
    let destination = try await point("drop-target")
    await harness.adapter.control(.press(source), token: token)
    await harness.adapter.control(.move(destination), token: token)
    await harness.adapter.control(.release(destination), token: token)
    #expect(
      try await view.evaluateJavaScript("document.getElementById('drop-result').textContent")
        as? String == "Drop accepted")
    await harness.adapter.control(.activate(try await point("audio-button")), token: token)
    // An unshown NSView does not prove audible playback. The visible Simulator UI test does.
    #expect(try await view.evaluateJavaScript("window.activationAtClick") as? Bool == true)
    _ = try await view.evaluateJavaScript("fixtureAudio.close(); true")
  }
  private enum InputFailure: Error { case load }
}
