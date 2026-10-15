import AppKit
import KioskCore
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
  private let preview: Bool
  private let exhibitionInset: Double
  private let profileFileURL: URL?
  private let credentialService: String
  private let credentialKeychain: CredentialStore.Keychain
  private let legacyCredentialService: String?
  private let storageNamespace: String

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
  }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    let window = ExhibitionWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 780),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = preview ? "Plinth — Preview" : "Plinth"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    let clock = MonotonicClock()
    let displays = DisplayAdapter(exhibitionInset: exhibitionInset)
    let web = WebKitAdapter()
    let location =
      profileFileURL
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
        0
      ]
      .appendingPathComponent(storageNamespace, isDirectory: true).appendingPathComponent(
        "profile.json")
    let presentation = PresentationAdapter(window: window, preview: preview, displays: displays)
    let port = NativeEffectPort(
      web: web,
      presentation: presentation,
      repository: ProfileRepository(fileURL: location),
      credentials: CredentialStore(
        service: credentialService, keychain: credentialKeychain,
        legacyService: legacyCredentialService), clock: clock, displays: displays
    )
    let executor = EffectExecutor(port: port)
    let runtime = RootRuntime(clock: clock, executor: executor, diagnostics: DiagnosticLogAdapter())
    presentation.pointerEvents = { [weak runtime] in runtime?.send($0, from: .platform) }
    self.window = window
    self.executor = executor
    self.runtime = runtime
    web.send = { [weak runtime] in runtime?.send($0, from: .webSurface).reply }
    window.contentView = NSHostingView(
      rootView: KioskRootView(
        root: runtime.rootProps, settings: runtime.settingsProps, unlock: runtime.unlockProps,
        web: runtime.webProps, host: PassiveWebHost(host: web.host),
        settingsIntent: { [weak self] in self?.settings($0) },
        unlockIntent: { [weak self] in self?.unlock($0) }))
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
    case .submit: event = .passcodeSubmitted
    case .cancel: event = .cancelAuthentication
    }
    runtime?.send(event, from: .unlock)
  }

  private func installMenu() {
    let menu = NSMenu()
    let root = NSMenuItem()
    let applicationMenu = NSMenu()
    applicationMenu.addItem(
      withTitle: "Plinthを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    root.submenu = applicationMenu
    menu.addItem(root)
    let edit = NSMenuItem()
    let editMenu = NSMenu(title: "編集")
    editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "切り取り", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "貼り付け", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "すべて選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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
    window?.delegate = nil
    window?.close()
    window = nil
  }
}
