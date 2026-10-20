import KioskCore
import KioskLocalization
import KioskPresentation
import KioskRuntime
import SwiftUI

public struct KioskRootView<WebHost: View>: View {
  let root: RenderPropsStore<RootProps>
  let settings: RenderPropsStore<SettingsProps>
  let remote: RenderPropsStore<RemoteManagementProps>
  let unlock: RenderPropsStore<UnlockProps>
  let web: RenderPropsStore<WebSurfaceProps>
  let host: WebHost
  let biometricHost: AnyView?
  let language: LanguagePreference
  let selectLanguage: (InterfaceLanguage) -> Void
  let settingsIntent: (SettingsIntent) -> Void
  let unlockIntent: (UnlockIntent) -> Void
  let pointerSetupGuidance: String?
  private var locale: Locale { language.locale }

  public init(
    root: RenderPropsStore<RootProps>, settings: RenderPropsStore<SettingsProps>,
    remote: RenderPropsStore<RemoteManagementProps>,
    unlock: RenderPropsStore<UnlockProps>, web: RenderPropsStore<WebSurfaceProps>, host: WebHost,
    biometricHost: AnyView? = nil,
    language: LanguagePreference, selectLanguage: @escaping (InterfaceLanguage) -> Void,
    settingsIntent: @escaping (SettingsIntent) -> Void,
    unlockIntent: @escaping (UnlockIntent) -> Void,
    pointerSetupGuidance: String? = nil
  ) {
    self.root = root
    self.settings = settings
    self.remote = remote
    self.unlock = unlock
    self.web = web
    self.host = host
    self.biometricHost = biometricHost
    self.language = language
    self.selectLanguage = selectLanguage
    self.settingsIntent = settingsIntent
    self.unlockIntent = unlockIntent
    self.pointerSetupGuidance = pointerSetupGuidance
  }

  public var body: some View {
    Group {
      if !root.props.administrationAvailable {
        Color.black.ignoresSafeArea()
      } else if root.props.showsAdministration {
        VStack(spacing: 0) {
          Picker(
            L10n.string("Device", locale: locale),
            selection: Binding(
              get: { remote.props.selectedTab },
              set: { settingsIntent(.remoteTab($0)) })
          ) {
            Text(L10n.string("This device", locale: locale)).tag(RemoteManagementTab.thisDevice)
            Text(L10n.string("Other devices", locale: locale)).tag(RemoteManagementTab.otherDevices)
          }
          .pickerStyle(.segmented)
          .padding(.horizontal)
          .padding(.top, 8)
          .accessibilityIdentifier("management-device-tab")
          if remote.props.selectedTab == .thisDevice {
            SettingsView(
              props: settings.props, remote: remote.props, send: settingsIntent,
              language: language.selection, selectLanguage: selectLanguage)
          } else {
            RemoteDeviceListView(props: remote.props, send: settingsIntent)
          }
        }
      } else {
        ZStack {
          Color.black
          if root.props.showsUnlock {
            UnlockView(props: unlock.props, biometricHost: biometricHost, send: unlockIntent)
          } else if root.props.mode == .paused {
            Label(L10n.string("Exhibition paused", locale: locale), systemImage: "pause.circle")
              .font(.title2).foregroundStyle(.white)
              .accessibilityIdentifier("exhibition-paused")
          } else if root.props.mode == .safeHold {
            if root.props.showsPointerSetupHelp {
              PointerSetupHelpView(
                instructions: pointerSetupGuidance
                  ?? "Switch Plinth to full screen.")
            } else {
              Label(
                L10n.string("Exhibition stopped", locale: locale),
                systemImage: "exclamationmark.triangle"
              )
              .font(.title2).foregroundStyle(.white)
              .accessibilityIdentifier("exhibition-stopped")
            }
          } else {
            host.allowsHitTesting(web.props.acceptsInput)
            if web.props.phase != .ready {
              Color.black
              ProgressView().tint(.white).accessibilityIdentifier("exhibition-preparing")
            } else if web.props.pageLoad == .loading {
              ProgressView().controlSize(.small).padding(12)
                .background(.regularMaterial, in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding()
                .allowsHitTesting(false)
            }
          }
        }
        .ignoresSafeArea()
      }
    }
    .environment(\.locale, language.locale)
  }
}
