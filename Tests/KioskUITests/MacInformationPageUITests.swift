import Foundation
import XCTest
import XCUIAutomation

extension KioskWorkflowUITests {
  @MainActor func testInformationPagesLicensesAndStoreScreenshots() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_DEDICATED_MAC"] == "1" else {
      throw XCTSkip("GUI tests require an explicitly enabled dedicated Mac.")
    }
    continueAfterFailure = false
    let language = ProcessInfo.processInfo.environment["PLINTH_STORE_SCREENSHOT_LANGUAGE"] ?? "en"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-store-ui-\(UUID())")
    let server = try await makeDemoServer()
    let app = XCUIApplication()
    app.launchArguments = ["--preview", "-AppleLanguages", "(\(language))"]
    app.launchEnvironment = [
      "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
      "PLINTH_TEST_CREDENTIAL_SERVICE": "ai.shiftone.plinth.tests.\(UUID().uuidString)",
      "PLINTH_DEDICATED_MAC": "1",
      "PLINTH_TEST_OS_PRESENTATION": "0",
    ]
    addTeardownBlock {
      await MainActor.run {
        app.terminate()
        server.stop()
        try? FileManager.default.removeItem(at: directory)
      }
    }
    app.launch()
    let start = app.buttons["start-exhibition"]
    await waitFor(start, timeout: 10)
    let scroll = app.scrollViews.firstMatch
    scroll.scroll(byDeltaX: 0, deltaY: -700)

    app.buttons["licenses"].click()
    await waitFor(app.descendants(matching: .any)["license-empty"])
    app.buttons["license-close"].click()
    await waitFor(start)

    if language == "en" {
      await verifyInformationLinks(app, start: start)
    }
    scroll.scroll(byDeltaX: 0, deltaY: 700)
    replace(
      app.textFields["start-url"], with: server.origin + "/demo/index.html")
    app.switches["allow-http"].click()
    scroll.scroll(byDeltaX: 0, deltaY: -700)
    attachStoreWindow(app, name: "store-mac-settings-\(language)")

    replace(app.secureTextFields["setup-passcode"], with: "plinth-review-passcode")
    app.buttons["save-passcode"].click()
    app.buttons["save-profile"].click()
    XCTAssertTrue(start.isEnabled)
    start.click()
    await waitFor(app.webViews.links["Next exhibit"], timeout: 25)
    attachStoreHierarchy(app, language: language)
    attachStoreWindow(app, name: "store-mac-exhibition-\(language)")
  }

  @MainActor private func makeDemoServer() async throws -> FixtureServer {
    let demoDirectory = localDemoDirectory()
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: demoDirectory.appendingPathComponent("index.html").path))
    let server = try FixtureServer(demoDirectory: demoDirectory)
    try await server.start()
    return server
  }

  @MainActor private func localDemoDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("site/demo")
  }

  @MainActor private func verifyInformationLinks(_ app: XCUIApplication, start: XCUIElement) async {
    let browser = XCUIApplication(bundleIdentifier: "com.apple.Safari")
    for (link, heading) in [("privacy-policy", "Privacy Policy"), ("support", "Contact us")] {
      let button = app.buttons[link]
      XCTAssertTrue(button.isHittable)
      button.click()
      await waitFor(browser.webViews.staticTexts[heading], timeout: 25)
      app.activate()
      await waitFor(start)
    }
  }

  @MainActor private func attachStoreWindow(_ app: XCUIApplication, name: String) {
    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor private func attachStoreHierarchy(_ app: XCUIApplication, language: String) {
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "store-mac-exhibition-hierarchy-\(language)"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)
  }
}
