import KioskCore
import KioskLocalization
import KioskPresentation
import KioskRuntime
import SwiftUI

public struct KioskRootView<WebHost: View>: View {
  let root: RenderPropsStore<RootProps>
  let settings: RenderPropsStore<SettingsProps>
  let unlock: RenderPropsStore<UnlockProps>
  let web: RenderPropsStore<WebSurfaceProps>
  let host: WebHost
  let language: LanguagePreference
  let selectLanguage: (InterfaceLanguage) -> Void
  let settingsIntent: (SettingsIntent) -> Void
  let unlockIntent: (UnlockIntent) -> Void
  let pointerSetupGuidance: String?
  private var locale: Locale { language.locale }

  public init(
    root: RenderPropsStore<RootProps>, settings: RenderPropsStore<SettingsProps>,
    unlock: RenderPropsStore<UnlockProps>, web: RenderPropsStore<WebSurfaceProps>, host: WebHost,
    language: LanguagePreference, selectLanguage: @escaping (InterfaceLanguage) -> Void,
    settingsIntent: @escaping (SettingsIntent) -> Void,
    unlockIntent: @escaping (UnlockIntent) -> Void,
    pointerSetupGuidance: String? = nil
  ) {
    self.root = root
    self.settings = settings
    self.unlock = unlock
    self.web = web
    self.host = host
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
        SettingsView(
          props: settings.props, send: settingsIntent, language: language.selection,
          selectLanguage: selectLanguage)
      } else {
        ZStack {
          Color.black
          if root.props.showsUnlock {
            UnlockView(props: unlock.props, send: unlockIntent)
          } else if root.props.mode == .safeHold {
            if root.props.showsPointerSetupHelp {
              PointerSetupHelpView(
                instructions: pointerSetupGuidance
                  ?? "Plinthを全画面表示にしてください。")
            } else {
              Label(
                L10n.string("展示を停止しました", locale: locale), systemImage: "exclamationmark.triangle"
              )
              .font(.title2).foregroundStyle(.white)
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
