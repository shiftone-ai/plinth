import KioskCore
import KioskLocalization
import KioskPresentation
import SwiftUI

public struct SettingsView: View {
  let props: SettingsProps
  let send: (SettingsIntent) -> Void
  let language: InterfaceLanguage
  let selectLanguage: (InterfaceLanguage) -> Void
  @Environment(\.locale) private var locale
  @FocusState private var focusedField: Field?
  private enum Field: Hashable {
    case startURL
    case domain(UInt64)
    case idle
  }

  public init(
    props: SettingsProps, send: @escaping (SettingsIntent) -> Void,
    language: InterfaceLanguage, selectLanguage: @escaping (InterfaceLanguage) -> Void
  ) {
    self.props = props
    self.send = send
    self.language = language
    self.selectLanguage = selectLanguage
  }

  public var body: some View {
    VStack(spacing: 0) {
      #if os(iOS)
        Color(uiColor: .systemGroupedBackground).frame(height: 44)
      #endif
      Form {
        SettingsLanguageSection(language: language, select: selectLanguage)
        #if os(macOS)
          Section(L10n.string("出力", locale: locale)) {
            Picker(
              L10n.string("方式", locale: locale),
              selection: value(\.macOutput.mode, edit: ProfileDraftEdit.macOutputMode)
            ) {
              Text(L10n.string("全画面固定", locale: locale)).tag(MacOutputSettings.Mode.fixedFullscreen)
              Text(L10n.string("ウィンドウ表示", locale: locale)).tag(
                MacOutputSettings.Mode.projectionWindow)
            }
            .accessibilityIdentifier("mac-output-mode")
            if props.draft.macOutput.mode == .fixedFullscreen {
              Picker(
                L10n.string("画面", locale: locale),
                selection: value(\.macOutput.displayID, edit: ProfileDraftEdit.macDisplayID)
              ) {
                Text(L10n.string("自動", locale: locale)).tag(String?.none)
                ForEach(props.macDisplays ?? []) { display in
                  Text(display.name).tag(String?.some(display.id))
                }
                if let id = props.draft.macOutput.displayID,
                  props.macDisplays?.contains(where: { $0.id == id }) != true
                {
                  Text(L10n.string("未接続の画面", locale: locale)).tag(String?.some(id))
                }
              }
              .accessibilityIdentifier("mac-output-display")
            }
          }
        #endif
        #if os(iOS)
          Section(L10n.string("展示先", locale: locale)) {
            Picker(
              L10n.string("画面", locale: locale),
              selection: value(
                \.profile.exhibitionDestination, edit: ProfileDraftEdit.exhibitionDestination)
            ) {
              Text(L10n.string("本体", locale: locale)).tag(ExhibitionDestination?.none)
              Text(L10n.string("外部ディスプレイ", locale: locale)).tag(
                ExhibitionDestination?.some(.externalDisplay)
              )
              .disabled(!props.supportsExternalDisplay)
            }
            .accessibilityIdentifier("exhibition-destination")
            if props.draft.profile.exhibitionDestination == .externalDisplay {
              Picker(
                L10n.string("回転", locale: locale),
                selection: value(
                  \.externalDisplayRotation, edit: { .externalDisplayRotation($0) })
              ) {
                Text(L10n.string("標準（0°）", locale: locale)).tag(ExternalDisplayRotation.standard)
                Text(L10n.string("右90°", locale: locale)).tag(ExternalDisplayRotation.clockwise)
                Text("180°").tag(ExternalDisplayRotation.upsideDown)
                Text(L10n.string("左90°", locale: locale)).tag(
                  ExternalDisplayRotation.counterclockwise)
              }
              .accessibilityIdentifier("external-display-rotation")
            }
            if props.draft.profile.exhibitionDestination == .externalDisplay,
              !props.externalDisplayModes.isEmpty || props.draft.profile.externalDisplayMode != nil
            {
              Picker(
                L10n.string("解像度", locale: locale),
                selection: value(
                  \.profile.externalDisplayMode, edit: ProfileDraftEdit.externalDisplayMode)
              ) {
                Text(L10n.string("自動", locale: locale)).tag(ExternalDisplayMode?.none)
                ForEach(props.externalDisplayModes) { mode in
                  Text(verbatim: "\(mode.width) × \(mode.height)").tag(
                    ExternalDisplayMode?.some(mode))
                }
                if let mode = props.draft.profile.externalDisplayMode,
                  !props.externalDisplayModes.contains(mode)
                {
                  Text(
                    verbatim: "\(mode.width) × \(mode.height) \(L10n.string("未接続", locale: locale))"
                  ).tag(
                    ExternalDisplayMode?.some(mode))
                }
              }
              .accessibilityIdentifier("external-display-mode")
            }
            if props.draft.profile.exhibitionDestination == .externalDisplay
              && props.showsExhibitionWindowPreparation
            {
              Button(L10n.string("展示ウィンドウを開く", locale: locale), systemImage: "display") {
                send(.prepareExternalScene)
              }
              .disabled(!props.canPrepareExternalScene)
              .accessibilityIdentifier("prepare-external-scene")
              if props.externalScenePreparationFailed {
                Label(
                  L10n.string("展示ウィンドウを開けませんでした", locale: locale),
                  systemImage: "exclamationmark.circle"
                )
                .foregroundStyle(.red)
              }
            }
          }
        #endif
        Section(L10n.string("展示ページ", locale: locale)) {
          #if os(iOS)
            Text(L10n.string("開始URL", locale: locale)).font(.caption).foregroundStyle(.secondary)
          #endif
          TextField(
            startURLFieldTitle,
            text: value(\.profile.startURL, edit: ProfileDraftEdit.startURL)
          )
          .accessibilityLabel(L10n.string("開始URL", locale: locale))
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
            L10n.string("閲覧先", locale: locale),
            selection: value(\.profile.navigation.mode, edit: ProfileDraftEdit.navigationMode)
          ) {
            Text(L10n.string("許可リスト", locale: locale)).tag(NavigationPolicy.Mode.allowlist)
            Text(L10n.string("拒否リスト", locale: locale)).tag(NavigationPolicy.Mode.denylist)
          }
          if let address = props.automaticallyAllowedAddress {
            AutomaticOriginView(address: address)
          } else if !props.draft.rules.isEmpty {
            Text(L10n.string("ドメイン", locale: locale)).font(.caption).foregroundStyle(.secondary)
          }
          ForEach(props.draft.rules) { rule in
            HStack {
              TextField(
                L10n.string("ドメイン", locale: locale),
                text: Binding(
                  get: { rule.address }, set: { send(.edit(.originAddress(rule.id, $0))) }),
                prompt: Text("*.example.com")
              )
              .labelsHidden()
              .accessibilityLabel(L10n.string("ドメイン", locale: locale))
              .accessibilityIdentifier("origin-\(rule.id)")
              .focused($focusedField, equals: .domain(rule.id))
              .submitLabel(.done)
              .onSubmit { focusedField = nil }
              #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
              #endif
              Button(L10n.string("ルールを削除", locale: locale), systemImage: "minus.circle") {
                send(.removeOriginRule(rule.id))
              }
              .labelStyle(.iconOnly)
            }
          }
          Button(L10n.string("ドメインを追加", locale: locale), systemImage: "plus") {
            send(.addOriginRule)
          }
          .accessibilityIdentifier("add-origin")
          Toggle(
            L10n.string("HTTPを許可", locale: locale),
            isOn: value(\.profile.navigation.allowsHTTP, edit: ProfileDraftEdit.allowsHTTP)
          )
          .accessibilityIdentifier("allow-http")
          Label(L10n.string("制限は主ページのみ。画像・埋め込みは対象外です", locale: locale), systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section(L10n.string("操作と復帰", locale: locale)) {
          Toggle(
            L10n.string("スクロールを許可", locale: locale),
            isOn: value(\.profile.interaction.allowsScroll, edit: ProfileDraftEdit.allowsScroll))
          Toggle(
            L10n.string("ドラッグを許可", locale: locale),
            isOn: value(\.profile.interaction.allowsDrag, edit: ProfileDraftEdit.allowsDrag))
          #if os(iOS)
            Text(L10n.string("無操作で復帰するまでの秒数", locale: locale)).font(.caption).foregroundStyle(
              .secondary)
          #endif
          TextField(
            L10n.string("無操作で復帰するまでの秒数", locale: locale),
            text: value(\.idleTimeoutText, edit: ProfileDraftEdit.idleTimeoutText)
          )
          .accessibilityIdentifier("idle-seconds")
          .focused($focusedField, equals: .idle)
          .submitLabel(.done)
          .onSubmit { focusedField = nil }
          Picker(
            L10n.string("復帰時のサイトデータ", locale: locale),
            selection: value(\.profile.resetMode, edit: ProfileDraftEdit.resetMode)
          ) {
            Text(L10n.string("新しい閲覧セッション", locale: locale)).tag(ResetMode.newVisitorSession)
            Text(L10n.string("Cookieなどを保持", locale: locale)).tag(ResetMode.retainWebsiteData)
          }
        }
        SettingsPasscodeSection(props: props, send: send)
        if !props.validationMessages.isEmpty {
          Section {
            ForEach(props.validationMessages) { message in
              Label(
                L10n.string(message.textKey, locale: locale), systemImage: "exclamationmark.circle"
              )
              .foregroundStyle(.red)
              .accessibilityIdentifier("validation-\(message.id.rawValue)")
            }
          }
        }
      }
      .formStyle(.grouped)
      .scrollDismissesKeyboard(.interactively)
      .disabled(props.saving)
      SettingsFooter(props: props, send: send)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension SettingsView {
  fileprivate var startURLFieldTitle: String {
    #if os(iOS)
      "https://example.com"
    #else
      L10n.string("開始URL", locale: locale)
    #endif
  }

  fileprivate func value<Value>(
    _ path: KeyPath<ProfileDraft, Value>, edit: @escaping (Value) -> ProfileDraftEdit
  ) -> Binding<Value> {
    Binding(get: { props.draft[keyPath: path] }, set: { send(.edit(edit($0))) })
  }
}
