import KioskCore
import KioskLocalization
import KioskPresentation
import SwiftUI

struct SettingsRemoteManagementSection: View {
  let props: RemoteManagementProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    Section(L10n.string("Remote management", locale: locale)) {
      Toggle(
        L10n.string("Allow remote management", locale: locale),
        isOn: Binding(
          get: { props.thisDeviceEnabled },
          set: { send(.remoteEnabled($0)) })
      )
      .disabled(!props.canChangeThisDevice)
      .accessibilityIdentifier("remote-management-enabled")
      if props.preferenceFailed {
        Label(
          L10n.string("Could not change remote management", locale: locale),
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.red)
      }
      if props.thisDeviceEnabled {
        Button(
          L10n.string("Create registration code", locale: locale),
          systemImage: "number"
        ) {
          send(.remotePairingCode)
        }
        .disabled(!props.canGeneratePairingCode)
        .accessibilityIdentifier("remote-create-code")
        if let code = props.pairingCode {
          LabeledContent(L10n.string("Registration code", locale: locale)) {
            Text(code).font(.system(.title3, design: .monospaced))
              .textSelection(.enabled)
              .accessibilityIdentifier("remote-registration-code")
          }
        }
        if let name = props.incomingPairingName {
          LabeledContent(L10n.string("Access request", locale: locale)) {
            Text(name)
          }
          HStack {
            Button(L10n.string("Deny access", locale: locale)) {
              send(.remotePairingApproval(false))
            }
            Button(L10n.string("Approve access", locale: locale)) {
              send(.remotePairingApproval(true))
            }
            .buttonStyle(.borderedProminent)
          }
          .disabled(props.pairingApprovalPending)
        }
        ForEach(props.approvedControllers) { controller in
          HStack {
            Text(controller.name)
            Spacer()
            Button(
              L10n.string("Revoke access", locale: locale),
              systemImage: "minus.circle"
            ) {
              send(.remoteRevokeController(controller.id))
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel(
              L10n.string("Revoke access", locale: locale) + ": " + controller.name
            )
            .disabled(!props.canRevokeController)
          }
        }
      }
    }
  }
}

struct RemoteDeviceListView: View {
  let props: RemoteManagementProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(L10n.string("Other devices", locale: locale)).font(.title2.bold())
        Spacer()
        Button(L10n.string("Refresh devices", locale: locale), systemImage: "arrow.clockwise") {
          send(.remoteRefresh)
        }
        .labelStyle(.iconOnly)
        .disabled(!props.canRefresh)
        .accessibilityIdentifier("remote-refresh")
      }
      .padding()
      if let selected = props.devices.first(where: { $0.id == props.selectedDeviceID }) {
        Form {
          Section {
            Button(L10n.string("Back to devices", locale: locale), systemImage: "chevron.left") {
              send(.remoteSelectDevice(nil))
            }
            Text(selected.name).font(.title3.bold())
            LabeledContent(L10n.string("Last updated", locale: locale)) {
              Text(selected.updatedAt, format: .dateTime.year().month().day().hour().minute())
            }
            if props.selectedDevicePaired {
              Label(
                L10n.string("Approved", locale: locale),
                systemImage: "checkmark.shield")
              DisclosureGroup(L10n.string("Pair again", locale: locale)) {
                pairingControls
              }
            } else {
              Label(L10n.string("Approval required", locale: locale), systemImage: "lock")
              pairingControls
            }
            if let status = pairingStatusKey {
              Label(
                L10n.string(status, locale: locale),
                systemImage: props.pairingPhase == .approved
                  ? "checkmark.circle" : "clock")
            }
          }
          if props.selectedDevicePaired {
            Section(L10n.string("Exhibition status", locale: locale)) {
              Button(
                L10n.string("Refresh status", locale: locale),
                systemImage: "arrow.clockwise"
              ) {
                send(.remoteStatus)
              }
              .disabled(!props.canRefreshStatus)
              .accessibilityIdentifier("remote-refresh-status")
              if let snapshot = props.selectedSnapshot {
                LabeledContent(
                  L10n.string("Current state", locale: locale),
                  value: L10n.string(stateKey(snapshot.mode), locale: locale))
                LabeledContent(L10n.string("Last checked", locale: locale)) {
                  Text(
                    Date(timeIntervalSince1970: TimeInterval(snapshot.reportedAt)),
                    format: .dateTime.year().month().day().hour().minute())
                }
              }
              if let status = commandStatusKey {
                if props.unknownResultBeforeRefresh {
                  Label(
                    L10n.string("Result unknown", locale: locale),
                    systemImage: "questionmark.circle")
                }
                Label(
                  L10n.string(status, locale: locale),
                  systemImage: props.statusPhase == .processed
                    ? "checkmark.circle" : "clock"
                )
                .accessibilityIdentifier("remote-command-status")
              }
            }
            if !props.availableExhibitionActions.isEmpty {
              Section(L10n.string("Exhibition controls", locale: locale)) {
                ForEach(props.availableExhibitionActions, id: \.self) { action in
                  Button(
                    L10n.string(exhibitionActionKey(action), locale: locale),
                    role: action == .stop ? .destructive : nil
                  ) {
                    if action == .restart || action == .stop {
                      send(.remoteExhibitionReview(action))
                    } else {
                      send(.remoteExhibitionRequest(action))
                    }
                  }
                  .accessibilityIdentifier("remote-exhibition-\(action.rawValue)")
                }
              }
            }
            RemoteDeviceEditorView(
              props: props, deviceName: selected.name, send: send)
          }
        }
        .formStyle(.grouped)
        .confirmationDialog(
          exhibitionReviewTitle(selected.name),
          isPresented: Binding(
            get: { props.exhibitionReviewAction != nil },
            set: { if !$0 { send(.remoteExhibitionCancelReview) } }),
          titleVisibility: .visible
        ) {
          if let action = props.exhibitionReviewAction {
            Button(
              L10n.string(exhibitionActionKey(action), locale: locale),
              role: action == .stop ? .destructive : nil
            ) {
              send(.remoteExhibitionRequest(action))
            }
          }
        }
      } else {
        List {
          switch props.accountStatus {
          case .checking:
            ProgressView(L10n.string("Checking iCloud", locale: locale))
          case .signInRequired:
            Label(
              L10n.string("Sign in to iCloud", locale: locale),
              systemImage: "person.crop.circle.badge.exclamationmark")
          case .offline:
            Label(
              L10n.string("iCloud unavailable", locale: locale),
              systemImage: "wifi.slash")
          case .cloudUnavailable:
            Label(
              L10n.string("iCloud unavailable", locale: locale),
              systemImage: "exclamationmark.icloud")
          case .failed:
            Label(
              L10n.string("Could not load devices", locale: locale),
              systemImage: "exclamationmark.triangle")
          case .ready:
            if props.devices.isEmpty {
              Text(L10n.string("No other devices", locale: locale))
                .foregroundStyle(.secondary)
            }
          }
          ForEach(props.devices) { device in
            Button {
              send(.remoteSelectDevice(device.id))
              if props.pairedDeviceIDs.contains(device.id) { send(.remoteStatus) }
            } label: {
              RemoteDeviceRow(device: device)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("remote-device-\(device.id.uuidString)")
          }
        }
        .accessibilityIdentifier("remote-devices")
      }
    }
  }

  private var pairingControls: some View {
    Group {
      TextField(
        L10n.string("Registration code", locale: locale),
        text: Binding(
          get: { props.pairingInput },
          set: { send(.remotePairingInput($0)) })
      )
      .accessibilityIdentifier("remote-pairing-input")
      #if os(iOS)
        .keyboardType(.numberPad)
      #endif
      Button(L10n.string("Request access", locale: locale)) {
        send(.remotePairingRequest)
      }
      .disabled(!props.canRequestPairing)
      .accessibilityIdentifier("remote-request-access")
    }
  }

  private var pairingStatusKey: String? {
    switch props.pairingPhase {
    case .idle: nil
    case .sending: "Sending request"
    case .awaitingApproval: "Waiting for approval"
    case .storingApproval: "Saving approval"
    case .approved: "Approved"
    case .rejected: "Access denied"
    case .failed: "Could not send request"
    case .unknown: "Result unknown"
    }
  }

  private var commandStatusKey: String? {
    switch props.statusPhase {
    case .idle: nil
    case .sending: "Sending request"
    case .waiting: "Waiting for device"
    case .accepted: "Accepted by device"
    case .applying: "Changing exhibition"
    case .processed:
      props.statusIsAutomaticRefresh
        ? "Status checked"
        : (props.lastCommandWasSave
          ? "Saved on device"
          : props.lastExhibitionAction == .stop
            ? "Exhibition stopped"
            : props.lastExhibitionAction != nil
              ? "Page loaded on device"
              : "Processed on device")
    case .rejected: rejectionKey(props.statusRejection)
    case .failed: "Could not send request"
    case .unknown: "Result unknown"
    }
  }

  private func stateKey(_ mode: AppMode) -> String {
    switch mode {
    case .exhibiting: "Exhibiting"
    case .enteringKiosk: "Changing exhibition"
    case .paused: "Exhibition paused"
    case .administration: "Administration"
    case .bootstrapping, .unlocking, .leavingKiosk: "Changing exhibition"
    case .safeHold, .terminating: "Exhibition stopped"
    }
  }

  private func rejectionKey(_ reason: RemoteCommandRejection?) -> String {
    switch reason {
    case .notAuthorized: "Access denied"
    case .expired: "Result unknown"
    case .duplicate: "Request already handled"
    case .busy: "Device busy"
    case .invalidState: "Operation unavailable"
    case .storageFailed: "Could not save on device"
    case .revisionConflict: "Settings changed on device"
    case .draftConflict: "Unsaved changes on device"
    case .invalidProfile: "Invalid settings"
    case .outputUnavailable: "Output unavailable on device"
    case .webLoadFailed: "Page failed to load on device"
    case nil: "Request rejected"
    }
  }

  private func exhibitionActionKey(_ action: RemoteExhibitionAction) -> String {
    switch action {
    case .start: "Start exhibition"
    case .restart: "Restart exhibition"
    case .stop: "Stop exhibition"
    case .resume: "Resume exhibition"
    }
  }

  private func exhibitionReviewTitle(_ name: String) -> String {
    let key =
      props.exhibitionReviewAction == .stop
      ? "Stop exhibition on %@?" : "Restart exhibition on %@?"
    return String(format: L10n.string(key, locale: locale), name)
  }

}

private struct RemoteDeviceRow: View {
  let device: RemoteDevice

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(device.name)
        Text(device.updatedAt, format: .dateTime.year().month().day().hour().minute())
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}
