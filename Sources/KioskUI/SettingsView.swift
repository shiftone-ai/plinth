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
        SettingsOutputSection(props: props, send: send)
        Section(L10n.string("Exhibition page", locale: locale)) {
          #if os(iOS)
            Text(L10n.string("Start URL", locale: locale)).font(.caption).foregroundStyle(
              .secondary)
          #endif
          TextField(
            startURLFieldTitle,
            text: value(\.profile.startURL, edit: ProfileDraftEdit.startURL)
          )
          .accessibilityLabel(L10n.string("Start URL", locale: locale))
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
            L10n.string("Navigation", locale: locale),
            selection: value(\.profile.navigation.mode, edit: ProfileDraftEdit.navigationMode)
          ) {
            Text(L10n.string("Allowlist", locale: locale)).tag(NavigationPolicy.Mode.allowlist)
            Text(L10n.string("Blocklist", locale: locale)).tag(NavigationPolicy.Mode.denylist)
          }
          if let address = props.automaticallyAllowedAddress {
            AutomaticOriginView(address: address)
          } else if !props.draft.rules.isEmpty {
            Text(L10n.string("Domain", locale: locale)).font(.caption).foregroundStyle(.secondary)
          }
          ForEach(props.draft.rules) { rule in
            HStack {
              TextField(
                L10n.string("Domain", locale: locale),
                text: Binding(
                  get: { rule.address }, set: { send(.edit(.originAddress(rule.id, $0))) }),
                prompt: Text("*.example.com")
              )
              .labelsHidden()
              .accessibilityLabel(L10n.string("Domain", locale: locale))
              .accessibilityIdentifier("origin-\(rule.id)")
              .focused($focusedField, equals: .domain(rule.id))
              .submitLabel(.done)
              .onSubmit { focusedField = nil }
              #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
              #endif
              Button(L10n.string("Remove rule", locale: locale), systemImage: "minus.circle") {
                send(.removeOriginRule(rule.id))
              }
              .labelStyle(.iconOnly)
              .accessibilityIdentifier("remove-origin-\(rule.id)")
            }
          }
          Button(L10n.string("Add domain", locale: locale), systemImage: "plus") {
            send(.addOriginRule)
          }
          .accessibilityIdentifier("add-origin")
          Toggle(
            L10n.string("Allow HTTP", locale: locale),
            isOn: value(\.profile.navigation.allowsHTTP, edit: ProfileDraftEdit.allowsHTTP)
          )
          .accessibilityIdentifier("allow-http")
          Label(
            L10n.string(
              "Restrictions apply to the main page only. Images and embedded content are excluded.",
              locale: locale), systemImage: "info.circle"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Section(L10n.string("Interaction and return", locale: locale)) {
          Toggle(
            L10n.string("Allow scrolling", locale: locale),
            isOn: value(\.profile.interaction.allowsScroll, edit: ProfileDraftEdit.allowsScroll)
          )
          .accessibilityIdentifier("allow-scroll")
          Toggle(
            L10n.string("Allow dragging", locale: locale),
            isOn: value(\.profile.interaction.allowsDrag, edit: ProfileDraftEdit.allowsDrag)
          )
          .accessibilityIdentifier("allow-drag")
          #if os(iOS)
            Text(L10n.string("Seconds until idle return", locale: locale)).font(.caption)
              .foregroundStyle(
                .secondary)
          #endif
          TextField(
            L10n.string("Seconds until idle return", locale: locale),
            text: value(\.idleTimeoutText, edit: ProfileDraftEdit.idleTimeoutText)
          )
          .accessibilityIdentifier("idle-seconds")
          .focused($focusedField, equals: .idle)
          .submitLabel(.done)
          .onSubmit { focusedField = nil }
          Picker(
            L10n.string("Site data on return", locale: locale),
            selection: value(\.profile.resetMode, edit: ProfileDraftEdit.resetMode)
          ) {
            Text(L10n.string("New browsing session", locale: locale)).tag(
              ResetMode.newVisitorSession)
            Text(L10n.string("Keep cookies and site data", locale: locale)).tag(
              ResetMode.retainWebsiteData)
          }
        }
        SettingsPasscodeSection(props: props, send: send)
        SettingsInformationSection()
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
      L10n.string("Start URL", locale: locale)
    #endif
  }

  fileprivate func value<Value>(
    _ path: KeyPath<ProfileDraft, Value>, edit: @escaping (Value) -> ProfileDraftEdit
  ) -> Binding<Value> {
    Binding(get: { props.draft[keyPath: path] }, set: { send(.edit(edit($0))) })
  }
}
