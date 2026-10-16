import Foundation
import UIKit
import XCTest
import XCUIAutomation

extension MobileWorkflowUITests {
  @MainActor func testSimulatedBiometricSuccess() async throws {
    let app = try await configuredBiometricPort(result: "succeeded")
    app.buttons["verify-biometric"].tap()
    try await exists(app.buttons["start-exhibition"])
    XCTAssertFalse(app.secureTextFields["unlock-passcode"].exists)
    attach(app, "biometric-unlock-success")
  }

  @MainActor func testSimulatedBiometricFailureKeepsPasswordAvailable() async throws {
    let app = try await configuredBiometricPort(result: "failed")
    app.buttons["verify-biometric"].tap()
    try await exists(app.staticTexts["biometric-unlock-failed"])
    XCTAssertTrue(app.secureTextFields["unlock-passcode"].exists)
    try await enterAdministrationWithPassword(app)
    attach(app, "biometric-unlock-failed-password-succeeded")
  }

  @MainActor func testSimulatedBiometricCancellationKeepsPasswordAvailable() async throws {
    let app = try await configuredBiometricPort(result: "cancelled")
    app.buttons["verify-biometric"].tap()
    let cancel = app.buttons["cancel-biometric-unlock"]
    try await exists(cancel)
    cancel.tap()
    XCTAssertFalse(app.staticTexts["biometric-unlock-failed"].exists)
    XCTAssertTrue(app.secureTextFields["unlock-passcode"].exists)
    try await enterAdministrationWithPassword(app)
    attach(app, "biometric-unlock-cancelled-password-succeeded")
  }

  @MainActor func testSimulatedBiometricEnrollmentChangeDisablesSetting() async throws {
    let app = try await configuredBiometricPort(result: "enrollmentChanged")
    app.buttons["verify-biometric"].tap()
    try await exists(app.staticTexts["biometric-unlock-failed"])
    XCTAssertFalse(app.buttons["verify-biometric"].exists)
    try await enterAdministrationWithPassword(app)
    let toggle = app.switches["biometric-unlock"]
    reach(toggle, app: app)
    XCTAssertEqual(toggle.value as? String, "0")
    try await exists(app.staticTexts["biometric-enrollment-changed"])
    attach(app, "biometric-enrollment-changed")
  }

  @MainActor private func configuredBiometricPort(result: String) async throws -> XCUIApplication {
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_BIOMETRIC_RESULT"] = result
    let kind = UIDevice.current.userInterfaceIdiom == .phone ? "faceID" : "touchID"
    app.launchEnvironment["PLINTH_TEST_BIOMETRIC_KIND"] = kind
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await configureExhibition(
      app, origin: server.origin, language: "biometric-\(result)",
      controlTitles: (save: "Save settings", start: "Start exhibition"))
    try await enterAdministrationWithPassword(app)
    let toggle = app.switches["biometric-unlock"]
    reach(toggle, app: app)
    try await enabled(toggle)
    XCTAssertEqual(toggle.label, kind == "faceID" ? "Unlock with Face ID" : "Unlock with Touch ID")
    toggle.switches.firstMatch.tap()
    let selected = expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
    await fulfillment(of: [selected], timeout: 10)
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.links["Allowed"])
    app.buttons["request-unlock"].tap()
    try await exists(app.buttons["verify-biometric"])
    return app
  }

  @MainActor func testFaceIDAuthenticationPromptUsesFaceIDLabel() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_BIOMETRIC_SIMULATOR_TEST"] == "1" else {
      throw XCTSkip("Requires enrolled Face ID in a Simulator")
    }
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    let setup = app.secureTextFields["setup-passcode"]
    reach(setup, app: app)
    setup.tap()
    setup.typeText("plinth-faceid-password")
    try await secureValue(setup, count: "plinth-faceid-password".count)
    app.keyboards.buttons["Done"].tap()
    let save = app.buttons["save-passcode"]
    reach(save, app: app)
    save.tap()
    let toggle = app.switches["biometric-unlock"]
    reach(toggle, app: app)
    try await enabled(toggle)
    XCTAssertEqual(toggle.label, "Unlock with Face ID")
    toggle.switches.firstMatch.tap()
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let faceID = system.staticTexts["Face ID"]
    XCTAssertTrue(faceID.waitForExistence(timeout: 10), system.debugDescription)
    attach(system, "faceid-authentication-en")
  }

  @MainActor func testBiometricSettingRequiresAdministratorPassword() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    let toggle = app.switches["biometric-unlock"]
    reach(toggle, app: app)
    try await exists(toggle)
    XCTAssertFalse(toggle.isEnabled)
    let reason = app.staticTexts["biometric-unavailable"]
    if reason.exists { XCTAssertFalse(reason.label.isEmpty) }
    attach(app, "biometric-before-password")
    let setup = app.secureTextFields["setup-passcode"]
    reach(setup, app: app)
    setup.tap()
    setup.typeText("plinth-biometric-password")
    try await secureValue(setup, count: "plinth-biometric-password".count)
    setup.typeText("\n")
    let save = app.buttons["save-passcode"]
    reach(save, app: app)
    save.tap()
    let updated = expectation(
      for: NSPredicate(format: "label == %@", "Change administrator password"),
      evaluatedWith: save)
    await fulfillment(of: [updated], timeout: 10)
    XCTAssertEqual(app.buttons["save-passcode"].label, "Change administrator password")
    XCTAssertFalse(toggle.isEnabled)
    attach(app, "biometric-unavailable-after-password")
  }

  @MainActor func testFaceIDEnrollmentChangeDisablesSetting() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_BIOMETRIC_SIMULATOR_TEST"] == "1" else {
      throw XCTSkip("Requires enrolled Face ID and a matching-response driver")
    }
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await configureExhibition(
      app, origin: server.origin, language: "faceid-setup",
      controlTitles: (save: "Save settings", start: "Start exhibition"))
    try await enterAdministrationWithPassword(app)
    let toggle = app.switches["biometric-unlock"]
    reach(toggle, app: app)
    try await enabled(toggle)
    toggle.switches.firstMatch.tap()
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCTAssertTrue(system.staticTexts["Face ID"].waitForExistence(timeout: 10))
    print("BIOMETRIC_ENABLE_PROMPT_READY")
    let enabledSetting = expectation(
      for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
    await fulfillment(of: [enabledSetting], timeout: 30)
    print("BIOMETRIC_ENROLLMENT_CHANGE_READY")
    try await Task.sleep(for: .seconds(3))
    app.terminate()
    app.launch()
    try await exists(app.webViews.links["Allowed"])
    try await enterAdministrationWithPassword(app)
    reach(toggle, app: app)
    let unavailable = app.staticTexts["biometric-unavailable"]
    try await exists(unavailable)
    XCTAssertEqual(toggle.value as? String, "0")
    XCTAssertEqual(unavailable.label, "Set up Face ID or Touch ID on this device first")
    print("BIOMETRIC_REENROLL_READY")
    try await Task.sleep(for: .seconds(3))
    app.terminate()
    app.launch()
    try await exists(app.webViews.links["Allowed"])
    try await enterAdministrationWithPassword(app)
    reach(toggle, app: app)
    try await enabled(toggle)
    XCTAssertEqual(toggle.value as? String, "0")
    XCTAssertEqual(toggle.label, "Unlock with Face ID")
    attach(app, "faceid-enrollment-changed")
  }

  @MainActor func testBiometricSettingSurvivesRelaunch() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_BIOMETRIC_SIMULATOR_TEST"] == "1" else {
      throw XCTSkip("Requires enrolled Simulator biometrics and a matching-response driver")
    }
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] = service
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await configureExhibition(
      app, origin: server.origin, language: "biometric-setup",
      controlTitles: (save: "Save settings", start: "Start exhibition"))
    try await enterAdministrationWithPassword(app)
    let toggle = app.switches["biometric-unlock"]
    reach(toggle, app: app)
    try await enabled(toggle)
    XCTAssertTrue(["Unlock with Face ID", "Unlock with Touch ID"].contains(toggle.label))
    toggle.switches.firstMatch.tap()
    try await exists(app.buttons["cancel-biometric-change"])
    print("BIOMETRIC_ENABLE_PROMPT_READY")
    let enabledSetting = expectation(
      for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
    await fulfillment(of: [enabledSetting], timeout: 30)
    attach(app, "biometric-enabled")
    app.terminate()
    app.launch()
    try await enterAdministrationWithPassword(app)
    reach(toggle, app: app)
    XCTAssertEqual(toggle.value as? String, "1")
    toggle.switches.firstMatch.tap()
    let disabledSetting = expectation(
      for: NSPredicate(format: "value == %@", "0"), evaluatedWith: toggle)
    await fulfillment(of: [disabledSetting], timeout: 10)
    app.terminate()
    app.launch()
    try await enterAdministrationWithPassword(app)
    reach(toggle, app: app)
    XCTAssertEqual(toggle.value as? String, "0")
    try await cancelBiometricAuthentication(app, toggle: toggle)
  }

  @MainActor private func cancelBiometricAuthentication(
    _ app: XCUIApplication, toggle: XCUIElement
  ) async throws {
    toggle.switches.firstMatch.tap()
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let cancel = system.buttons[
      "com.apple.localauthentication.ax.authentication.button.cancel"
    ].firstMatch
    try await exists(cancel)
    cancel.tap()
    let completed = expectation(
      for: NSPredicate(format: "exists == false"),
      evaluatedWith: app.buttons["cancel-biometric-change"])
    await fulfillment(of: [completed], timeout: 10)
    XCTAssertEqual(toggle.value as? String, "0")
    XCTAssertFalse(app.staticTexts["biometric-change-failed"].exists)
    reach(toggle, app: app)
    attach(app, "biometric-cancelled")
  }

  @MainActor private func enterAdministrationWithPassword(_ app: XCUIApplication) async throws {
    let request = app.buttons["request-unlock"]
    if request.exists { request.tap() }
    let password = app.secureTextFields["unlock-passcode"]
    try await exists(password)
    password.tap()
    password.typeText("plinth-localization-passcode")
    app.buttons["verify-passcode"].tap()
    try await exists(app.buttons["start-exhibition"])
  }
}
