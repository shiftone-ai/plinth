import KioskCore
import KioskLocalization
import KioskPresentation
import SwiftUI

struct RemoteDeviceEditorView: View {
  let props: RemoteManagementProps
  let deviceName: String
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    if let saved = props.selectedSnapshot?.savedProfile {
      Section(L10n.string("Start URL", locale: locale)) {
        LabeledContent(L10n.string("Saved URL", locale: locale), value: saved.startURL)
        LabeledContent(
          L10n.string("Revision", locale: locale),
          value: String(saved.revision))
        if let editing = props.editing {
          if !editing.reviewOpen {
            remoteTextField(
              "Start URL",
              text: Binding(
                get: { editing.draft.profile.startURL },
                set: { send(.remoteEditStartURL($0)) })
            )
            .accessibilityIdentifier("remote-start-url")
          }
        } else {
          Button(L10n.string("Edit settings", locale: locale)) {
            send(.remoteEditOpen)
          }
          .disabled(!props.canEditStartURL)
          .accessibilityIdentifier("remote-edit-start-url")
        }
      }
      if let editing = props.editing, !editing.reviewOpen {
        if let displays = props.selectedSnapshot?.macDisplays {
          Section(L10n.string("Output", locale: locale)) {
            Picker(
              L10n.string("Mode", locale: locale),
              selection: Binding(
                get: { editing.draft.macOutput.mode },
                set: { send(.remoteEditDraft(.macOutputMode($0))) })
            ) {
              Text(L10n.string("Fixed full screen", locale: locale))
                .tag(MacOutputSettings.Mode.fixedFullscreen)
              Text(L10n.string("Window", locale: locale))
                .tag(MacOutputSettings.Mode.projectionWindow)
            }
            if editing.draft.macOutput.mode == .fixedFullscreen {
              Picker(
                L10n.string("Display", locale: locale),
                selection: Binding(
                  get: { editing.draft.macOutput.displayID },
                  set: { send(.remoteEditDraft(.macDisplayID($0))) })
              ) {
                Text(L10n.string("Automatic", locale: locale)).tag(String?.none)
                ForEach(displays) { display in
                  Text(display.name).tag(String?.some(display.id))
                }
              }
            }
          }
        }
        if let mobile = props.selectedSnapshot?.mobileDisplays {
          Section(L10n.string("Display destination", locale: locale)) {
            Picker(
              L10n.string("Display", locale: locale),
              selection: Binding(
                get: {
                  editing.draft.profile.exhibitionDestination == .device
                    ? nil : editing.draft.profile.exhibitionDestination
                },
                set: { send(.remoteEditDraft(.exhibitionDestination($0))) })
            ) {
              Text(L10n.string("Device", locale: locale))
                .tag(ExhibitionDestination?.none)
              if mobile.supportsExternalDisplay && mobile.externalAvailable {
                Text(L10n.string("External display", locale: locale))
                  .tag(ExhibitionDestination?.some(.externalDisplay))
              }
            }
            if editing.draft.profile.exhibitionDestination == .externalDisplay,
              mobile.externalAvailable
            {
              Picker(
                L10n.string("Rotation", locale: locale),
                selection: Binding(
                  get: { editing.draft.externalDisplayRotation },
                  set: { send(.remoteEditDraft(.externalDisplayRotation($0))) })
              ) {
                Text(L10n.string("Standard (0°)", locale: locale))
                  .tag(ExternalDisplayRotation.standard)
                Text(L10n.string("Right 90°", locale: locale))
                  .tag(ExternalDisplayRotation.clockwise)
                Text("180°").tag(ExternalDisplayRotation.upsideDown)
                Text(L10n.string("Left 90°", locale: locale))
                  .tag(ExternalDisplayRotation.counterclockwise)
              }
              if !mobile.displayModes.isEmpty {
                Picker(
                  L10n.string("Resolution", locale: locale),
                  selection: Binding(
                    get: { editing.draft.profile.externalDisplayMode },
                    set: { send(.remoteEditDraft(.externalDisplayMode($0))) })
                ) {
                  Text(L10n.string("Automatic", locale: locale))
                    .tag(ExternalDisplayMode?.none)
                  ForEach(mobile.displayModes) { mode in
                    Text(verbatim: "\(mode.width) × \(mode.height)")
                      .tag(ExternalDisplayMode?.some(mode))
                  }
                }
              }
            }
          }
        }
        Section(L10n.string("Navigation", locale: locale)) {
          Picker(
            L10n.string("Navigation", locale: locale),
            selection: Binding(
              get: { editing.draft.profile.navigation.mode },
              set: { send(.remoteEditDraft(.navigationMode($0))) })
          ) {
            Text(L10n.string("Allowlist", locale: locale))
              .tag(NavigationPolicy.Mode.allowlist)
            Text(L10n.string("Blocklist", locale: locale))
              .tag(NavigationPolicy.Mode.denylist)
          }
          ForEach(editing.draft.rules) { rule in
            HStack {
              remoteTextField(
                "Domain",
                text: Binding(
                  get: { rule.address },
                  set: { send(.remoteEditDraft(.originAddress(rule.id, $0))) })
              )
              .accessibilityIdentifier("remote-origin-\(rule.id)")
              Button(
                L10n.string("Remove rule", locale: locale),
                systemImage: "minus.circle"
              ) {
                send(.remoteEditRemoveRule(rule.id))
              }
              .labelStyle(.iconOnly)
            }
          }
          Button(L10n.string("Add domain", locale: locale), systemImage: "plus") {
            send(.remoteEditAddRule)
          }
          Toggle(
            L10n.string("Allow HTTP", locale: locale),
            isOn: Binding(
              get: { editing.draft.profile.navigation.allowsHTTP },
              set: { send(.remoteEditDraft(.allowsHTTP($0))) }))
        }
        Section(L10n.string("Interaction and return", locale: locale)) {
          Toggle(
            L10n.string("Allow scrolling", locale: locale),
            isOn: Binding(
              get: { editing.draft.profile.interaction.allowsScroll },
              set: { send(.remoteEditDraft(.allowsScroll($0))) }))
          Toggle(
            L10n.string("Allow dragging", locale: locale),
            isOn: Binding(
              get: { editing.draft.profile.interaction.allowsDrag },
              set: { send(.remoteEditDraft(.allowsDrag($0))) }))
          TextField(
            L10n.string("Seconds until idle return", locale: locale),
            text: Binding(
              get: { editing.draft.idleTimeoutText },
              set: { send(.remoteEditDraft(.idleTimeoutText($0))) }))
          Picker(
            L10n.string("Site data on return", locale: locale),
            selection: Binding(
              get: { editing.draft.profile.resetMode },
              set: { send(.remoteEditDraft(.resetMode($0))) })
          ) {
            Text(L10n.string("New browsing session", locale: locale))
              .tag(ResetMode.newVisitorSession)
            Text(L10n.string("Keep cookies and site data", locale: locale))
              .tag(ResetMode.retainWebsiteData)
          }
        }
      }
      if let editing = props.editing {
        Section(L10n.string("Changes", locale: locale)) {
          if editing.reviewOpen {
            LabeledContent(
              L10n.string("Device", locale: locale),
              value: deviceName)
            ForEach(props.reviewDifferences) { difference in
              VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(difference.labelKey, locale: locale))
                  .font(.headline)
                HStack(spacing: 12) {
                  comparisonValue(difference.current)
                  Image(systemName: "arrow.right").accessibilityHidden(true)
                  comparisonValue(difference.selected)
                }
              }
              .accessibilityElement(children: .combine)
            }
            Button(L10n.string("Save on device", locale: locale)) {
              send(.remoteEditSave)
            }
            .disabled(props.savingStartURL)
            .accessibilityIdentifier("remote-save-start-url")
          } else {
            Button(L10n.string("Review change", locale: locale)) {
              send(.remoteEditReview)
            }
            .disabled(!props.canReviewEdit)
          }
          Button(L10n.string("Cancel editing", locale: locale)) {
            send(.remoteEditCancel)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func remoteTextField(_ key: String, text: Binding<String>) -> some View {
    #if os(iOS)
      TextField(L10n.string(key, locale: locale), text: text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    #else
      TextField(L10n.string(key, locale: locale), text: text)
    #endif
  }

  @ViewBuilder
  private func comparisonValue(_ value: CatalogDisplayValue) -> some View {
    switch value {
    case .text(let text): Text(verbatim: text)
    case .localized(let key): Text(L10n.string(key, locale: locale))
    case .absent: Text(verbatim: "—")
    }
  }
}
