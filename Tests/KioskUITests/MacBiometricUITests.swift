import AppKit
import Foundation
import XCTest
import XCUIAutomation

extension KioskWorkflowUITests {
  @MainActor func testBiometricUnlockSuccess() async throws {
    let app = try await biometricFixture(result: "succeeded")
    app.buttons["verify-biometric"].click()
    XCTAssertTrue(app.buttons["start-exhibition"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.secureTextFields["unlock-passcode"].exists)
  }

  @MainActor func testBiometricUnlockFailureKeepsPasswordAvailable() async throws {
    let app = try await biometricFixture(result: "failed")
    app.buttons["verify-biometric"].click()
    XCTAssertTrue(app.staticTexts["biometric-unlock-failed"].waitForExistence(timeout: 10))
    try await unlockWithPassword(app)
  }

  @MainActor func testBiometricUnlockCancellationKeepsPasswordAvailable() async throws {
    let app = try await biometricFixture(result: "cancelled")
    app.buttons["verify-biometric"].click()
    let cancel = app.buttons["cancel-biometric-unlock"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 10))
    cancel.click()
    XCTAssertFalse(app.staticTexts["biometric-unlock-failed"].exists)
    try await unlockWithPassword(app)
  }

  @MainActor private func biometricFixture(result: String) async throws -> XCUIApplication {
    guard ProcessInfo.processInfo.environment["PLINTH_DEDICATED_MAC"] == "1" else {
      throw XCTSkip("GUI tests require an explicitly enabled dedicated Mac.")
    }
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    let app = XCUIApplication()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-biometric-ui-\(UUID())")
    app.launchArguments = ["--preview", "-AppleLanguages", "(en)"]
    app.launchEnvironment = [
      "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
      "PLINTH_TEST_CREDENTIAL_SERVICE": "ai.shiftone.plinth.tests.\(UUID().uuidString)",
      "PLINTH_TEST_BIOMETRIC_RESULT": result,
    ]
    addTeardownBlock {
      await MainActor.run {
        app.terminate()
        server.stop()
        try? FileManager.default.removeItem(at: directory)
      }
    }
    app.launch()
    await configureBiometricExhibition(app, origin: server.origin)
    app.typeKey("k", modifierFlags: [.command, .option, .shift])
    XCTAssertTrue(app.secureTextFields["unlock-passcode"].waitForExistence(timeout: 10))
    let biometric = app.buttons["verify-biometric"]
    XCTAssertTrue(biometric.waitForExistence(timeout: 10))
    XCTAssertEqual(biometric.label, "Unlock with Touch ID")
    return app
  }

  @MainActor private func configureBiometricExhibition(_ app: XCUIApplication, origin: String)
    async
  {
    let start = app.buttons["start-exhibition"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    replaceBiometricFixture(app.textFields["start-url"], with: origin + "/home")
    app.buttons["add-origin"].click()
    replaceBiometricFixture(app.textFields["origin-1"], with: origin)
    app.switches["allow-http"].click()
    let setup = app.secureTextFields["setup-passcode"]
    if !setup.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -800) }
    replaceBiometricFixture(setup, with: "plinth-biometric-ui-passcode")
    app.buttons["save-passcode"].click()
    let toggle = app.switches["biometric-unlock"]
    if !toggle.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500) }
    let available = expectation(
      for: NSPredicate(format: "enabled == true"), evaluatedWith: toggle)
    await fulfillment(of: [available], timeout: 10)
    XCTAssertEqual(toggle.label, "Unlock with Touch ID")
    toggle.click()
    let selected = expectation(
      for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
    await fulfillment(of: [selected], timeout: 10)
    let save = app.buttons["save-profile"]
    let canSave = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    await fulfillment(of: [canSave], timeout: 10)
    save.click()
    let canStart = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
    await fulfillment(of: [canStart], timeout: 10)
    start.click()
    XCTAssertTrue(app.webViews.links["Allowed"].waitForExistence(timeout: 10))
  }

  @MainActor private func unlockWithPassword(_ app: XCUIApplication) async throws {
    let password = app.secureTextFields["unlock-passcode"]
    XCTAssertTrue(password.exists)
    replaceBiometricFixture(password, with: "plinth-biometric-ui-passcode")
    app.buttons["verify-passcode"].click()
    XCTAssertTrue(app.buttons["start-exhibition"].waitForExistence(timeout: 10))
  }

  @MainActor private func replaceBiometricFixture(_ element: XCUIElement, with value: String) {
    element.click()
    element.typeKey("a", modifierFlags: .command)
    element.typeText(value)
  }
}
