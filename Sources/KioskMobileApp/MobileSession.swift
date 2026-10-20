#if os(iOS)
  import KioskLocalization
  import KioskCore
  import KioskPresentation
  import KioskRuntime
  import KioskUI
  import SwiftUI
  import UIKit

  @MainActor
  public final class MobileSession {
    static let exhibitionActivity = "ai.shiftone.plinth.exhibition"
    private struct SceneOwner {
      let scene: UIWindowScene
      let window: MobileInputWindow
      let exhibition: Bool
      var registration: (any ExternalDisplayRegistration)?
      let previousOverscanCompensation: UIScreen.OverscanCompensation?
    }
    private let web = WebKitAdapter()
    private let webServer = WebAdministrationServer()
    private let language: LanguagePreference
    private let pointer = MobilePointerAdapter()
    private let displayModes = MobileDisplayModeAdapter()
    private var scenes: [String: SceneOwner] = [:]
    private var deviceScreen: UIScreen?
    private var bootstrapped = false
    private var stopped = false
    private var runtime: RootRuntime!
    private var executor: EffectExecutor!
    private var presentation: MobilePresentationAdapter!
    private let cloudBridge = CatalogCloudEventBridge()
    private let remoteBridge = RemoteCloudEventBridge()

    private struct CredentialConfiguration {
      let storageNamespace: String
      let service: String
      let keychain: CredentialStore.Keychain
    }

    init() {
      let clock = MonotonicClock()
      let cloudEngineHost = CloudSyncEngineHost.shared
      let credentials = Self.credentialConfiguration()
      language = LanguagePreference(storageNamespace: credentials.storageNamespace)
      #if DEBUG
        let testService = ProcessInfo.processInfo.environment["PLINTH_TEST_CREDENTIAL_SERVICE"]
        let fixtureService = testService.flatMap {
          $0.hasPrefix("ai.shiftone.plinth.tests.") ? $0 : nil
        }
      #else
        let fixtureService: String? = nil
      #endif
      let location = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(credentials.storageNamespace, isDirectory: true)
        .appendingPathComponent("profile.json")
      #if DEBUG
        Self.installDamagedCatalogFixture(at: location, service: fixtureService)
      #endif
      presentation = MobilePresentationAdapter()
      presentation.pointer = pointer
      let remoteDirectory: any RemoteDirectoryPort
      #if DEBUG
        if fixtureService != nil,
          ProcessInfo.processInfo.environment["PLINTH_TEST_REMOTE_FIXTURE"] == "1"
        {
          remoteDirectory = RemoteDirectoryUITestFixture { [weak remoteBridge] event in
            remoteBridge?.send(event)
          }
        } else {
          remoteDirectory = RemoteDirectoryCloudSync(
            stateURL: location.deletingLastPathComponent().appendingPathComponent(
              "remote-management.json"),
            displayName: UIDevice.current.name,
            platform: UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone,
            cloudAvailable: Bundle.main.object(forInfoDictionaryKey: "PlinthCloudKitEntitled")
              as? String == "YES",
            keychain: credentials.keychain,
            engineHost: cloudEngineHost
          ) { [weak remoteBridge] event in remoteBridge?.send(event) }
        }
      #else
        remoteDirectory = RemoteDirectoryCloudSync(
          stateURL: location.deletingLastPathComponent().appendingPathComponent(
            "remote-management.json"),
          displayName: UIDevice.current.name,
          platform: UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone,
          cloudAvailable: Bundle.main.object(forInfoDictionaryKey: "PlinthCloudKitEntitled")
            as? String == "YES",
          keychain: credentials.keychain,
          engineHost: cloudEngineHost
        ) { [weak remoteBridge] event in remoteBridge?.send(event) }
      #endif
      let port = NativeEffectPort(
        web: web, presentation: presentation, repository: ProfileRepository(fileURL: location),
        credentials: CredentialStore(service: credentials.service, keychain: credentials.keychain),
        biometrics: MobileBiometricComposition.make(
          service: credentials.service, fixtureService: fixtureService, language: language),
        clock: clock, displays: presentation,
        catalogRepository: CatalogRepository(
          fileURL: location.deletingLastPathComponent().appendingPathComponent("catalog.json")),
        catalogCloudSync: CatalogCloudSync(
          stateURL: location.deletingLastPathComponent().appendingPathComponent(
            "catalog-cloud.json"),
          engineHost: cloudEngineHost
        ) { [weak cloudBridge] event in cloudBridge?.send(event) },
        remoteDirectory: remoteDirectory,
        webServer: webServer)
      #if DEBUG
        if let value = ProcessInfo.processInfo.environment["PLINTH_TEST_IDLE_SECONDS"],
          let timeout = Double(value), timeout.isFinite, timeout > 0
        {
          executor = EffectExecutor(port: MobileTestEffectPort(base: port, idleTimeout: timeout))
        } else {
          executor = EffectExecutor(port: port)
        }
      #else
        executor = EffectExecutor(port: port)
      #endif
      runtime = RootRuntime(clock: clock, executor: executor, diagnostics: DiagnosticLogAdapter())
      cloudBridge.runtime = runtime
      remoteBridge.runtime = runtime
      attachWebServer()
      wireAdapters()
      runtime.send(.catalogLoadRequested, from: .root)
      runtime.send(.remoteLoadRequested, from: .root)
    }

    private func attachWebServer() {
      webServer.attach(runtime: runtime, locale: { [language] in language.locale })
      webServer.addressChanged = { [weak runtime] endpoint in
        runtime?.send(.webServerAddressChanged(endpoint), from: .webAdministration)
      }
    }

    #if DEBUG
      private static func installDamagedCatalogFixture(at profileURL: URL, service: String?) {
        guard service != nil,
          ProcessInfo.processInfo.environment["PLINTH_TEST_CORRUPT_CATALOG"] == "1"
        else { return }
        let catalogURL = profileURL.deletingLastPathComponent().appendingPathComponent(
          "catalog.json")
        try? FileManager.default.createDirectory(
          at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{\"entries\": [".utf8).write(to: catalogURL)
      }
    #endif

    private static func credentialConfiguration() -> CredentialConfiguration {
      #if DEBUG
        let testService = ProcessInfo.processInfo.environment["PLINTH_TEST_CREDENTIAL_SERVICE"]
        let fixtureService = testService.flatMap {
          $0.hasPrefix("ai.shiftone.plinth.tests.") ? $0 : nil
        }
        let keychain: CredentialStore.Keychain =
          fixtureService != nil
            && ProcessInfo.processInfo.environment[
              "PLINTH_TEST_ISOLATED_CREDENTIALS"] == "1"
          ? .testDefaults : .platformDefault
        return .init(
          storageNamespace: fixtureService ?? "Plinth",
          service: fixtureService ?? "ai.shiftone.plinth.mobile", keychain: keychain)
      #else
        return .init(
          storageNamespace: "Plinth", service: "ai.shiftone.plinth.mobile",
          keychain: .platformDefault)
      #endif
    }

    func connect(_ scene: UIWindowScene, exhibitionWindow: Bool) -> UIWindow {
      precondition(!stopped)
      if !exhibitionWindow && deviceScreen == nil { deviceScreen = scene.screen }
      let predicate = NSPredicate(
        format: exhibitionWindow ? "SELF == %@" : "SELF != %@", Self.exhibitionActivity)
      scene.activationConditions.canActivateForTargetContentIdentifierPredicate = predicate
      scene.activationConditions.prefersToActivateForTargetContentIdentifierPredicate = predicate
      let previousOverscanCompensation: UIScreen.OverscanCompensation?
      if scene.session.role == .windowExternalDisplayNonInteractive {
        previousOverscanCompensation = scene.screen.overscanCompensation
        scene.screen.overscanCompensation = .none
      } else {
        previousOverscanCompensation = nil
      }
      let window = MobileInputWindow(windowScene: scene)
      if scene.session.role == .windowExternalDisplayNonInteractive {
        if #available(iOS 27.0, *) {} else { window.frame = scene.screen.bounds }
      }
      let rootView = makeRootView(
        exhibitionWindow: exhibitionWindow,
        displayOnly: scene.session.role == .windowExternalDisplayNonInteractive)
      window.rootViewController = MobileHostingController(rootView: rootView)
      window.scope = { [weak self] in
        switch self?.runtime.rootProps.props.mode {
        case .administration: .administration
        case .unlocking: .authentication
        default: .web
        }
      }
      window.send = { [weak self] in self?.runtime.send($0, from: .platform).reply }
      let registration: (any ExternalDisplayRegistration)?
      // UIKit activates the external Scene after its visible window becomes key.
      // Each Scene has its own key window; the device keeps its own input controller.
      window.makeKeyAndVisible()
      if #available(iOS 27.0, *), !exhibitionWindow, !ProcessInfo.processInfo.isiOSAppOnMac,
        let controller = window.rootViewController
      {
        registration = MobileExternalDisplayRegistration(controller: controller)
      } else {
        registration = nil
      }
      scenes[scene.session.persistentIdentifier] = SceneOwner(
        scene: scene, window: window, exhibition: exhibitionWindow, registration: registration,
        previousOverscanCompensation: previousOverscanCompensation)
      (window.rootViewController as? MobileHostingController<MobileRootView>)?
        .externalRegistration = registration
      displaysChanged()
      if !bootstrapped {
        bootstrapped = true
        runtime.send(.bootstrapRequested, from: .root)
      }
      return window
    }

    func isExhibitionScene(_ scene: UIScene) -> Bool {
      scenes[scene.session.persistentIdentifier]?.exhibition == true
    }

    func disconnect(_ scene: UIWindowScene) {
      displayModes.disconnect(scene)
      if let owner = scenes.removeValue(forKey: scene.session.persistentIdentifier) {
        owner.registration?.stop()
        owner.window.send = nil
        owner.window.scope = nil
        owner.window.isHidden = true
        owner.window.rootViewController = nil
        if let previous = owner.previousOverscanCompensation {
          owner.scene.screen.overscanCompensation = previous
        }
      }
      displaysChanged()
      if scenes.isEmpty { runtime.send(.mobileLastSceneDisconnected, from: .platform) }
    }

    var shouldRestartAfterBootstrapFailure: Bool {
      scenes.isEmpty && runtime.snapshot.root.bootstrapReadFailed
    }

    func continueActivity(_ activity: NSUserActivity, in scene: UIScene) {
      guard isExhibitionScene(scene), activity.activityType == Self.exhibitionActivity else {
        return
      }
      presentation.scenePrepared(for: activity)
    }

    func backgrounded(_ scene: UIWindowScene) {
      if scenes[scene.session.persistentIdentifier]?.exhibition == false
        || selectedOwner()?.scene === scene
      {
        runtime.send(.applicationDeactivated, from: .platform)
      }
      displaysChanged()
    }

    func applicationActivated() {
      runtime.send(.applicationActivated, from: .platform)
      runtime.send(.remoteRefreshRequested, from: .platform)
      runtime.send(.remoteStatusRequested(UUID()), from: .platform)
    }

    func resetExhibitionFromShortcut() -> Bool {
      runtime.send(.shortcutResetRequested, from: .platform).reply == .accepted
    }

    func displaysChanged() {
      let availability = displayModes.availability(
        in: scenes.values.map { (scene: $0.scene, exhibition: $0.exhibition) },
        deviceScreen: deviceScreen)
      runtime.send(.mobileDisplaysChanged(availability), from: .platform)
      displayModes.refresh()
    }

    private func selectedOwner() -> SceneOwner? {
      let destination = runtime.snapshot.root.activeProfile?.exhibitionDestination ?? .device
      return scenes.values.first {
        destination == .externalDisplay
          ? $0.exhibition && deviceScreen != nil && $0.scene.screen !== deviceScreen
            && ($0.scene.session.role == .windowExternalDisplayNonInteractive)
              == runtime.rootProps.props.externalDisplayOnly
          : !$0.exhibition && $0.scene.screen === deviceScreen
      }
    }

    private func setPresentation(_ active: Bool) {
      if active, let frame = presentation.exhibitionFrame {
        web.host.frame = frame
        web.host.layoutIfNeeded()
      }
      for owner in scenes.values {
        (owner.window.rootViewController as? MobileHostingController<MobileRootView>)?.exhibiting =
          active
      }
    }

    private func settings(_ intent: SettingsIntent) {
      if let event = RemoteIntentEventMapper.event(for: intent) {
        runtime.send(event, from: .settings)
        return
      }
      if let event = CatalogIntentEventMapper.event(
        for: intent, importCount: runtime.settingsProps.props.catalog.importPreview?.count ?? 0
      ) {
        runtime.send(event, from: .settings)
        return
      }
      let event: Event
      switch intent {
      case .edit(let edit): event = .draftEdited(edit)
      case .editPasscode(let value): event = .passcodeEdited(value)
      case .configurePasscode: event = .configurePasscodeRequested
      case .changeBiometricUnlock(let enabled): event = .biometricChangeRequested(enabled)
      case .cancelBiometricChange: event = .biometricChangeCancelled
      case .save: event = .saveDraftRequested
      case .discard: event = .discardDraftRequested
      case .addOriginRule: event = .addOriginRuleRequested
      case .removeOriginRule(let id): event = .removeOriginRuleRequested(id)
      case .start: event = .startExhibitionRequested
      case .prepareExternalScene: event = .prepareExternalSceneRequested
      case .openInformationPage(let page, let locale):
        event = .openInformationPageRequested(page, locale: locale)
      case .openLicenses: event = .openLicensesRequested
      case .closeLicenses: event = .closeLicensesRequested
      case .quit: return
      default: return
      }
      runtime.send(event, from: .settings)
    }

    private func unlock(_ intent: UnlockIntent) {
      let event: Event
      switch intent {
      case .editPasscode(let value): event = .passcodeEdited(value)
      case .submit:
        runtime.send(.biometricUnlockCancelled, from: .unlock)
        event = .passcodeSubmitted
      case .authenticateWithBiometrics: event = .biometricUnlockRequested
      case .cancelBiometricAuthentication: event = .biometricUnlockCancelled
      case .cancel: event = .cancelAuthentication
      }
      runtime.send(event, from: .unlock)
    }

    func stop() {
      guard !stopped else { return }
      stopped = true
      displayModes.stop()
      runtime.stop()
      pointer.stop()
      web.send = nil
      presentation.selectedScene = nil
      presentation.exhibitionChanged = nil
      presentation.existingExhibitionScene = nil
      for owner in scenes.values {
        owner.registration?.stop()
        owner.window.send = nil
        owner.window.scope = nil
        owner.window.isHidden = true
        owner.window.rootViewController = nil
        if let previous = owner.previousOverscanCompensation {
          owner.scene.screen.overscanCompensation = previous
        }
      }
      scenes.removeAll()
    }
  }

  extension MobileSession {
    private func wireAdapters() {
      pointer.send = { [weak self] in self?.runtime.send($0, from: .platform).reply }
      pointer.bodyScene = { [weak self] in self?.scenes.values.first { !$0.exhibition }?.scene }
      pointer.requestLock = { [weak self] requested in
        for owner in self?.scenes.values ?? [String: SceneOwner]().values where !owner.exhibition {
          (owner.window.rootViewController as? MobileHostingController<MobileRootView>)?
            .pointerLockRequested = requested
        }
      }
      pointer.viewport = { [weak self] in self?.presentation.exhibitionFrame?.size }
      pointer.generation = { [weak self] in self?.runtime.webProps.props.generation ?? 0 }
      pointer.start()
      web.send = { [weak self] in self?.runtime.send($0, from: .webSurface).reply }
      presentation.selectedScene = { [weak self] in self?.selectedOwner()?.scene }
      presentation.exhibitionChanged = { [weak self] active in self?.setPresentation(active) }
      presentation.existingExhibitionScene = { [weak self] in
        self?.scenes.values.first(where: \.exhibition)?.scene
      }
      displayModes.selectedWindow = { [weak self] in self?.selectedOwner()?.window }
      displayModes.changed = { [weak self] in self?.displaysChanged() }
      displayModes.canConfigure = { [weak self] in
        self?.scenes.values.contains {
          !$0.exhibition && $0.scene.activationState == .foregroundActive
        } == true
      }
      presentation.prepareDisplayMode = { [weak self] mode, token in
        await self?.displayModes.prepare(mode, token: token) ?? false
      }
      presentation.cancelDisplayMode = { [weak self] token in self?.displayModes.cancel(token) }
    }

    private func makeRootView(exhibitionWindow: Bool, displayOnly: Bool) -> MobileRootView {
      MobileRootView(
        root: runtime.rootProps, settings: runtime.settingsProps, remote: runtime.remoteProps,
        unlock: runtime.unlockProps,
        web: runtime.webProps, host: web.host,
        language: language, selectLanguage: { [weak self] in self?.language.select($0) },
        exhibitionWindow: exhibitionWindow,
        displayOnly: displayOnly,
        pointerSetupGuidance: MobilePointerSetupGuidance.instructions,
        settingsIntent: { [weak self] in self?.settings($0) },
        unlockIntent: { [weak self] in self?.unlock($0) },
        rootIntent: { [weak self] _ in self?.runtime.send(.unlockRequested, from: .platform) },
        externalControl: { [weak self] control, generation in
          self?.runtime.send(
            .externalWebControlRequested(control, generation: generation), from: .platform)
        })
    }
  }
#endif
