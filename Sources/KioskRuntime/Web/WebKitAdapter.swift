import KioskCore
import WebKit

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor
public final class WebKitAdapter: NSObject, WebSurfacePort, WKNavigationDelegate, WKUIDelegate {
  #if os(macOS)
    public let host = NSView()
  #else
    public let host = UIView()
  #endif
  public var send: (@MainActor (Event) -> Reply?)?
  public private(set) var webView: WKWebView?
  private var dataStore: WKWebsiteDataStore?
  private var generation: UInt64 = 0
  private var loadToken: OperationToken?
  private(set) var navigation: WKNavigation?
  private let navigationTokens = NSMapTable<WKNavigation, NavigationToken>(
    keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
  private var decisions = DecisionRegistry()
  private let externalInput = ExternalInputGate()

  public func create(
    _ token: OperationToken, mode: ResetMode, interaction: InteractionPolicy = .init()
  ) {
    releaseSurface()
    generation = token.webGeneration ?? 0
    if mode == .newVisitorSession || dataStore == nil { dataStore = .nonPersistent() }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore ?? .nonPersistent()
    configuration.preferences.isElementFullscreenEnabled = false
    configuration.mediaTypesRequiringUserActionForPlayback = .audio
    #if os(iOS)
      configuration.allowsInlineMediaPlayback = true
    #endif
    let view = ExhibitionWebView(frame: host.bounds, configuration: configuration)
    #if os(macOS)
      view.autoresizingMask = [.width, .height]
    #else
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    #endif
    #if os(macOS)
      view.allowsMagnification = false
    #else
      view.allowsLinkPreview = false
      view.scrollView.isScrollEnabled = interaction.allowsScroll
      view.scrollView.pinchGestureRecognizer?.isEnabled = false
      view.scrollView.bounces = false
      view.scrollView.contentInsetAdjustmentBehavior = .never
      if #available(iOS 26.0, *) {
        // Exhibition content has no native bars for the system's edge effects to blend beneath.
        for edge in [
          view.scrollView.topEdgeEffect, view.scrollView.bottomEdgeEffect,
          view.scrollView.leftEdgeEffect, view.scrollView.rightEdgeEffect,
        ] {
          edge.isHidden = true
        }
      }
    #endif
    view.allowsBackForwardNavigationGestures = false
    view.navigationDelegate = self
    view.uiDelegate = self
    view.isInspectable = false
    #if os(iOS)
      view.accessibilityIdentifier = "exhibition-web-\(generation)"
    #endif
    webView = view
    decisions = DecisionRegistry()
    host.addSubview(view)
    #if DEBUG && os(iOS)
      print(
        "WEB_CREATED generation=\(generation) host=\(host.bounds) web=\(view.bounds) attached=\(host.window != nil)"
      )
    #endif
  }

  public func load(_ address: String, token: OperationToken) -> Bool {
    guard token.webGeneration == generation, let view = webView, let url = URL(string: address)
    else { return false }
    loadToken = token
    #if DEBUG && os(iOS)
      print(
        "WEB_LOAD generation=\(generation) host=\(host.bounds) web=\(view.bounds) attached=\(host.window != nil)"
      )
    #endif
    navigation = view.load(URLRequest(url: url))
    if let navigation { navigationTokens.setObject(NavigationToken(token), forKey: navigation) }
    return navigation != nil
  }

  public func releaseSurface() {
    // Invalidate before stopping WebKit; stopLoading can synchronously trigger callbacks.
    loadToken = nil
    externalInput.reset()
    navigation = nil
    navigationTokens.removeAllObjects()
    decisions.close()
    let previous = webView
    webView = nil
    previous?.navigationDelegate = nil
    previous?.uiDelegate = nil
    previous?.stopLoading()
    previous?.removeFromSuperview()
  }

  public func control(_ control: ExternalWebControl, token: OperationToken) async {
    let stream: AsyncStream<ExternalInputGate.Permit>
    do { stream = try externalInput.enqueue(control) } catch {
      _ = send?(.externalWebControlDeliveryFailed(token))
      return
    }
    for await permit in stream {
      defer { externalInput.finish(permit) }
      await deliverExternalControl(permit.control, token: token)
      break
    }
  }

  private func deliverExternalControl(_ control: ExternalWebControl, token: OperationToken) async {
    guard control.isValid, token.webGeneration == generation, let view = webView,
      send?(.externalWebControlExecutionRequested(token)) == .accepted, !Task.isCancelled
    else { return }
    let arguments: [String: Any]
    switch control {
    case .move(let point): arguments = ["action": "move", "x": point.x, "y": point.y]
    case .activate(let point): arguments = ["action": "activate", "x": point.x, "y": point.y]
    case .press(let point): arguments = ["action": "press", "x": point.x, "y": point.y]
    case .release(let point): arguments = ["action": "release", "x": point.x, "y": point.y]
    case .cancelPress: arguments = ["action": "cancel", "x": 0, "y": 0]
    case .scroll(let dx, let dy):
      arguments = ["action": "scroll", "x": 0, "y": 0, "dx": dx, "dy": dy]
    }
    // Standard DOM activation keeps navigation in this WebView's policy delegate.
    // Event isTrusted stays false. Playback activation is verified against the installed WebKit.
    _ = try? await view.callAsyncJavaScript(
      ExternalWebInputScript.control, arguments: arguments, in: nil, contentWorld: .page)
  }

  public func stop() {
    releaseSurface()
    dataStore = nil
    send = nil
  }

  private func decide(
    view: WKWebView, address: String?, mainFrame: Bool, newWindow: Bool, isGET: Bool,
    supportedContent: Bool = true
  ) -> NavigationDecision {
    guard view === webView, let address,
      case .navigation(let decision) = send?(
        .navigationRequested(
          url: address, generation: generation, mainFrame: mainFrame,
          newWindow: newWindow, isGET: isGET, supportedContent: supportedContent))
    else { return .cancel(.staleOperation) }
    return decision
  }

  private func restricted(_ capability: WebCapability) {
    _ = send?(.webCapabilityRequested(capability, generation: generation))
  }

  public func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    if action.shouldPerformDownload { restricted(.download) }
    let id = decisions.register(generation: generation) {
      decisionHandler($0 == .allow ? .allow : .cancel)
    }
    let decision = decide(
      view: webView, address: action.request.url?.absoluteString,
      mainFrame: action.targetFrame?.isMainFrame ?? true,
      newWindow: action.targetFrame == nil, isGET: action.request.httpMethod == "GET",
      supportedContent: !action.shouldPerformDownload)
    decisions.resolve(id, generation: generation, decision: decision)
  }

  public func webView(
    _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
    decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
  ) {
    if !response.canShowMIMEType { restricted(.download) }
    let id = decisions.register(generation: generation) {
      decisionHandler($0 == .allow ? .allow : .cancel)
    }
    let decision = decide(
      view: webView, address: response.response.url?.absoluteString,
      mainFrame: response.isForMainFrame, newWindow: false, isGET: true,
      supportedContent: response.canShowMIMEType)
    decisions.resolve(id, generation: generation, decision: decision)
  }

  public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)
  {
    guard webView === self.webView, let navigation, let token = loadToken else { return }
    if let issued = navigationTokens.object(forKey: navigation), issued.token != token { return }
    navigationTokens.setObject(NavigationToken(token), forKey: navigation)
    self.navigation = navigation
    _ = send?(.webNavigationBegan(token))
  }

  public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    guard current(webView, navigation), let token = loadToken, let url = webView.url else { return }
    _ = send?(.webCommitted(token, url: url.absoluteString))
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard current(webView, navigation), let token = loadToken else { return }
    _ = send?(.webFinished(token))
    #if DEBUG && os(iOS)
      print(
        "WEB_FINISHED generation=\(generation) host=\(host.bounds) web=\(webView.bounds) attached=\(host.window != nil)"
      )
      webView.evaluateJavaScript(
        """
        JSON.stringify({width:innerWidth,height:innerHeight,visibility:document.visibilityState,
        visualWidth:visualViewport?.width,visualHeight:visualViewport?.height,
        documentHeight:document.documentElement.scrollHeight,
        media:[...document.querySelectorAll('video')].map(v=>({paused:v.paused,ended:v.ended,
          readyState:v.readyState,currentTime:v.currentTime,duration:v.duration,
          error:v.error?.code,muted:v.muted,inline:v.playsInline})),
        elements:[[innerWidth/2,innerHeight/2],[innerWidth/2,innerHeight*.9]].map(([x,y])=>{
          let e=document.elementFromPoint(x,y);if(!e)return null;
          let r=e.getBoundingClientRect(),s=getComputedStyle(e);
          return {tag:e.tagName,id:e.id,cls:e.className,x:r.x,y:r.y,width:r.width,height:r.height,
            position:s.position,background:s.backgroundColor,zIndex:s.zIndex};
        })})
        """
      ) { [weak self, weak webView] result, _ in
        guard let self, let webView, webView === self.webView, self.loadToken == token else {
          return
        }
        if let value = result as? String { print("WEB_VIEWPORT \(value)") }
      }
    #endif
  }

  public func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) { failed(webView, navigation, error) }

  public func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error
  ) { failed(webView, navigation, error) }

  private func current(_ view: WKWebView, _ navigation: WKNavigation?) -> Bool {
    guard view === webView, let navigation, navigation === self.navigation else { return false }
    return navigationTokens.object(forKey: navigation)?.token == loadToken
  }

  private func failed(_ view: WKWebView, _ navigation: WKNavigation?, _ error: any Error) {
    guard current(view, navigation), let token = loadToken else { return }
    let error = error as NSError
    // Policy cancellation and replacement are expected; they are not network failures.
    if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
    let failure: WebFailure
    if error.domain == NSURLErrorDomain && (-1206 ... -1200).contains(error.code) {
      failure = .tls
    } else if error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
      failure = .timeout
    } else {
      failure = .network
    }
    _ = send?(.webFailed(token, failure))
  }

  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    guard webView === self.webView else { return }
    _ = send?(.webProcessTerminated(generation: generation))
  }

  public func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for action: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    // The action policy already asks the Mediator to replace a permitted GET in this surface.
    // Never create a second WebView here.
    nil
  }

  public func webView(
    _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void
  ) {
    restricted(.alert)
    completionHandler()
  }

  public func webView(
    _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void
  ) {
    restricted(.confirm)
    completionHandler(false)
  }

  public func webView(
    _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void
  ) {
    restricted(.prompt)
    completionHandler(nil)
  }

  public func webView(
    _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void
  ) {
    restricted(.fileSelection)
    completionHandler(nil)
  }

  public func webView(
    _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
  ) {
    restricted(.mediaCapture)
    decisionHandler(.deny)
  }

  @available(macOS 27.0, iOS 27.0, *)
  public func webView(
    _ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
  ) {
    restricted(.geolocation)
    decisionHandler(.deny)
  }

  public func webView(
    _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    // System trust validation remains enabled; HTTP authentication never opens a credential dialog.
    if challenge.protectionSpace.authenticationMethod != NSURLAuthenticationMethodServerTrust {
      restricted(.httpAuthentication)
    }
    completionHandler(
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
  }
}

@MainActor
private final class NavigationToken: NSObject {
  let token: OperationToken
  init(_ token: OperationToken) { self.token = token }
}
