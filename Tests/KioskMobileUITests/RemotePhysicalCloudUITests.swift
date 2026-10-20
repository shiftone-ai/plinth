import XCTest

/// Run on two signed devices with the isolated issue 60 bundle identifier.
class RemotePhysicalCloudUITests: XCTestCase {
  fileprivate let passcode = "plinth-physical-test-passcode"
  fileprivate let service = "ai.shiftone.plinth.tests.issue60remote.physical"

  fileprivate func requirePhysicalRun(_ app: XCUIApplication) throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Run on a signed physical device")
    #else
      guard Bundle.main.bundleIdentifier == "ai.shiftone.plinth.tests.issue60remote.xctrunner"
      else {
        throw XCTSkip("Run with the isolated issue 60 app identifier")
      }
    #endif
  }

  @MainActor fileprivate func reach(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<8 where !element.exists || !element.isHittable {
      app.collectionViews.firstMatch.swipeUp()
    }
  }

  @MainActor fileprivate func replaceURL(
    _ field: XCUIElement, with replacement: String, app: XCUIApplication
  ) {
    reach(field, app: app)
    XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
    field.tap()
    let existing = field.value as? String ?? ""
    field.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2)
        + replacement)
    XCTAssertEqual(field.value as? String, replacement, app.debugDescription)
    field.typeText("\n")
  }

  @MainActor fileprivate func refreshUntil(
    _ element: XCUIElement, using refresh: XCUIElement, attempts: Int = 20,
    timeout: TimeInterval = 5, matches: (XCUIElement) -> Bool
  ) {
    for _ in 0..<attempts {
      if matches(element) { break }
      refresh.tap()
      _ = XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)],
        timeout: timeout)
    }
  }

  @MainActor fileprivate func configure(_ app: XCUIApplication) {
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] = service
    app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
  }

  @MainActor fileprivate func openAdministration(_ app: XCUIApplication) -> Bool {
    let credentialsExisted = app.buttons["request-unlock"].waitForExistence(timeout: 3)
    if credentialsExisted {
      app.buttons["request-unlock"].tap()
      let passcode = app.secureTextFields["unlock-passcode"]
      XCTAssertTrue(passcode.waitForExistence(timeout: 10), app.debugDescription)
      passcode.tap()
      passcode.typeText(self.passcode)
      XCTAssertEqual((passcode.value as? String)?.count, self.passcode.count)
      passcode.typeText("\n")
    }
    XCTAssertTrue(
      app.segmentedControls["management-device-tab"].waitForExistence(timeout: 10),
      app.debugDescription)
    return credentialsExisted
  }
}

final class RemotePhysicalCloudTargetUITests: RemotePhysicalCloudUITests {
  @MainActor func testPublishThisDevice() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    let credentialsExisted = openAdministration(app)

    let setup = app.secureTextFields["setup-passcode"]
    if !credentialsExisted {
      reach(setup, app: app)
      XCTAssertTrue(setup.exists, app.debugDescription)
      setup.tap()
      setup.typeText(passcode)
      XCTAssertEqual((setup.value as? String)?.count, passcode.count)
      setup.typeText("\n")
      let save = app.buttons["save-passcode"]
      XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
      save.tap()
    }

    let remote = app.switches["remote-management-enabled"]
    reach(remote, app: app)
    XCTAssertTrue(remote.exists, app.debugDescription)
    XCTAssertTrue(remote.isEnabled, app.debugDescription)
    if remote.value as? String != "1" { remote.switches.firstMatch.tap() }
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"), object: remote)
        ], timeout: 20), .completed, app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "physical-remote-published"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor func testApprovePhysicalPairing() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    _ = openAdministration(app)

    let createCode = app.buttons["remote-create-code"]
    reach(createCode, app: app)
    XCTAssertTrue(createCode.waitForExistence(timeout: 10), app.debugDescription)
    createCode.tap()
    let code = app.staticTexts["remote-registration-code"]
    XCTAssertTrue(code.waitForExistence(timeout: 10), app.debugDescription)
    let digits = code.label.filter(\.isNumber)
    XCTAssertEqual(digits.count, 8, app.debugDescription)
    print("PLINTH_PHYSICAL_PAIRING_CODE=\(digits)")

    let approval = app.buttons["Approve access"]
    let tabs = app.segmentedControls["management-device-tab"]
    for _ in 0..<10 where !approval.exists {
      reach(approval, app: app)
      if approval.waitForExistence(timeout: 10) { break }
      tabs.buttons["Other devices"].tap()
      let refresh = app.buttons["remote-refresh"]
      if refresh.waitForExistence(timeout: 3) { refresh.tap() }
      tabs.buttons["This device"].tap()
    }
    XCTAssertTrue(approval.exists, app.debugDescription)
    approval.tap()
    let revoke = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Revoke access")
    ).firstMatch
    XCTAssertTrue(revoke.waitForExistence(timeout: 20), app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "physical-pairing-approved"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    _ = XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)],
      timeout: 45)
  }

  @MainActor func testRefreshPhysicalDirectoryWhileWaiting() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    _ = openAdministration(app)
    app.segmentedControls["management-device-tab"].buttons["Other devices"].tap()
    let refresh = app.buttons["remote-refresh"]
    XCTAssertTrue(refresh.waitForExistence(timeout: 10), app.debugDescription)
    for _ in 0..<20 {
      refresh.tap()
      _ = XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)],
        timeout: 8)
    }
  }

  @MainActor func testWaitForPhysicalExhibition() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    _ = openAdministration(app)
    app.segmentedControls["management-device-tab"].buttons["Other devices"].tap()
    let refresh = app.buttons["remote-refresh"]
    XCTAssertTrue(refresh.waitForExistence(timeout: 10), app.debugDescription)
    refreshUntil(app.webViews.firstMatch, using: refresh, timeout: 7) { $0.exists }
    XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20), app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "physical-remote-exhibition-on-target"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor func testPreparePhysicalProfile() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    _ = openAdministration(app)
    let field = app.textFields["start-url"]
    replaceURL(field, with: "https://example.com", app: app)
    let save = app.buttons["save-profile"]
    reach(save, app: app)
    XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(save.isEnabled, app.debugDescription)
    save.tap()
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "physical-profile-saved"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}

final class RemotePhysicalCloudControllerUITests: RemotePhysicalCloudUITests {
  @MainActor func testDiscoverOtherPhysicalDevice() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    _ = openAdministration(app)
    let tabs = app.segmentedControls["management-device-tab"]
    XCTAssertTrue(tabs.waitForExistence(timeout: 10), app.debugDescription)
    tabs.buttons["Other devices"].tap()
    let refresh = app.buttons["remote-refresh"]
    XCTAssertTrue(refresh.waitForExistence(timeout: 10), app.debugDescription)
    refresh.tap()
    let device = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "remote-device-")
    ).firstMatch
    XCTAssertTrue(device.waitForExistence(timeout: 60), app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "physical-remote-discovered"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor func testRequestPhysicalPairingAndStatus() throws {
    continueAfterFailure = false
    guard let code = ProcessInfo.processInfo.environment["PLINTH_PAIRING_CODE"],
      code.count == 8, code.allSatisfy(\.isNumber)
    else { throw XCTSkip("Set PLINTH_PAIRING_CODE in the xctestrun environment") }
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    _ = openAdministration(app)
    let tabs = app.segmentedControls["management-device-tab"]
    tabs.buttons["Other devices"].tap()
    app.buttons["remote-refresh"].tap()
    let device = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "remote-device-")
    ).firstMatch
    XCTAssertTrue(device.waitForExistence(timeout: 30), app.debugDescription)
    device.tap()
    let refreshStatus = app.buttons["remote-refresh-status"]
    if !refreshStatus.exists {
      let input = app.textFields["remote-pairing-input"]
      XCTAssertTrue(input.waitForExistence(timeout: 10), app.debugDescription)
      input.tap()
      input.typeText(code)
      app.buttons["remote-request-access"].tap()
    }
    XCTAssertTrue(refreshStatus.waitForExistence(timeout: 90), app.debugDescription)
    let paired = XCTAttachment(screenshot: app.screenshot())
    paired.name = "physical-pairing-received"
    paired.lifetime = .keepAlways
    add(paired)

    refreshStatus.tap()
    let result = app.staticTexts["remote-command-status"]
    let refreshDirectory = app.buttons["remote-refresh"]
    refreshUntil(result, using: refreshDirectory, attempts: 12) {
      $0.exists && $0.label.contains("Processed on device")
    }
    XCTAssertTrue(
      result.exists && result.label.contains("Processed on device"), app.debugDescription)
    let status = XCTAttachment(screenshot: app.screenshot())
    status.name = "physical-status-result"
    status.lifetime = .keepAlways
    add(status)
  }

  @MainActor func testSavePhysicalStartURL() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    _ = openAdministration(app)
    app.segmentedControls["management-device-tab"].buttons["Other devices"].tap()
    let refresh = app.buttons["remote-refresh"]
    refresh.tap()
    let device = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "remote-device-")
    ).firstMatch
    XCTAssertTrue(device.waitForExistence(timeout: 30), app.debugDescription)
    device.tap()
    let status = app.buttons["remote-refresh-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
    status.tap()
    let edit = app.buttons["remote-edit-start-url"]
    refreshUntil(edit, using: refresh, attempts: 15) { $0.exists }
    reach(edit, app: app)
    XCTAssertTrue(edit.exists, app.debugDescription)
    edit.tap()
    let field = app.textFields["remote-start-url"]
    reach(field, app: app)
    XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
    let existing = field.value as? String ?? ""
    let replacement =
      existing == "https://example.org" ? "https://example.com" : "https://example.org"
    replaceURL(field, with: replacement, app: app)
    let review = app.buttons["Review change"]
    reach(review, app: app)
    XCTAssertTrue(review.isEnabled, app.debugDescription)
    review.tap()
    let save = app.buttons["remote-save-start-url"]
    reach(save, app: app)
    save.tap()
    let result = app.staticTexts["remote-command-status"]
    refreshUntil(result, using: refresh) {
      $0.exists && $0.label.contains("Saved on device")
    }
    XCTAssertTrue(result.exists && result.label.contains("Saved on device"), app.debugDescription)
    let savedURL = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", replacement)
    ).firstMatch
    XCTAssertTrue(savedURL.exists, app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "physical-start-url-saved-on-target"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor func testStartPhysicalExhibition() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    try requirePhysicalRun(app)
    configure(app)
    app.launch()
    _ = openAdministration(app)
    app.segmentedControls["management-device-tab"].buttons["Other devices"].tap()
    let refresh = app.buttons["remote-refresh"]
    refresh.tap()
    let device = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "remote-device-")
    ).firstMatch
    XCTAssertTrue(device.waitForExistence(timeout: 30), app.debugDescription)
    device.tap()
    let status = app.buttons["remote-refresh-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
    status.tap()
    let start = app.buttons["remote-exhibition-start"]
    refreshUntil(start, using: refresh) { $0.exists }
    reach(start, app: app)
    XCTAssertTrue(start.exists, app.debugDescription)
    start.tap()
    let result = app.staticTexts["remote-command-status"]
    refreshUntil(result, using: refresh) {
      $0.exists && $0.label.contains("Page loaded on device")
    }
    XCTAssertTrue(
      result.exists && result.label.contains("Page loaded on device"), app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "physical-exhibition-start-result"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
