import XCTest

/// Run on the controller while the approved target uses a different network.
final class RemotePhysicalCloudCrossNetworkUITests: RemotePhysicalCloudUITests {
  @MainActor func testRestartPhysicalExhibition() throws {
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
    let restart = app.buttons["remote-exhibition-restart"]
    refreshUntil(restart, using: refresh, attempts: 15) { $0.exists }
    reach(restart, app: app)
    XCTAssertTrue(restart.exists, app.debugDescription)
    restart.tap()
    let confirm = app.sheets.buttons["Restart exhibition"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
    confirm.tap()
    let result = app.staticTexts["remote-command-status"]
    refreshUntil(result, using: refresh, attempts: 25) {
      $0.exists && $0.label.contains("Page loaded on device")
    }
    XCTAssertTrue(
      result.exists && result.label.contains("Page loaded on device"), app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "physical-remote-restart-loaded"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
