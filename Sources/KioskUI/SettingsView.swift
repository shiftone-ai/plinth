import KioskCore
import KioskPresentation
import SwiftUI

public struct SettingsView: View {
  let props: SettingsProps
  let send: (SettingsIntent) -> Void
  @FocusState private var focusedField: Field?
  private enum Field: Hashable {
    case startURL
    case domain(UInt64)
    case idle, passcode
  }

  public init(props: SettingsProps, send: @escaping (SettingsIntent) -> Void) {
    self.props = props
    self.send = send
  }

  public var body: some View {
    VStack(spacing: 0) {
      Form {
        #if os(macOS)
          Section("出力") {
            Picker("方式", selection: value(\.macOutput.mode, edit: ProfileDraftEdit.macOutputMode)) {
              Text("全画面固定").tag(MacOutputSettings.Mode.fixedFullscreen)
              Text("ウィンドウ表示").tag(MacOutputSettings.Mode.projectionWindow)
            }
            .accessibilityIdentifier("mac-output-mode")
            if props.draft.macOutput.mode == .fixedFullscreen {
              Picker(
                "画面", selection: value(\.macOutput.displayID, edit: ProfileDraftEdit.macDisplayID)
              ) {
                Text("自動").tag(String?.none)
                ForEach(props.macDisplays ?? []) { display in
                  Text(display.name).tag(String?.some(display.id))
                }
                if let id = props.draft.macOutput.displayID,
                  props.macDisplays?.contains(where: { $0.id == id }) != true
                {
                  Text("未接続の画面").tag(String?.some(id))
                }
              }
              .accessibilityIdentifier("mac-output-display")
            }
          }
        #endif
        #if os(iOS)
          Section("展示先") {
            Picker(
              "画面",
              selection: value(
                \.profile.exhibitionDestination, edit: ProfileDraftEdit.exhibitionDestination)
            ) {
              Text("本体").tag(ExhibitionDestination?.none)
              Text("外部ディスプレイ").tag(ExhibitionDestination?.some(.externalDisplay))
                .disabled(!props.supportsExternalDisplay)
            }
            .accessibilityIdentifier("exhibition-destination")
            if props.draft.profile.exhibitionDestination == .externalDisplay {
              Picker(
                "回転",
                selection: value(
                  \.externalDisplayRotation, edit: { .externalDisplayRotation($0) })
              ) {
                Text("標準（0°）").tag(ExternalDisplayRotation.standard)
                Text("右90°").tag(ExternalDisplayRotation.clockwise)
                Text("180°").tag(ExternalDisplayRotation.upsideDown)
                Text("左90°").tag(ExternalDisplayRotation.counterclockwise)
              }
              .accessibilityIdentifier("external-display-rotation")
            }
            if props.draft.profile.exhibitionDestination == .externalDisplay,
              !props.externalDisplayModes.isEmpty || props.draft.profile.externalDisplayMode != nil
            {
              Picker(
                "解像度",
                selection: value(
                  \.profile.externalDisplayMode, edit: ProfileDraftEdit.externalDisplayMode)
              ) {
                Text("自動").tag(ExternalDisplayMode?.none)
                ForEach(props.externalDisplayModes) { mode in
                  Text(verbatim: "\(mode.width) × \(mode.height)").tag(
                    ExternalDisplayMode?.some(mode))
                }
                if let mode = props.draft.profile.externalDisplayMode,
                  !props.externalDisplayModes.contains(mode)
                {
                  Text("\(mode.width) × \(mode.height)（未接続）").tag(ExternalDisplayMode?.some(mode))
                }
              }
              .accessibilityIdentifier("external-display-mode")
            }
            if props.draft.profile.exhibitionDestination == .externalDisplay
              && props.showsExhibitionWindowPreparation
            {
              Button("展示ウィンドウを開く", systemImage: "display") { send(.prepareExternalScene) }
                .disabled(!props.canPrepareExternalScene)
                .accessibilityIdentifier("prepare-external-scene")
              if props.externalScenePreparationFailed {
                Label("展示ウィンドウを開けませんでした", systemImage: "exclamationmark.circle")
                  .foregroundStyle(.red)
              }
            }
          }
        #endif
        Section("展示ページ") {
          #if os(iOS)
            Text("開始URL").font(.caption).foregroundStyle(.secondary)
          #endif
          TextField("開始URL", text: value(\.profile.startURL, edit: ProfileDraftEdit.startURL))
            .focused($focusedField, equals: .startURL)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .textContentType(.URL)
            #if os(iOS)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .keyboardType(.URL)
            #endif
            .accessibilityIdentifier("start-url")
          Picker(
            "閲覧先",
            selection: value(\.profile.navigation.mode, edit: ProfileDraftEdit.navigationMode)
          ) {
            Text("許可リスト").tag(NavigationPolicy.Mode.allowlist)
            Text("拒否リスト").tag(NavigationPolicy.Mode.denylist)
          }
          if let address = props.automaticallyAllowedAddress {
            AutomaticOriginView(address: address)
          }
          ForEach(props.draft.rules) { rule in
            VStack(alignment: .leading) {
              #if os(iOS)
                Text("ドメイン").font(.caption).foregroundStyle(.secondary)
              #endif
              HStack {
                TextField(
                  "ドメイン",
                  text: Binding(
                    get: { rule.address }, set: { send(.edit(.originAddress(rule.id, $0))) }),
                  prompt: Text("*.example.com")
                )
                .accessibilityIdentifier("origin-\(rule.id)")
                .focused($focusedField, equals: .domain(rule.id))
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                #if os(iOS)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .keyboardType(.URL)
                #endif
                Button("ルールを削除", systemImage: "minus.circle") {
                  send(.removeOriginRule(rule.id))
                }
                .labelStyle(.iconOnly)
              }
            }
          }
          Button("ドメインを追加", systemImage: "plus") {
            send(.addOriginRule)
          }
          .accessibilityIdentifier("add-origin")
          Toggle(
            "HTTPを許可",
            isOn: value(\.profile.navigation.allowsHTTP, edit: ProfileDraftEdit.allowsHTTP)
          )
          .accessibilityIdentifier("allow-http")
          Label("閲覧先の制限は主ページに適用されます。画像や埋め込みコンテンツは対象外です。", systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section("操作と復帰") {
          Toggle(
            "スクロールを許可",
            isOn: value(\.profile.interaction.allowsScroll, edit: ProfileDraftEdit.allowsScroll))
          Toggle(
            "ドラッグを許可",
            isOn: value(\.profile.interaction.allowsDrag, edit: ProfileDraftEdit.allowsDrag))
          #if os(iOS)
            Text("無操作で復帰するまでの秒数").font(.caption).foregroundStyle(.secondary)
          #endif
          TextField(
            "無操作で復帰するまでの秒数", text: value(\.idleTimeoutText, edit: ProfileDraftEdit.idleTimeoutText)
          )
          .accessibilityIdentifier("idle-seconds")
          .focused($focusedField, equals: .idle)
          .submitLabel(.done)
          .onSubmit { focusedField = nil }
          Picker(
            "復帰時のサイトデータ", selection: value(\.profile.resetMode, edit: ProfileDraftEdit.resetMode)
          ) {
            Text("新しい閲覧セッション").tag(ResetMode.newVisitorSession)
            Text("Cookieなどを保持").tag(ResetMode.retainWebsiteData)
          }
        }
        Section("管理者") {
          SecureField(
            "新しいパスコード（8文字以上）",
            text: Binding(
              get: { props.passcode }, set: { send(.editPasscode($0)) })
          )
          .accessibilityIdentifier("setup-passcode")
          .focused($focusedField, equals: .passcode)
          .submitLabel(.done)
          .onSubmit { focusedField = nil }
          Button(props.credentialsConfigured ? "パスコードを変更" : "パスコードを保存") {
            send(.configurePasscode)
          }
          .disabled(props.passcode.count < 8 || props.configuringCredential)
          .accessibilityIdentifier("save-passcode")
          if props.credentialConfigurationFailed {
            Label("パスコードを保存できませんでした", systemImage: "exclamationmark.circle")
              .foregroundStyle(.red)
          }
          #if os(macOS)
            LabeledContent("管理者解除", value: "⌘ ⌥ ⇧ K")
          #endif
        }
        if !props.validationMessages.isEmpty {
          Section {
            ForEach(props.validationMessages) { message in
              Label(message.text, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .accessibilityIdentifier("validation-\(message.id.rawValue)")
            }
          }
        }
      }
      .formStyle(.grouped)
      .scrollDismissesKeyboard(.interactively)
      .disabled(props.saving)
      HStack {
        #if os(macOS)
          Button("終了") { send(.quit) }
        #endif
        Spacer()
        if props.saveFailed {
          Label("設定を保存できませんでした", systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
        }
        if props.saving { ProgressView().controlSize(.small) }
        Button("変更を破棄") { send(.discard) }.disabled(props.saving)
        Button("設定を保存") { send(.save) }.disabled(!props.canSave)
          .accessibilityIdentifier("save-profile")
        Button("展示を開始") { send(.start) }.disabled(!props.canStart)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("start-exhibition")
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func value<Value>(
    _ path: KeyPath<ProfileDraft, Value>, edit: @escaping (Value) -> ProfileDraftEdit
  ) -> Binding<Value> {
    Binding(get: { props.draft[keyPath: path] }, set: { send(.edit(edit($0))) })
  }
}
