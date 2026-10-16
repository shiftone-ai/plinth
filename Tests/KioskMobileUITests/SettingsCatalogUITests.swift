import Foundation
import XCTest
import XCUIAutomation

final class SettingsCatalogUITests: XCTestCase {
  @MainActor func testExportToLocalFiles() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_TEST_FILE_PROVIDER_UI"] == "1" else {
      throw XCTSkip(
        "Run with TEST_RUNNER_PLINTH_TEST_FILE_PROVIDER_UI=1 on a dedicated iPad Simulator")
    }
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.catalog.file.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await registerSavedSettings(in: app)
    let passphrase = app.secureTextFields["catalog-passphrase"]
    reach(passphrase, in: app)
    passphrase.tap()
    passphrase.typeText("abcdefghijklmnop")
    try await secureCount(passphrase, count: 16)
    let confirm = app.secureTextFields["catalog-confirm-passphrase"]
    reach(confirm, in: app)
    confirm.tap()
    confirm.typeText("abcdefghijklmnop")
    try await secureCount(confirm, count: 16)
    let export = app.buttons["catalog-export-all"]
    reach(export, in: app)
    try await enabled(export)
    export.tap()
    let files = app.staticTexts["On My iPad"]
    try await exists(files)
    files.tap()
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "catalog-files-before-save"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let savePoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.055))
    savePoint.tap()
    let after = XCTAttachment(screenshot: app.screenshot())
    after.name = "catalog-files-after-save"
    after.lifetime = .keepAlways
    add(after)
    XCTAssertFalse(files.exists)
    XCTAssertTrue(app.buttons["catalog-import-file"].waitForExistence(timeout: 10))
  }

  @MainActor func testSavedEntrySurvivesRestartAndLoadsIntoEditor() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.catalog.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await registerSavedSettings(in: app)
    app.terminate()
    app.launch()
    try await unlockIfNeeded(in: app)
    try await loadSavedEntry(in: app)
  }

  @MainActor private func registerSavedSettings(in app: XCUIApplication) async throws {
    let url = app.textFields["start-url"]
    reach(url, in: app)
    url.tap()
    url.typeText("https://example.com/home\n")
    let save = app.buttons["save-profile"]
    reach(save, in: app)
    try await enabled(save)
    save.tap()
    let setup = app.secureTextFields["setup-passcode"]
    reach(setup, in: app)
    setup.tap()
    setup.typeText("plinth-mobile-passcode")
    try await secureCount(setup, count: "plinth-mobile-passcode".count)
    setup.typeText("\n")
    let savePasscode = app.buttons["save-passcode"]
    reach(savePasscode, in: app)
    try await enabled(savePasscode)
    savePasscode.tap()
    let name = app.textFields["catalog-name"]
    reach(name, in: app)
    name.tap()
    name.typeText("A\n")
    let register = app.buttons["catalog-register"]
    try await enabled(register)
    register.tap()
  }

  @MainActor private func unlockIfNeeded(in app: XCUIApplication) async throws {
    guard app.buttons["request-unlock"].exists else { return }
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-mobile-passcode")
    try await secureCount(unlock, count: "plinth-mobile-passcode".count)
    app.buttons["verify-passcode"].tap()
  }

  @MainActor private func loadSavedEntry(in app: XCUIApplication) async throws {
    let entry = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
    ).firstMatch
    reach(entry, in: app)
    XCTAssertTrue(entry.label.contains("A"))
    entry.tap()
    try await exists(app.staticTexts["Contents"])
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "catalog-entry-detail"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let apply = app.buttons["catalog-apply"]
    for _ in 0..<6 where !apply.exists || !apply.isHittable {
      app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeUp()
    }
    XCTAssertTrue(apply.isHittable)
    apply.tap()
    let restoredURL = app.textFields["start-url"]
    for _ in 0..<8 where !restoredURL.exists || !restoredURL.isHittable {
      app.collectionViews.firstMatch.swipeDown()
    }
    XCTAssertTrue(restoredURL.isHittable)
    XCTAssertEqual(restoredURL.value as? String, "https://example.com/home")
  }

  @MainActor private func reach(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<5 where !element.exists || !element.isHittable {
      app.collectionViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(element.isHittable)
  }

  @MainActor private func exists(_ element: XCUIElement) async throws {
    let ready = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 10)
    _ = try XCTUnwrap(element.exists ? element : nil)
  }

  @MainActor private func enabled(_ element: XCUIElement) async throws {
    let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 15)
    _ = try XCTUnwrap(element.isEnabled ? element : nil)
  }

  @MainActor private func secureCount(_ element: XCUIElement, count: Int) async throws {
    let ready = expectation(
      for: NSPredicate(format: "value.length == %d", count), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 5)
    XCTAssertEqual((element.value as? String)?.count, count)
  }
}
