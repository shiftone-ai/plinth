import Foundation
import XCTest
import XCUIAutomation

extension KioskWorkflowUITests {
  @MainActor func testInformationPagesLicensesAndStoreScreenshots() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_DEDICATED_MAC"] == "1" else {
      throw XCTSkip("GUI tests require an explicitly enabled dedicated Mac.")
    }
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-store-ui-\(UUID())")
    let app = XCUIApplication()
    app.launchArguments = ["--preview", "-AppleLanguages", "(en)"]
    app.launchEnvironment = [
      "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
      "PLINTH_TEST_CREDENTIAL_SERVICE": "ai.shiftone.plinth.tests.\(UUID().uuidString)",
      "PLINTH_DEDICATED_MAC": "1",
      "PLINTH_TEST_OS_PRESENTATION": "0",
    ]
    addTeardownBlock {
      await MainActor.run {
        app.terminate()
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

    let browser = XCUIApplication(bundleIdentifier: "com.apple.Safari")
    for (link, heading) in [("privacy-policy", "Privacy Policy"), ("support", "Contact us")] {
      let button = app.buttons[link]
      XCTAssertTrue(button.isHittable)
      button.click()
      await waitFor(browser.webViews.staticTexts[heading], timeout: 25)
      app.activate()
      await waitFor(start)
    }
    attach(app, name: "store-mac-settings")

    await captureExhibition(app, start: start, scroll: scroll)
  }

  @MainActor private func captureExhibition(
    _ app: XCUIApplication, start: XCUIElement, scroll: XCUIElement
  ) async {
    scroll.scroll(byDeltaX: 0, deltaY: 700)
    replace(
      app.textFields["start-url"], with: "https://shiftone-ai.github.io/plinth/demo/index.html")
    scroll.scroll(byDeltaX: 0, deltaY: -700)
    replace(app.secureTextFields["setup-passcode"], with: "plinth-review-passcode")
    app.buttons["save-passcode"].click()
    app.buttons["save-profile"].click()
    XCTAssertTrue(start.isEnabled)
    start.click()
    let next = app.webViews.links["Next exhibit"]
    await waitFor(next, timeout: 25)
    app.webViews.firstMatch.scroll(byDeltaX: 0, deltaY: -700)
    next.click()
    await waitFor(app.webViews.staticTexts["Another view"], timeout: 25)
    attach(app, name: "store-mac-exhibition")
    let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screen.name = "store-mac-display"
    screen.lifetime = .keepAlways
    add(screen)
  }
}
