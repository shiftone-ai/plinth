import Foundation
import UIKit
import XCTest
import XCUIAutomation

extension MobileWorkflowUITests {
  @MainActor func testRemoteManagementLanguagesAndVoiceOver() async throws {
    guard #available(iOS 27.0, *) else {
      throw XCTSkip("VoiceOver UI testing requires iOS 27")
    }
    continueAfterFailure = false
    let cases = [
      ("en", "Other devices", "Edit settings"),
      ("ja", "ほかの端末", "設定を編集"),
      ("ko", "다른 기기", "설정 편집"),
      ("zh-Hans", "其他设备", "编辑设置"),
    ]
    for (language, otherDevices, editSettings) in cases {
      let app = XCUIApplication()
      app.launchArguments = ["-AppleLanguages", "(\(language))"]
      app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
        "ai.shiftone.plinth.tests.\(UUID().uuidString)"
      app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
      app.launchEnvironment["PLINTH_TEST_REMOTE_FIXTURE"] = "1"
      app.launch()
      let voiceOver = XCUIDevice.shared.voiceOverService
      defer {
        try? voiceOver.disable()
        app.terminate()
      }
      let tabs = app.segmentedControls["management-device-tab"]
      XCTAssertTrue(tabs.waitForExistence(timeout: 10), app.debugDescription)
      tabs.buttons[otherDevices].tap()
      let device = app.buttons["remote-device-00000000-0000-0000-0000-000000000060"]
      XCTAssertTrue(device.waitForExistence(timeout: 10), app.debugDescription)
      device.tap()
      let edit = app.buttons["remote-edit-start-url"]
      XCTAssertTrue(edit.waitForExistence(timeout: 10), app.debugDescription)
      XCTAssertEqual(edit.label, editSettings)
      attach(app, "remote-management-\(language)")

      try voiceOver.enable()
      XCTAssertTrue(voiceOver.isEnabled)
      app.activate()
      var speech: [String] = []
      for _ in 0..<80 {
        let utterance = try voiceOver.moveForward().utterance
        speech.append(utterance)
        if speech.contains(where: { $0.contains(editSettings) }) { break }
      }
      try voiceOver.disable()
      XCTAssertTrue(
        speech.contains { $0.contains(editSettings) },
        speech.joined(separator: " | "))
    }
  }

  @MainActor func testRemoteStartURLEditShowsTheTargetSaveResult() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
    app.launchEnvironment["PLINTH_TEST_REMOTE_FIXTURE"] = "1"
    app.launch()
    defer { app.terminate() }

    let tabs = app.segmentedControls["management-device-tab"]
    XCTAssertTrue(tabs.waitForExistence(timeout: 10), app.debugDescription)
    tabs.buttons["Other devices"].tap()
    let device = app.buttons["remote-device-00000000-0000-0000-0000-000000000060"]
    XCTAssertTrue(device.waitForExistence(timeout: 10), app.debugDescription)
    attach(app, "remote-devices-list")
    device.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    let edit = app.buttons["remote-edit-start-url"]
    XCTAssertTrue(edit.waitForExistence(timeout: 10), app.debugDescription)
    reach(edit, app: app)
    edit.tap()

    let field = app.textFields["remote-start-url"]
    XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
    field.tap()
    field.typeText(
      String(
        repeating: XCUIKeyboardKey.delete.rawValue,
        count: "https://example.com/home".count + 2) + "https://example.com/next")
    let review = app.buttons["Review change"]
    reach(review, app: app)
    XCTAssertTrue(review.isEnabled)
    review.tap()
    let save = app.buttons["remote-save-start-url"]
    reach(save, app: app)
    XCTAssertTrue(app.staticTexts["Gallery iPad"].exists)
    save.tap()
    let result = app.staticTexts["remote-command-status"]
    waitForStatus(result, containing: "Accepted by device")
    waitForStatus(result, containing: "Saved on device")
    let savedURL = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "https://example.com/next")
    ).firstMatch
    XCTAssertTrue(savedURL.exists, app.debugDescription)
    attach(app, "remote-start-url-saved-on-target")
  }

  @MainActor func testOtherDevicesTabWithoutLocalExhibitionSetup() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
    app.launch()
    defer { app.terminate() }

    let tabs = app.segmentedControls["management-device-tab"]
    XCTAssertTrue(tabs.waitForExistence(timeout: 10), app.debugDescription)
    tabs.buttons["Other devices"].tap()
    XCTAssertTrue(
      app.collectionViews["remote-devices"].waitForExistence(timeout: 10),
      app.debugDescription)
    XCTAssertTrue(app.buttons["remote-refresh"].exists)
    attach(app, "other-devices-without-local-setup")

    tabs.buttons["This device"].tap()
    XCTAssertTrue(app.textFields["start-url"].waitForExistence(timeout: 10))
  }

  @MainActor private func waitForStatus(_ element: XCUIElement, containing text: String) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", text),
      object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
  }
}
