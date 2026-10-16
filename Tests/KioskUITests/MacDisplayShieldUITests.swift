import AppKit
import Foundation
import XCTest
import XCUIAutomation

extension KioskWorkflowUITests {
  @MainActor func testBuiltInDisplayShowsAdministratorShortcut() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_OS_PRESENTATION_TESTS"] == "1",
      NSScreen.screens.contains(where: Self.isBuiltIn),
      NSScreen.screens.contains(where: { !Self.isBuiltIn($0) })
    else { throw XCTSkip("Requires a Mac with built-in and external displays.") }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-shield-ui-\(UUID())")
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    let passcode = "plinth-shield-passcode"
    let server = try FixtureServer()
    try await server.start()
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment = [
      "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
      "PLINTH_TEST_CREDENTIAL_SERVICE": service,
      "PLINTH_DEDICATED_MAC": "1",
      "PLINTH_TEST_OS_PRESENTATION": "1",
    ]
    addTeardownBlock {
      await MainActor.run {
        app.terminate()
        server.stop()
        try? FileManager.default.removeItem(at: directory)
      }
    }
    app.launch()
    let start = await configureAndStart(app, origin: server.origin, passcode: passcode)

    let title = app.descendants(matching: .any)["shield-unlock-title"]
    let shortcut = app.descendants(matching: .any)["shield-unlock-shortcut"]
    await waitFor(shortcut)
    XCTAssertEqual(title.value as? String, "Administrator unlock")
    XCTAssertEqual(shortcut.value as? String, "⌘ ⌥ ⇧ K")
    attach(app, name: "administrator-shortcut-on-built-in-display")

    app.typeKey("k", modifierFlags: [.command, .option, .shift])
    let unlock = app.secureTextFields["unlock-passcode"]
    await waitFor(unlock)
    replace(unlock, with: passcode)
    app.buttons["verify-passcode"].click()
    await waitFor(start)
    XCTAssertFalse(shortcut.exists)
  }

  @MainActor private func configureAndStart(
    _ app: XCUIApplication, origin: String, passcode: String
  ) async -> XCUIElement {
    let start = app.buttons["start-exhibition"]
    await waitFor(start)
    replace(app.textFields["start-url"], with: origin + "/home")
    app.activate()
    let allowHTTP = app.switches["allow-http"]
    allowHTTP.click()
    app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -800)
    let setup = app.secureTextFields["setup-passcode"]
    replace(setup, with: passcode)
    app.activate()
    app.buttons["save-passcode"].click()
    let save = app.buttons["save-profile"]
    let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    await fulfillment(of: [enabled], timeout: 10)
    save.click()
    let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
    await fulfillment(of: [ready], timeout: 10)
    start.click()
    return start
  }

  private static func isBuiltIn(_ screen: NSScreen) -> Bool {
    guard
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? NSNumber
    else { return false }
    return CGDisplayIsBuiltin(number.uint32Value) != 0
  }
}
