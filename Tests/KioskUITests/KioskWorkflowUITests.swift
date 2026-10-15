import AppKit
import Foundation
import XCTest
import XCUIAutomation

final class KioskWorkflowUITests: XCTestCase {
  @MainActor
  func testSetupNavigationIdleRecoveryAndAdministratorUnlock() async throws {
    try await workflow(preview: true)
  }

  @MainActor
  func testNormalPresentationRestoresAfterAdministratorUnlock() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_OS_PRESENTATION_TESTS"] == "1" else {
      throw XCTSkip("OS Presentation tests require explicit enablement on a dedicated Mac.")
    }
    try await workflow(preview: false)
  }

  @MainActor
  func testNativeCursorConfinementAndUnlockRelease() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_OS_PRESENTATION_TESTS"] == "1" else {
      throw XCTSkip("Dedicated OS test")
    }
    try await workflow(preview: false, pointerRegion: true)
  }

  @MainActor
  func testSettingsAndPasscodeSurviveDataProtectionMigration() async throws {
    try await workflow(preview: true, migration: true)
  }

  @MainActor
  func testProjectionWindowKeepsFrameAndCursorFree() async throws {
    try await workflow(preview: false, projectionWindow: true)
  }

  @MainActor
  private func workflow(
    preview: Bool, pointerRegion: Bool = false, migration: Bool = false,
    projectionWindow: Bool = false
  )
    async throws
  {
    guard ProcessInfo.processInfo.environment["PLINTH_DEDICATED_MAC"] == "1" else {
      throw XCTSkip("GUI tests require an explicitly enabled dedicated Mac.")
    }
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-ui-\(UUID())")
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    let server = try FixtureServer()
    try await server.start()
    let app = XCUIApplication()
    addTeardownBlock {
      await MainActor.run {
        // Follow the app's authentication contract before terminating an exhibition fixture.
        if app.state != .notRunning, !app.buttons["start-exhibition"].exists {
          app.typeKey("k", modifierFlags: [.command, .option, .shift])
          let unlock = app.secureTextFields["unlock-passcode"]
          if unlock.waitForExistence(timeout: 3) {
            unlock.click()
            unlock.typeKey("a", modifierFlags: .command)
            unlock.typeText("plinth-ui-staff-passcode")
            app.buttons["verify-passcode"].click()
            _ = app.buttons["start-exhibition"].waitForExistence(timeout: 8)
          }
        }
        app.terminate()
        server.stop()
        // The app owns its Keychain item; the separate UI driver cannot delete it without approval.
        // Each run uses a unique service and storage namespace, preserved for the restart assertion.
        print("ISOLATED_FIXTURE_SERVICE=\(service)")
        try? FileManager.default.removeItem(at: directory)
      }
    }
    app.launchArguments = preview ? ["--preview"] : []
    app.launchEnvironment = [
      "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
      "PLINTH_TEST_CREDENTIAL_SERVICE": service,
      "PLINTH_DEDICATED_MAC": "1",
      "PLINTH_TEST_OS_PRESENTATION": preview ? "0" : "1",
      "PLINTH_TEST_POINTER_REGION": pointerRegion ? "1" : "0",
    ]
    app.launch()
    let start = app.buttons["start-exhibition"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    XCTAssertFalse(start.isEnabled)
    if projectionWindow {
      app.popUpButtons["mac-output-mode"].click()
      app.menuItems["ウィンドウ表示"].click()
      XCTAssertFalse(app.popUpButtons["mac-output-display"].exists)
    }
    replace(app.textFields["start-url"], with: server.origin + "/home")
    app.buttons["add-origin"].click()
    replace(app.textFields["origin-1"], with: server.origin)
    app.switches["allow-http"].click()
    replace(app.textFields["idle-seconds"], with: "5")
    let setup = app.secureTextFields["setup-passcode"]
    if !setup.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -800) }
    replace(setup, with: "plinth-ui-staff-passcode")
    app.buttons["save-passcode"].click()
    let save = app.buttons["save-profile"]
    let configured = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    await fulfillment(of: [configured], timeout: 10)
    save.click()
    let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
    await fulfillment(of: [enabled], timeout: 10)
    let administrativeFrame = try visibleWindowFrame(app)
    attach(app, name: preview ? "preview-administration" : "normal-administration")
    start.click()
    let allowed = app.webViews.links["Allowed"]
    await waitFor(allowed, timeout: 10)
    allowed.click()
    print("MAC_WEB_AFTER_CLICK=\(app.webViews.firstMatch.debugDescription)")
    let visited = app.webViews.descendants(matching: .any).matching(
      NSPredicate(format: "label == '/allowed' OR value == '/allowed'")
    ).firstMatch
    await waitFor(visited)
    // Confirm arrival before checking return; an unchanged home page must not satisfy the idle assertion.
    let home = app.webViews.descendants(matching: .any).matching(
      NSPredicate(format: "label == '/home' OR value == '/home'")
    ).firstMatch
    await waitFor(home, timeout: 10)
    attach(app, name: preview ? "preview-exhibition-after-idle" : "normal-exhibition-after-idle")
    if projectionWindow {
      XCTAssertEqual(try visibleWindowFrame(app), administrativeFrame)
      let web = app.webViews.firstMatch
      web.coordinate(withNormalizedOffset: .zero).withOffset(
        CGVector(dx: 50 - web.frame.minX, dy: 0)
      ).hover()
      XCTAssertEqual(NSEvent.mouseLocation.x, 50, accuracy: 1)
      attach(app, name: "projection-window-cursor-free")
    } else if !preview {
      let screen = try XCTUnwrap(NSScreen.screens.first)
      // A borderless presentation may not expose an AXWindow; validate the visible Web viewport.
      let region = screen.frame.insetBy(dx: pointerRegion ? 150 : 0, dy: pointerRegion ? 150 : 0)
      XCTAssertEqual(app.webViews.firstMatch.frame.size.width, region.size.width)
      XCTAssertEqual(app.webViews.firstMatch.frame.size.height, region.size.height)
      if pointerRegion {
        let outside = app.webViews.firstMatch.coordinate(
          withNormalizedOffset: CGVector(dx: -0.05, dy: 0.5))
        outside.hover()
        let captured = expectation(
          for: NSPredicate { _, _ in
            region.contains(NSEvent.mouseLocation)
              && abs(NSEvent.mouseLocation.x - region.minX) <= 1
          }, evaluatedWith: self)
        await fulfillment(of: [captured], timeout: 3)
        XCTAssertTrue(region.contains(NSEvent.mouseLocation))
        XCTAssertEqual(NSEvent.mouseLocation.x, region.minX, accuracy: 1)
        attach(app, name: "cursor-confined-to-output")
      }
      app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: .command)
      XCTAssertEqual(app.state, .runningForeground)
      app.typeKey("q", modifierFlags: .command)
      app.typeKey("w", modifierFlags: .command)
      // Cmd-Tab can span an idle deadline; let the real HTTP fixture finish the new surface.
      await waitFor(app.webViews.links["Allowed"], timeout: 10)
    }
    app.typeKey("k", modifierFlags: [.command, .option, .shift])
    let unlock = app.secureTextFields["unlock-passcode"]
    await waitFor(unlock)
    replace(unlock, with: "incorrect-passcode")
    app.buttons["verify-passcode"].click()
    await waitFor(app.staticTexts["パスコードが一致しません"], timeout: 10)
    XCTAssertFalse(start.exists)
    app.buttons["cancel-unlock"].click()
    await waitFor(app.webViews.links["Allowed"], timeout: 10)
    app.typeKey("k", modifierFlags: [.command, .option, .shift])
    await waitFor(unlock)
    replace(unlock, with: "plinth-ui-staff-passcode")
    app.buttons["verify-passcode"].click()
    await waitFor(start, timeout: 10)
    attach(
      app,
      name: preview
        ? "preview-administration-after-authentication"
        : "normal-administration-after-authentication")
    if !preview {
      XCTAssertEqual(try visibleWindowFrame(app), administrativeFrame)
      if pointerRegion {
        let button = app.buttons["start-exhibition"]
        button.coordinate(withNormalizedOffset: .zero).withOffset(
          CGVector(dx: 50 - button.frame.minX, dy: 0)
        ).hover()
        let region = screenRegion()
        let free = expectation(
          for: NSPredicate { _, _ in !region.contains(NSEvent.mouseLocation) },
          evaluatedWith: self)
        await fulfillment(of: [free], timeout: 3)
        XCTAssertEqual(NSEvent.mouseLocation.x, 50, accuracy: 1)
      }
    }
    app.terminate()
    if migration { app.launchEnvironment["PLINTH_TEST_KEYCHAIN_MIGRATION"] = "1" }
    app.launch()
    await waitFor(app.webViews.links["Allowed"], timeout: 10)
    if migration {
      app.typeKey("k", modifierFlags: [.command, .option, .shift])
      await waitFor(unlock)
      replace(unlock, with: "plinth-ui-staff-passcode")
      app.buttons["verify-passcode"].click()
      await waitFor(start, timeout: 10)
      replace(app.secureTextFields["setup-passcode"], with: "plinth-ui-replacement-passcode")
      app.buttons["save-passcode"].click()
      let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
      await fulfillment(of: [ready], timeout: 10)
      start.click()
      await waitFor(app.webViews.links["Allowed"], timeout: 10)
      app.typeKey("k", modifierFlags: [.command, .option, .shift])
      await waitFor(unlock)
      replace(unlock, with: "plinth-ui-staff-passcode")
      app.buttons["verify-passcode"].click()
      await waitFor(app.staticTexts["パスコードが一致しません"], timeout: 10)
      replace(unlock, with: "plinth-ui-replacement-passcode")
      app.buttons["verify-passcode"].click()
      await waitFor(start, timeout: 10)
      attach(app, name: "data-protection-migration-settings")
      app.terminate()
      app.launch()
      await waitFor(app.webViews.links["Allowed"], timeout: 10)
      app.typeKey("k", modifierFlags: [.command, .option, .shift])
      await waitFor(unlock)
      replace(unlock, with: "plinth-ui-replacement-passcode")
      app.buttons["verify-passcode"].click()
      await waitFor(start, timeout: 10)
    }
  }

  @MainActor
  private func screenRegion() -> CGRect { NSScreen.screens.first!.frame.insetBy(dx: 150, dy: 150) }

  @MainActor
  private func visibleWindowFrame(_ app: XCUIApplication) throws -> CGRect {
    // Borderless transitions can leave AXWindow.frame infinite even while its controls are visible.
    XCTAssertEqual(app.state, .runningForeground)
    let targetURL = Bundle.main.bundleURL.deletingLastPathComponent()
      .appendingPathComponent("Plinth.app").resolvingSymlinksInPath()
    let targetBundle = try XCTUnwrap(Bundle(url: targetURL))
    let identifier = try XCTUnwrap(targetBundle.bundleIdentifier)
    let target = try XCTUnwrap(
      NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
        $0.bundleURL?.resolvingSymlinksInPath() == targetURL
      })
    let windows = try XCTUnwrap(
      CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]])
    let frames = windows.compactMap { info -> CGRect? in
      guard
        (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.processIdentifier,
        (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
        let bounds = info[kCGWindowBounds as String] as? [String: Any],
        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
        frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width > 0, frame.height > 0
      else { return nil }
      return frame
    }
    return try XCTUnwrap(frames.max { $0.width * $0.height < $1.width * $1.height })
  }

  @MainActor
  private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5) async {
    // Release the main actor so the fixture's real HTTP listener can answer WebKit.
    let ready = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: timeout)
  }

  @MainActor
  private func replace(_ field: XCUIElement, with value: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(value)
  }

  @MainActor
  private func attach(_ app: XCUIApplication, name: String) {
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
