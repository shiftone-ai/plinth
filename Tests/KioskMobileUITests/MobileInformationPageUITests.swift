import Foundation
import XCTest
import XCUIAutomation

extension MobileWorkflowUITests {
  @MainActor func testUnavailableInformationPageKeepsAdministrationUsable() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_INFORMATION_PAGE_URL"] =
      "plinth-unavailable://information"
    app.launch()
    defer { app.terminate() }

    try await configureStoreReviewDemo(app)
    for link in ["privacy-policy", "support"] {
      let pageLink = app.descendants(matching: .any)[link]
      reach(pageLink, app: app)
      pageLink.tap()
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
      try await exists(app.buttons["start-exhibition"])
    }

    let idle = app.textFields["idle-seconds"]
    for _ in 0..<4 where !idle.isHittable {
      app.collectionViews.firstMatch.swipeDown()
    }
    XCTAssertTrue(idle.isHittable)
    idle.tap()
    let previous = try XCTUnwrap(idle.value as? String)
    idle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count + 2))
    idle.typeText("5")
    try await value(idle, equals: "5")
    idle.typeText("\n")
    let save = app.buttons["save-profile"]
    try await enabled(save)
    save.tap()
    let start = app.buttons["start-exhibition"]
    try await enabled(start)
    start.tap()
    try await exists(app.webViews.links["NEXT EXHIBIT"], timeout: 20)
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-review-passcode")
    app.buttons["verify-passcode"].tap()
    try await exists(start)
  }
}
