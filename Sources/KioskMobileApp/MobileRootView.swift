#if os(iOS)
  import KioskCore
  import KioskPresentation
  import KioskRuntime
  import KioskUI
  import SwiftUI
  import UIKit

  struct MobileRootView: View {
    let root: RenderPropsStore<RootProps>
    let settings: RenderPropsStore<SettingsProps>
    let unlock: RenderPropsStore<UnlockProps>
    let web: RenderPropsStore<WebSurfaceProps>
    let host: UIView
    let exhibitionWindow: Bool
    let displayOnly: Bool
    let pointerSetupGuidance: String
    let settingsIntent: (SettingsIntent) -> Void
    let unlockIntent: (UnlockIntent) -> Void
    let rootIntent: (RootIntent) -> Void
    let externalControl: (ExternalWebControl, UInt64) -> Void

    var body: some View {
      ZStack {
        if exhibitionWindow {
          Color.black.ignoresSafeArea()
          if root.props.exhibitionDestination == .externalDisplay && root.props.mode == .exhibiting
            && root.props.externalDisplayOnly == displayOnly
          {
            MobileExternalSurface(rotation: root.props.externalDisplayRotation) {
              PassiveMobileWebHost(host: host).allowsHitTesting(web.props.acceptsInput)
                .overlay {
                  if displayOnly, let point = root.props.externalPointer {
                    GeometryReader { geometry in
                      Image(systemName: "cursorarrow")
                        .foregroundStyle(.white).shadow(color: .black, radius: 1)
                        .position(
                          x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                    }.allowsHitTesting(false).accessibilityHidden(true)
                  }
                }
            }
          } else if root.props.mode == .administration && !displayOnly {
            Label("このウィンドウを外部ディスプレイへ移動", systemImage: "display")
              .foregroundStyle(.white)
          }
        } else if root.props.exhibitionDestination == .externalDisplay
          && [.exhibiting, .enteringKiosk].contains(root.props.mode)
        {
          Color.black.ignoresSafeArea()
          if root.props.externalDisplayOnly {
            PassiveExternalControl(
              enabled: web.props.acceptsInput, allowsDrag: root.props.externalAllowsDrag,
              pointerCaptured: root.props.externalPointerLocked
            ) {
              externalControl($0, web.props.generation)
            }.ignoresSafeArea()
          }
          Image(systemName: "display").foregroundStyle(.white)
            .accessibilityLabel("展示中")
            .accessibilityIdentifier("external-exhibition-active")
            .allowsHitTesting(false)
        } else {
          KioskRootView(
            root: root, settings: settings, unlock: unlock, web: web,
            host: PassiveMobileWebHost(host: host),
            settingsIntent: settingsIntent, unlockIntent: unlockIntent,
            pointerSetupGuidance: pointerSetupGuidance)
        }
      }
      .overlay(alignment: .topTrailing) {
        if !exhibitionWindow && root.props.administrationAvailable
          && !root.props.showsAdministration && !root.props.showsUnlock
        {
          PassiveAdministratorEntry { rootIntent(.unlock) }
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
            .padding()
            .accessibilityIdentifier("request-unlock")
        }
      }
    }
  }

  final class AdministratorEntryButton: UIButton {}

  private struct PassiveAdministratorEntry: UIViewRepresentable {
    let send: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(send: send) }
    func makeUIView(context: Context) -> AdministratorEntryButton {
      let button = AdministratorEntryButton(type: .system)
      button.setImage(UIImage(systemName: "lock"), for: .normal)
      button.tintColor = .label
      button.accessibilityLabel = "管理者解除"
      button.accessibilityIdentifier = "request-unlock"
      button.addTarget(
        context.coordinator, action: #selector(Coordinator.request), for: .touchUpInside)
      return button
    }
    func updateUIView(_ button: AdministratorEntryButton, context: Context) {
      context.coordinator.send = send
    }
    @MainActor final class Coordinator: NSObject {
      var send: () -> Void
      init(send: @escaping () -> Void) { self.send = send }
      @objc func request() { send() }
    }
  }

  private struct PassiveMobileWebHost: UIViewRepresentable {
    let host: UIView
    func makeUIView(context: Context) -> UIView { host }
    func updateUIView(_ uiView: UIView, context: Context) {}
  }
#endif
