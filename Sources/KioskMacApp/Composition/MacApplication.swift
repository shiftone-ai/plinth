import AppKit
import KioskCore
import KioskLocalization
import KioskPresentation
import KioskRuntime
import KioskUI
import SwiftUI

@MainActor
public final class MacApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var window: NSWindow?
  private var runtime: RootRuntime?
  private var input: NativeInputAdapter?
  private var lifecycle: LifecycleAdapter?
  private var executor: EffectExecutor?
  private var webServer: WebAdministrationServer?
  private let preview: Bool
  private let exhibitionInset: Double
  private let profileFileURL: URL?
  private let credentialService: String
  private let credentialKeychain: CredentialStore.Keychain
  private let legacyCredentialService: String?
  private let storageNamespace: String
  private let language: LanguagePreference

  public init(
    preview: Bool = false, profileFileURL: URL? = nil, exhibitionInset: Double = 0,
    credentialService: String = "ai.shiftone.plinth", storageNamespace: String = "Plinth",
    credentialKeychain: CredentialStore.Keychain = .platformDefault,
    legacyCredentialService: String? = nil
  ) {
    self.preview = preview
    self.exhibitionInset = exhibitionInset
    self.profileFileURL = profileFileURL
    self.credentialService = credentialService
    self.credentialKeychain = credentialKeychain
    self.legacyCredentialService = legacyCredentialService
    self.storageNamespace = storageNamespace
    self.language = LanguagePreference(storageNamespace: storageNamespace)
  }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    let window = makeWindow()
    let clock = MonotonicClock()
    let displays = DisplayAdapter(exhibitionInset: exhibitionInset)
    let web = WebKitAdapter()
    let presentation = PresentationAdapter(
      window: window, preview: preview, displays: displays,
      unlockTitle: { [language] in
        L10n.string("Administrator unlock", locale: language.locale)
      })
    let webServer = WebAdministrationServer()
    let port = makeEffectPort(
      web: web, presentation: presentation, clock: clock, displays: displays,
      webServer: webServer)
    let executor = EffectExecutor(port: port)
    let runtime = RootRuntime(clock: clock, executor: executor, diagnostics: DiagnosticLogAdapter())
    presentation.pointerEvents = { [weak runtime] in runtime?.send($0, from: .platform) }
    self.window = window
    self.executor = executor
    self.runtime = runtime
    self.webServer = webServer
    webServer.attach(runtime: runtime, locale: { [language] in language.locale })
    webServer.addressChanged = { [weak runtime] endpoint in
      runtime?.send(.webServerAddressChanged(endpoint), from: .webAdministration)
    }
    web.send = { [weak runtime] in runtime?.send($0, from: .webSurface).reply }
    window.contentView = makeContentView(runtime: runtime, web: web)
    input = NativeInputAdapter(
      window: window,
      scope: { [weak runtime] in
        switch runtime?.rootProps.props.mode {
        case .administration: .administration
        case .unlocking: .authentication
        default: .web
        }
      }, send: { [weak runtime] in runtime?.send($0, from: .platform).reply },
      requestTermination: { NSApplication.shared.terminate(nil) })
    lifecycle = LifecycleAdapter(displays: displays) { [weak runtime] in
      runtime?.send($0, from: .platform)
    }
    input?.start()
    lifecycle?.start()
    installMenu()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate()
    runtime.send(.macDisplaysChanged(displays.availableDisplays), from: .platform)
    runtime.send(.bootstrapRequested, from: .root)
  }

  private func makeEffectPort(
    web: WebKitAdapter, presentation: PresentationAdapter, clock: MonotonicClock,
    displays: DisplayAdapter, webServer: WebAdministrationServer
  ) -> NativeEffectPort {
    let location =
      profileFileURL
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(storageNamespace, isDirectory: true).appendingPathComponent(
        "profile.json")
    return NativeEffectPort(
      web: web, presentation: presentation,
      repository: ProfileRepository(fileURL: location),
      credentials: CredentialStore(
        service: credentialService, keychain: credentialKeychain,
        legacyService: legacyCredentialService),
      biometrics: BiometricCredentialAdapter(
        service: credentialService,
        enableReason: { [language] in
          L10n.string("Enable administrator unlock with biometrics", locale: language.locale)
        },
        unlockReason: { [language] in
          L10n.string("Unlock administrator settings", locale: language.locale)
        }),
      clock: clock, displays: displays, webServer: webServer)
  }

  private func makeWindow() -> ExhibitionWindow {
    let window = ExhibitionWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 780),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = preview ? "Plinth — Preview" : "Plinth"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    return window
  }

  private func makeContentView(runtime: RootRuntime, web: WebKitAdapter) -> NSView {
    NSHostingView(
      rootView: KioskRootView(
        root: runtime.rootProps, settings: runtime.settingsProps, unlock: runtime.unlockProps,
        web: runtime.webProps, host: PassiveWebHost(host: web.host),
        language: language,
        selectLanguage: { [weak self] selected in
          self?.language.select(selected)
          self?.installMenu()
        },
        settingsIntent: { [weak self] in self?.settings($0) },
        unlockIntent: { [weak self] in self?.unlock($0) }))
  }

  private func settings(_ intent: SettingsIntent) {
    let event: Event
    switch intent {
    case .edit(let edit): event = .draftEdited(edit)
    case .editPasscode(let value): event = .passcodeEdited(value)
    case .save: event = .saveDraftRequested
    case .discard: event = .discardDraftRequested
    case .addOriginRule: event = .addOriginRuleRequested
    case .removeOriginRule(let id): event = .removeOriginRuleRequested(id)
    case .configurePasscode: event = .configurePasscodeRequested
    case .changeBiometricUnlock(let enabled): event = .biometricChangeRequested(enabled)
    case .cancelBiometricChange: event = .biometricChangeCancelled
    case .start: event = .startExhibitionRequested
    case .prepareExternalScene: event = .prepareExternalSceneRequested
    case .quit:
      NSApplication.shared.terminate(nil)
      return
    }
    runtime?.send(event, from: .settings)
  }

  private func unlock(_ intent: UnlockIntent) {
    let event: Event
    switch intent {
    case .editPasscode(let value): event = .passcodeEdited(value)
    case .submit:
      runtime?.send(.biometricUnlockCancelled, from: .unlock)
      event = .passcodeSubmitted
    case .authenticateWithBiometrics: event = .biometricUnlockRequested
    case .cancelBiometricAuthentication: event = .biometricUnlockCancelled
    case .cancel: event = .cancelAuthentication
    }
    runtime?.send(event, from: .unlock)
  }

  private func installMenu() {
    let locale = language.locale
    let menu = NSMenu()
    let root = NSMenuItem()
    let applicationMenu = NSMenu()
    applicationMenu.addItem(
      withTitle: L10n.string("Quit Plinth", locale: locale),
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    root.submenu = applicationMenu
    menu.addItem(root)
    let edit = NSMenuItem()
    let editMenu = NSMenu(title: L10n.string("Edit", locale: locale))
    editMenu.addItem(
      withTitle: L10n.string("Undo", locale: locale), action: Selector(("undo:")),
      keyEquivalent: "z")
    editMenu.addItem(.separator())
    editMenu.addItem(
      withTitle: L10n.string("Cut", locale: locale), action: #selector(NSText.cut(_:)),
      keyEquivalent: "x")
    editMenu.addItem(
      withTitle: L10n.string("Copy", locale: locale), action: #selector(NSText.copy(_:)),
      keyEquivalent: "c")
    editMenu.addItem(
      withTitle: L10n.string("Paste", locale: locale), action: #selector(NSText.paste(_:)),
      keyEquivalent: "v")
    editMenu.addItem(
      withTitle: L10n.string("Select All", locale: locale), action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a")
    edit.submenu = editMenu
    menu.addItem(edit)
    NSApplication.shared.mainMenu = menu
  }

  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApplication.shared.terminate(nil)
    return false
  }

  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard runtime?.send(.terminateRequested, from: .platform).reply == .accepted else {
      return .terminateCancel
    }
    // Termination is accepted only after administrative access; explicit stop restores native resources.
    stop()
    return .terminateNow
  }

  public func applicationWillTerminate(_ notification: Notification) { stop() }

  private func stop() {
    input?.stop()
    lifecycle?.stop()
    runtime?.stop()
    input = nil
    lifecycle = nil
    runtime = nil
    executor = nil
    webServer = nil
    window?.delegate = nil
    window?.close()
    window = nil
  }
}
