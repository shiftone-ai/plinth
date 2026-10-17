import AppKit
import Foundation
import Testing
import WebKit

@testable import KioskRuntime

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_NATIVE_TESTS"] == "1"))
@MainActor
struct WebAdministrationPageInteractionTests {
  @Test(.timeLimit(.minutes(1)))
  func focusedEditorStillNoticesRevokedSession() async throws {
    _ = NSApplication.shared
    let html = WebAdministrationPage.html(locale: Locale(identifier: "en"))
      .replacingOccurrences(of: #"<script src="/app.js" defer></script>"#, with: "")
      .replacingOccurrences(
        of: "</body>",
        with: "<script>\(WebAdministrationPage.script)</script></body>")
    let view = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 844))
    let observer = PageLoadObserver()
    view.navigationDelegate = observer
    try await withCheckedThrowingContinuation { continuation in
      observer.completion = continuation
      view.loadHTMLString(html, baseURL: nil)
    }
    let result =
      try await view.callAsyncJavaScript(
        """
        sessionToken = 'revoked';
        details.hidden = false;
        editor.hidden = false;
        form.hidden = true;
        document.querySelector('#edit-start-url').focus();
        const focused = editor.contains(document.activeElement);
        let requests = 0;
        window.fetch = async () => { requests++; return { status: 401, ok: false }; };
        await poll();
        return [focused, requests, form.hidden, details.hidden, message.textContent];
        """, arguments: [:], in: nil, contentWorld: .page) as? [Any]
    #expect(result?[0] as? Bool == true)
    #expect(result?[1] as? Int == 1)
    #expect(result?[2] as? Bool == false)
    #expect(result?[3] as? Bool == true)
    #expect(result?[4] as? String == "")
  }

  @Test(.timeLimit(.minutes(1)))
  func focusedEditorClearsConnectionErrorAfterRecovery() async throws {
    _ = NSApplication.shared
    let html = WebAdministrationPage.html(locale: Locale(identifier: "en"))
      .replacingOccurrences(of: #"<script src="/app.js" defer></script>"#, with: "")
      .replacingOccurrences(
        of: "</body>",
        with: "<script>\(WebAdministrationPage.script)</script></body>")
    let view = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 844))
    let observer = PageLoadObserver()
    view.navigationDelegate = observer
    try await withCheckedThrowingContinuation { continuation in
      observer.completion = continuation
      view.loadHTMLString(html, baseURL: nil)
    }
    let result =
      try await view.callAsyncJavaScript(
        """
        sessionToken = 'current';
        details.hidden = false;
        editor.hidden = false;
        form.hidden = true;
        const input = document.querySelector('#edit-start-url');
        input.focus();
        input.value = 'https://example.com/unsaved';
        let requests = 0;
        window.fetch = async () => {
          requests++;
          if (requests === 1) throw new TypeError('offline');
          return { status: 200, ok: true,
            json: async () => ({ saving: false, saveFailed: false }) };
        };
        await poll();
        const errorShown = connectionLost && message.textContent === document.body.dataset.connection;
        await poll();
        return [errorShown, connectionLost, message.textContent,
          input.value, editor.contains(document.activeElement)];
        """, arguments: [:], in: nil, contentWorld: .page) as? [Any]
    #expect(result?[0] as? Bool == true)
    #expect(result?[1] as? Bool == false)
    #expect(result?[2] as? String == "")
    #expect(result?[3] as? String == "https://example.com/unsaved")
    #expect(result?[4] as? Bool == true)
  }

  @Test(.timeLimit(.minutes(1)))
  func oldPollCannotClearANewSession() async throws {
    _ = NSApplication.shared
    let html = WebAdministrationPage.html(locale: Locale(identifier: "en"))
      .replacingOccurrences(of: #"<script src="/app.js" defer></script>"#, with: "")
      .replacingOccurrences(
        of: "</body>",
        with: "<script>\(WebAdministrationPage.script)</script></body>")
    let view = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 844))
    let observer = PageLoadObserver()
    view.navigationDelegate = observer
    try await withCheckedThrowingContinuation { continuation in
      observer.completion = continuation
      view.loadHTMLString(html, baseURL: nil)
    }
    let result =
      try await view.callAsyncJavaScript(
        """
        sessionToken = 'old';
        details.hidden = false;
        form.hidden = true;
        let finishOldRequest;
        let failOldRequest;
        let requests = 0;
        window.fetch = async () => new Promise((resolve, reject) => {
          requests++;
          if (requests === 1) finishOldRequest = () => resolve({ status: 401, ok: false });
          else failOldRequest = () => reject(new TypeError('offline'));
        });
        const oldPoll = poll();
        const failingOldPoll = poll();
        sessionToken = 'new';
        finishOldRequest();
        failOldRequest();
        await Promise.all([oldPoll, failingOldPoll]);
        return [sessionToken, form.hidden, details.hidden, message.textContent];
        """, arguments: [:], in: nil, contentWorld: .page) as? [Any]
    #expect(result?[0] as? String == "new")
    #expect(result?[1] as? Bool == true)
    #expect(result?[2] as? Bool == false)
    #expect(result?[3] as? String == "")
  }

  @Test(.timeLimit(.minutes(1)))
  func expiredSessionShowsLoginWithoutAConnectionError() async throws {
    _ = NSApplication.shared
    let html = WebAdministrationPage.html(locale: Locale(identifier: "en"))
      .replacingOccurrences(of: #"<script src="/app.js" defer></script>"#, with: "")
      .replacingOccurrences(
        of: "</body>",
        with: "<script>\(WebAdministrationPage.script)</script></body>")
    let view = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 844))
    let observer = PageLoadObserver()
    view.navigationDelegate = observer
    try await withCheckedThrowingContinuation { continuation in
      observer.completion = continuation
      view.loadHTMLString(html, baseURL: nil)
    }
    let result =
      try await view.callAsyncJavaScript(
        """
        sessionToken = 'expired';
        details.hidden = false;
        form.hidden = true;
        message.textContent = document.body.dataset.connection;
        window.fetch = async () => ({ status: 401, ok: false });
        try { await refresh(); } catch (error) {
          if (error.message !== 'unauthorized') throw error;
        }
        return [form.hidden, details.hidden, message.textContent];
        """, arguments: [:], in: nil, contentWorld: .page) as? [Any]
    #expect(result?[0] as? Bool == false)
    #expect(result?[1] as? Bool == true)
    #expect(result?[2] as? String == "")
  }

  @Test(.timeLimit(.minutes(1)))
  func anotherEditCannotReplaceTheValueBeingTyped() async throws {
    _ = NSApplication.shared
    let html = WebAdministrationPage.html(locale: Locale(identifier: "en"))
      .replacingOccurrences(of: #"<script src="/app.js" defer></script>"#, with: "")
      .replacingOccurrences(
        of: "</body>",
        with: "<script>\(WebAdministrationPage.script)</script></body>")
    let view = WKWebView(frame: .init(x: 0, y: 0, width: 390, height: 844))
    let observer = PageLoadObserver()
    view.navigationDelegate = observer
    try await withCheckedThrowingContinuation { continuation in
      observer.completion = continuation
      view.loadHTMLString(html, baseURL: nil)
    }
    let values =
      try await view.evaluateJavaScript(
        """
        const profile = {
          startURL: 'https://example.com/old',
          navigation: { mode: 'allowlist', rules: [], allowsHTTP: false },
          interaction: { allowsScroll: false, allowsDrag: false },
          idleTimeout: 120, resetMode: 'newVisitorSession',
          externalDisplayRotation: 0, macOutput: { mode: 'fixedFullscreen' }
        };
        const state = {
          mode: 'administration', savedProfile: profile,
          draft: { profile, rules: [], idleTimeoutText: '120' },
          macDisplays: [], mobileOutputAvailable: false,
          canSave: true, hasUnsavedDraft: true
        };
        render(state);
        const input = document.querySelector('#edit-start-url');
        input.focus();
        input.value = 'https://example.com/new';
        render(state);
        const whileFocused = input.value;
        input.blur();
        pendingFields.set('startURL', 1);
        input.value = 'https://example.com/newer';
        render(state);
        [whileFocused, input.value];
        """) as? [String]
    #expect(values == ["https://example.com/new", "https://example.com/newer"])
  }
}

@MainActor
private final class PageLoadObserver: NSObject, WKNavigationDelegate {
  var completion: CheckedContinuation<Void, any Error>?

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    completion?.resume()
    completion = nil
  }

  func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error
  ) {
    completion?.resume(throwing: error)
    completion = nil
  }
}
