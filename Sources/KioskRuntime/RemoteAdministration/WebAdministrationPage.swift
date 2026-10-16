import Foundation
import KioskLocalization

enum WebAdministrationPage {
  static func html(locale: Locale) -> String {
    let label: (String) -> String = { escape(L10n.string($0, locale: locale)) }
    return [
      htmlBeginning(locale: locale, label: label), htmlSummary(label: label),
      htmlEditor(label: label), htmlOutputEditor(label: label), htmlEnding(label: label),
    ].joined(separator: "\n")
  }

  private static func htmlBeginning(locale: Locale, label: (String) -> String) -> String {
    return """
      <!doctype html>
      <html lang="\(escape(locale.language.languageCode?.identifier ?? "en"))">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(label("Web management"))</title>
        <link rel="stylesheet" href="/app.css">
        <script src="/app.js" defer></script>
      </head>
      <body data-failed="\(label("Incorrect administrator password"))"
            data-cooldown="\(label("Try again in 30 seconds"))"
            data-connection="\(label("Could not connect to the device"))"
            data-wait="\(label("Signing in"))"
            data-yes="\(label("Yes"))" data-no="\(label("No"))"
            data-exhibiting="\(label("Exhibiting"))"
            data-administration="\(label("Administrator"))"
            data-entering-kiosk="\(label("Exhibition starting"))"
            data-leaving-kiosk="\(label("Exhibition stopping"))"
            data-unlocking="\(label("Administrator unlock"))"
            data-safe-hold="\(label("Exhibition stopped"))"
            data-paused="\(label("Exhibition paused"))"
            data-bootstrapping="\(label("Starting Plinth"))"
            data-terminating="\(label("Exhibition stopping"))"
            data-allowlist="\(label("Allowlist"))"
            data-denylist="\(label("Blocklist"))"
            data-new-visitor-session="\(label("New browsing session"))"
            data-retain-website-data="\(label("Keep cookies and site data"))"
            data-device="\(label("Device"))"
            data-external-display="\(label("External display"))"
            data-fixed-fullscreen="\(label("Fixed full screen"))"
            data-projection-window="\(label("Window"))"
            data-edit-mode="\(label("Editing is unavailable in the current device state"))"
            data-save-failed="\(label("Could not save settings"))"
            data-rejected="\(label("The device rejected the change"))"
            data-unsaved-draft="\(label("Save or discard changes before restarting"))"
            data-unsupported-displays="\(label("The selected display is unavailable"))"
            data-restart-failed="\(label("Could not restart the exhibition"))"
            data-restart-mode="\(label("Restart is unavailable in the current device state"))"
            data-save-unknown="\(label("Connection lost. The last save may have completed"))"
            data-automatic="\(label("Automatic"))"
            data-disconnected-display="\(label("Disconnected display"))"
            data-domain="\(label("Domain"))"
            data-remove-rule="\(label("Remove rule"))"
            data-invalid-navigation-rules="\(label("Check the domain"))"
            data-home-not-allowed="\(label("The start URL is not allowed by the navigation rules"))"
            data-invalid-idle-timeout="\(label("Enter an idle time greater than zero"))"
            data-invalid-display-mode="\(label("Check the resolution"))"
            data-invalid-revision="\(label("Settings have reached the save limit"))">
      """
  }

  private static func htmlSummary(label: (String) -> String) -> String {
    return """
        <div class="page">
          <header><h1>\(label("Web management"))</h1></header>
          <form id="login-form">
            <label for="password">\(label("Administrator password"))</label>
            <div class="login-row">
              <input id="password" type="password" autocomplete="current-password" required>
              <button type="submit">\(label("Log in"))</button>
            </div>
          </form>
          <p id="message" role="status" aria-live="polite"></p>
          <main id="details" hidden>
            <h2>\(label("Saved settings"))</h2>
            <dl>
              <div><dt>\(label("Status"))</dt><dd id="mode"></dd></div>
              <div><dt>\(label("Start URL"))</dt><dd id="start-url"></dd></div>
              <div><dt>\(label("Navigation"))</dt><dd id="navigation"></dd></div>
              <div><dt>\(label("Domain"))</dt><dd id="domains"></dd></div>
              <div><dt>\(label("Allow HTTP"))</dt><dd id="http"></dd></div>
              <div><dt>\(label("Allow scrolling"))</dt><dd id="scroll"></dd></div>
              <div><dt>\(label("Allow dragging"))</dt><dd id="drag"></dd></div>
              <div><dt>\(label("Seconds until idle return"))</dt><dd id="idle"></dd></div>
              <div><dt>\(label("Site data on return"))</dt><dd id="reset"></dd></div>
              <div id="saved-destination"><dt>\(label("Exhibition destination"))</dt><dd id="destination"></dd></div>
              <div id="saved-resolution"><dt>\(label("Resolution"))</dt><dd id="resolution"></dd></div>
              <div id="saved-rotation"><dt>\(label("Rotation"))</dt><dd id="rotation"></dd></div>
              <div id="saved-mac-output"><dt>\(label("Mac output"))</dt><dd id="mac-output"></dd></div>
              <div id="saved-mac-display"><dt>\(label("Display"))</dt><dd id="mac-display"></dd></div>
            </dl>
      """
  }

  private static func htmlEditor(label: (String) -> String) -> String {
    return """
            <section id="editor" hidden>
              <h2>\(label("Edit"))</h2>
              <form id="settings-form">
                <label for="edit-start-url">\(label("Start URL"))</label>
                <input id="edit-start-url" data-field="startURL" type="url">
                <label for="edit-navigation">\(label("Navigation"))</label>
                <select id="edit-navigation" data-field="navigationMode">
                  <option value="allowlist">\(label("Allowlist"))</option>
                  <option value="denylist">\(label("Blocklist"))</option>
                </select>
                <label>\(label("Domain"))</label>
                <div id="edit-rules"></div>
                <button id="add-rule" type="button" class="secondary">\(label("Add domain"))</button>
                <label class="check"><input id="edit-http" data-field="allowsHTTP" type="checkbox">
                  \(label("Allow HTTP"))</label>
                <label class="check"><input id="edit-scroll" data-field="allowsScroll" type="checkbox">
                  \(label("Allow scrolling"))</label>
                <label class="check"><input id="edit-drag" data-field="allowsDrag" type="checkbox">
                  \(label("Allow dragging"))</label>
                <label for="edit-idle">\(label("Seconds until idle return"))</label>
                <input id="edit-idle" data-field="idleTimeoutText" inputmode="decimal">
                <label for="edit-reset">\(label("Site data on return"))</label>
                <select id="edit-reset" data-field="resetMode">
                  <option value="newVisitorSession">\(label("New browsing session"))</option>
                  <option value="retainWebsiteData">\(label("Keep cookies and site data"))</option>
                </select>
      """
  }

  private static func htmlOutputEditor(label: (String) -> String) -> String {
    return """
                <div id="mac-output-editor" hidden>
                  <h2>\(label("Output"))</h2>
                  <label for="edit-mac-output">\(label("Mode"))</label>
                  <select id="edit-mac-output" data-field="macOutputMode">
                    <option value="fixedFullscreen">\(label("Fixed full screen"))</option>
                    <option value="projectionWindow">\(label("Window"))</option>
                  </select>
                  <div id="mac-display-row">
                    <label for="edit-mac-display">\(label("Display"))</label>
                    <select id="edit-mac-display" data-field="macDisplayID"></select>
                  </div>
                </div>
                <div id="mobile-output-editor" hidden>
                  <h2>\(label("Display destination"))</h2>
                  <label for="edit-destination">\(label("Display"))</label>
                  <select id="edit-destination" data-field="exhibitionDestination">
                    <option value="device">\(label("Device"))</option>
                    <option value="externalDisplay">\(label("External display"))</option>
                  </select>
                  <div id="external-options" hidden>
                    <label for="edit-rotation">\(label("Rotation"))</label>
                    <select id="edit-rotation" data-field="externalDisplayRotation">
                      <option value="0">\(label("Standard (0°)"))</option>
                      <option value="90">\(label("Right 90°"))</option>
                      <option value="180">180°</option>
                      <option value="270">\(label("Left 90°"))</option>
                    </select>
                    <label for="edit-resolution">\(label("Resolution"))</label>
                    <select id="edit-resolution" data-field="externalDisplayMode"></select>
                    <p id="external-preparation" hidden>
                      \(label("Prepare the external display on the device"))</p>
                  </div>
                </div>
                <ul id="validation" aria-live="polite"></ul>
                <button id="save-settings" type="submit">\(label("Save settings"))</button>
                <button id="discard-settings" type="button" class="secondary">
                  \(label("Discard changes"))</button>
              </form>
            </section>
      """
  }

  private static func htmlEnding(label: (String) -> String) -> String {
    return """
            <section id="exhibition-actions" hidden>
              <button id="start-exhibition" type="button">\(label("Start exhibition"))</button>
              <button id="restart-exhibition" type="button">\(label("Restart exhibition"))</button>
              <button id="stop-exhibition" type="button" class="secondary">
                \(label("Stop exhibition"))</button>
              <button id="resume-exhibition" type="button">\(label("Resume exhibition"))</button>
            </section>
          </main>
        </div>
      </body>
      </html>
      """
  }

  private static func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  static var script: String { webAdministrationScript }

  static let style = """
    :root { color-scheme: light dark; font: 16px system-ui, sans-serif; }
    body { margin: 0; background: Canvas; color: CanvasText; }
    .page { max-width: 760px; margin: 0 auto; padding: 28px 20px 64px; }
    h1 { font-size: 1.6rem; margin: 0 0 28px; }
    h2 { font-size: 1.2rem; margin: 36px 0 12px; }
    form { max-width: 440px; }
    label { display: block; margin-bottom: 8px; font-weight: 600; }
    .login-row { display: flex; gap: 10px; }
    input, select { min-width: 0; padding: 12px; font: inherit; border: 1px solid GrayText;
      border-radius: 8px; background: Canvas; color: CanvasText; }
    .login-row input { flex: 1; }
    button { padding: 12px 18px; font: inherit; font-weight: 600; border: 0; border-radius: 8px;
      color: white; background: #245bb5; cursor: pointer; }
    button:disabled { opacity: .5; cursor: default; }
    button.secondary { color: CanvasText; background: color-mix(in srgb, CanvasText 12%, Canvas); }
    button:focus-visible, input:focus-visible, select:focus-visible {
      outline: 3px solid #4087ef; outline-offset: 2px; }
    #message { min-height: 1.5em; color: #a43127; }
    dl { margin: 0; border-top: 1px solid GrayText; }
    dl div { display: grid; grid-template-columns: minmax(150px, 35%) 1fr; gap: 16px;
      padding: 12px 0; border-bottom: 1px solid GrayText; }
    dl div[hidden] { display: none; }
    dt { color: GrayText; } dd { margin: 0; overflow-wrap: anywhere; }
    #settings-form { max-width: 520px; }
    #settings-form > label:not(.check) { margin-top: 20px; }
    #settings-form > input, #settings-form > select { display: block; width: 100%; box-sizing: border-box; }
    #mac-output-editor, #mobile-output-editor { margin-top: 28px; }
    #mac-output-editor h2, #mobile-output-editor h2 { margin-bottom: 16px; }
    #mac-output-editor label, #mobile-output-editor label { margin-top: 18px; }
    #mac-output-editor select, #mobile-output-editor select { width: 100%; }
    #external-preparation { color: #a43127; }
    #settings-form .check { display: flex; align-items: center; gap: 10px; margin: 18px 0; }
    #settings-form .check input { width: 20px; height: 20px; }
    .rule-row { display: flex; gap: 8px; margin-bottom: 8px; }
    .rule-row input { flex: 1; }
    #validation { padding-left: 20px; color: #a43127; }
    #exhibition-actions { margin-top: 32px; }
    @media (max-width: 540px) { dl div { grid-template-columns: 1fr; gap: 4px; } }
    """
}
