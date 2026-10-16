import KioskCore
import KioskLocalization
import KioskPresentation
import SwiftUI

struct SettingsOutputSection: View {
  let props: SettingsProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    Group {
      #if os(macOS)
        Section(L10n.string("Output", locale: locale)) {
          unavailableCatalogOutputNotice
          Picker(
            L10n.string("Mode", locale: locale),
            selection: value(\.macOutput.mode, edit: ProfileDraftEdit.macOutputMode)
          ) {
            Text(L10n.string("Fixed full screen", locale: locale)).tag(
              MacOutputSettings.Mode.fixedFullscreen)
            Text(L10n.string("Window", locale: locale)).tag(
              MacOutputSettings.Mode.projectionWindow
            ).accessibilityIdentifier("mac-output-projection-window")
          }
          .accessibilityIdentifier("mac-output-mode")
          if props.draft.macOutput.mode == .fixedFullscreen {
            Picker(
              L10n.string("Display", locale: locale),
              selection: value(\.macOutput.displayID, edit: ProfileDraftEdit.macDisplayID)
            ) {
              Text(L10n.string("Automatic", locale: locale)).tag(String?.none)
              ForEach(props.macDisplays ?? []) { display in
                Text(display.name).tag(String?.some(display.id))
              }
              if let id = props.draft.macOutput.displayID,
                props.macDisplays?.contains(where: { $0.id == id }) != true
              {
                Text(L10n.string("Disconnected display", locale: locale)).tag(String?.some(id))
              }
            }
            .accessibilityIdentifier("mac-output-display")
          }
        }
      #endif
      #if os(iOS)
        Section(L10n.string("Display destination", locale: locale)) {
          unavailableCatalogOutputNotice
          Picker(
            L10n.string("Display", locale: locale),
            selection: value(
              \.profile.exhibitionDestination, edit: ProfileDraftEdit.exhibitionDestination)
          ) {
            Text(L10n.string("Device", locale: locale)).tag(ExhibitionDestination?.none)
              .accessibilityIdentifier("exhibition-destination-device")
            Text(L10n.string("External display", locale: locale)).tag(
              ExhibitionDestination?.some(.externalDisplay)
            )
            .accessibilityIdentifier("exhibition-destination-external")
            .disabled(!props.supportsExternalDisplay)
          }
          .accessibilityIdentifier("exhibition-destination")
          if props.draft.profile.exhibitionDestination == .externalDisplay {
            Picker(
              L10n.string("Rotation", locale: locale),
              selection: value(
                \.externalDisplayRotation, edit: { .externalDisplayRotation($0) })
            ) {
              Text(L10n.string("Standard (0°)", locale: locale)).tag(
                ExternalDisplayRotation.standard)
              Text(L10n.string("Right 90°", locale: locale)).tag(
                ExternalDisplayRotation.clockwise
              )
              .accessibilityIdentifier("external-display-rotation-clockwise")
              Text("180°").tag(ExternalDisplayRotation.upsideDown)
              Text(L10n.string("Left 90°", locale: locale)).tag(
                ExternalDisplayRotation.counterclockwise)
            }
            .accessibilityIdentifier("external-display-rotation")
          }
          if props.draft.profile.exhibitionDestination == .externalDisplay,
            !props.externalDisplayModes.isEmpty || props.draft.profile.externalDisplayMode != nil
          {
            Picker(
              L10n.string("Resolution", locale: locale),
              selection: value(
                \.profile.externalDisplayMode, edit: ProfileDraftEdit.externalDisplayMode)
            ) {
              Text(L10n.string("Automatic", locale: locale)).tag(ExternalDisplayMode?.none)
              ForEach(props.externalDisplayModes) { mode in
                Text(verbatim: "\(mode.width) × \(mode.height)").tag(
                  ExternalDisplayMode?.some(mode)
                ).accessibilityIdentifier("external-display-mode-\(mode.width)x\(mode.height)")
              }
              if let mode = props.draft.profile.externalDisplayMode,
                !props.externalDisplayModes.contains(mode)
              {
                Text(
                  verbatim:
                    "\(mode.width) × \(mode.height) \(L10n.string("Disconnected", locale: locale))"
                ).tag(
                  ExternalDisplayMode?.some(mode))
              }
            }
            .accessibilityIdentifier("external-display-mode")
          }
          if props.draft.profile.exhibitionDestination == .externalDisplay
            && props.showsExhibitionWindowPreparation
          {
            Button(L10n.string("Open exhibition window", locale: locale), systemImage: "display") {
              send(.prepareExternalScene)
            }
            .disabled(!props.canPrepareExternalScene)
            .accessibilityIdentifier("prepare-external-scene")
            if props.externalScenePreparationFailed {
              Label(
                L10n.string("Could not open exhibition window", locale: locale),
                systemImage: "exclamationmark.circle"
              )
              .foregroundStyle(.red)
            }
          }
        }
      #endif
    }
  }

  @ViewBuilder
  private var unavailableCatalogOutputNotice: some View {
    if props.catalogOutputUnavailable {
      Label(
        L10n.string("Choose an available output before saving", locale: locale),
        systemImage: "exclamationmark.circle"
      )
      .foregroundStyle(.orange)
    }
  }

  private func value<Value>(
    _ path: KeyPath<ProfileDraft, Value>, edit: @escaping (Value) -> ProfileDraftEdit
  ) -> Binding<Value> {
    Binding(get: { props.draft[keyPath: path] }, set: { send(.edit(edit($0))) })
  }
}
