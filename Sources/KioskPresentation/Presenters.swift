import Foundation
import KioskCore

public enum Presenters {
  public static func remoteManagement(_ root: RootState) -> RemoteManagementProps {
    let hidden =
      root.remote.installation?.hiddenDeviceIDs(
        for: root.remote.accountIdentifier) ?? []
    let selected = root.remote.devices.first { $0.id == root.remote.selectedDeviceID }
    let grant = selected.flatMap { root.remote.installation?.approvedTargets[$0.id] }
    let paired =
      grant != nil && grant?.accountIdentifier == root.remote.accountIdentifier
      && grant?.signingPublicKey == selected?.signingPublicKey
      && grant?.agreementPublicKey == selected?.agreementPublicKey
    let outgoing = root.remote.pairing.outgoing
    let canManageAccess =
      root.mode == .administration && root.administratorSession
      && root.remote.enabled
    let pairedIDs = Set(
      root.remote.devices.compactMap { device -> UUID? in
        guard let grant = root.remote.installation?.approvedTargets[device.id],
          grant.accountIdentifier == root.remote.accountIdentifier,
          grant.signingPublicKey == device.signingPublicKey,
          grant.agreementPublicKey == device.agreementPublicKey
        else { return nil }
        return device.id
      })
    return RemoteManagementProps(
      accountStatus: root.remote.status,
      selectedTab: root.remote.selectedTab,
      selectedDeviceID: root.remote.selectedDeviceID,
      visibleDevices: root.remote.devices.filter { !hidden.contains($0.id) },
      hiddenDevices: root.remote.devices.filter { hidden.contains($0.id) },
      canRefresh: root.remote.sessionOperation != nil,
      thisDeviceEnabled: root.remote.enabled,
      canChangeThisDevice: root.mode == .administration && root.credentialsConfigured
        && root.administratorSession && root.remote.accountIdentifier != nil
        && root.remote.installation != nil && root.remote.preferenceOperation == nil,
      changingPreference: root.remote.preferenceOperation != nil,
      preferenceFailed: root.remote.preferenceFailed,
      canGeneratePairingCode: canManageAccess
        && root.remote.pairing.codeOperation == nil,
      pairingCode: canManageAccess ? root.remote.pairing.code?.value : nil,
      incomingPairingName: canManageAccess ? root.remote.pairing.incoming?.name : nil,
      pairingApprovalPending: root.remote.pairing.approvalOperation != nil,
      approvedControllers: (root.remote.installation.map {
        Array($0.approvedControllers.values)
      } ?? [])
      .filter { $0.accountIdentifier == root.remote.accountIdentifier }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
      canRevokeController: canManageAccess
        && root.remote.pairing.revocationOperation == nil,
      selectedDevicePaired: paired,
      pairingInput: root.remote.pairing.input,
      canRequestPairing: selected != nil && !paired
        && selected?.signingPublicKey?.count == 32
        && selected?.agreementPublicKey?.count == 32
        && root.remote.pairing.input.utf8.count == 8
        && root.remote.status == .ready
        && ![.sending, .awaitingApproval, .storingApproval]
          .contains(outgoing?.phase ?? .idle),
      pairingPhase: outgoing?.target.id == selected?.id
        ? outgoing?.phase ?? .idle : .idle,
      pairedDeviceIDs: pairedIDs,
      selectedSnapshot: selected.map { pairedIDs.contains($0.id) } == true
        ? root.remote.selectedSnapshot : nil,
      statusPhase: root.remote.outgoingCommand?.targetID == selected?.id
        ? root.remote.outgoingCommand?.phase ?? .idle : .idle,
      statusRejection: root.remote.outgoingCommand?.targetID == selected?.id
        ? root.remote.outgoingCommand?.outcome.flatMap {
          if case .rejected(let reason) = $0 { return reason }
          return nil
        } : nil,
      canRefreshStatus: paired && root.remote.sessionOperation != nil
        && ![.sending, .waiting].contains(
          root.remote.outgoingCommand?.phase ?? .idle),
      canEditStartURL: paired && root.remote.selectedSnapshot?.savedProfile != nil
        && root.remote.outgoingCommand?.phase == .processed,
      editing: root.remote.editing?.targetID == selected?.id ? root.remote.editing : nil,
      canReviewEdit: root.remote.editing?.targetID == selected?.id
        && root.remote.editing?.patch.edits.isEmpty == false
        && root.remote.outgoingCommand?.phase == .processed,
      savingStartURL: root.remote.outgoingCommand.map {
        if case .saveProfile = $0.command {
          return [.sending, .waiting].contains($0.phase)
        }
        return false
      } ?? false,
      lastCommandWasSave: root.remote.outgoingCommand.map {
        if case .saveProfile = $0.command { return true }
        return false
      } ?? false,
      reviewDifferences: root.remote.editing.flatMap { editing -> [CatalogDifference]? in
        guard let base = editing.baseProfile,
          let validated = editing.draft.validatedProfile,
          let selected = CatalogSnapshot(validated)
        else { return nil }
        return CatalogComparison.differences(current: base, selected: selected)
      } ?? [],
      availableExhibitionActions: {
        guard paired, root.remote.status == .ready,
          root.remote.sessionOperation != nil,
          ![.sending, .waiting].contains(
            root.remote.outgoingCommand?.phase ?? .idle),
          let mode = root.remote.selectedSnapshot?.mode
        else { return [] }
        switch mode {
        case .administration: return [.start]
        case .exhibiting: return [.restart, .stop]
        case .paused, .safeHold: return [.resume]
        default: return []
        }
      }(),
      exhibitionReviewAction: root.remote.exhibitionReviewAction)
  }

  public static func webAdministration(
    _ root: RootState, _ administration: AdministrationState
  ) -> WebAdministrationProps {
    WebAdministrationProps(
      mode: root.mode, savedProfile: root.savedProfile,
      draft: administration.draft, saving: administration.saving,
      saveFailed: administration.saveFailed,
      canSave: [.administration, .exhibiting, .paused, .safeHold].contains(root.mode)
        && !administration.saving
        && ProfileRevision.next(after: root.savedProfile?.revision) != nil
        && administration.hasUnsavedDraft && administration.draft?.validatedProfile != nil,
      validationMessages: settingsValidation(root, administration),
      hasUnsavedDraft: administration.hasUnsavedDraft,
      webRestartFailed: root.webRestartFailed,
      macDisplays: root.macDisplays,
      mobileOutputAvailable: root.mobileDisplays != nil,
      supportsExternalDisplay: root.mobileDisplays?.supportsExternalDisplay == true,
      externalDisplayModes: root.mobileDisplays?.displayModes ?? [],
      showsExhibitionWindowPreparation:
        root.mobileDisplays?.canPrepareExhibitionWindow == true)
  }

  public static func root(_ state: RootState) -> RootProps {
    RootProps(
      mode: state.mode, showsAdministration: state.mode == .administration,
      showsUnlock: state.mode == .unlocking,
      exhibitionDestination: state.activeProfile?.exhibitionDestination ?? .device,
      administrationAvailable: state.mobileDisplays?.deviceAvailable ?? true,
      externalDisplayOnly: state.mobileDisplays?.externalDisplayOnly == true,
      externalDisplayRotation: state.activeProfile?.exhibitionDestination == .externalDisplay
        ? state.activeProfile?.externalDisplayRotation ?? .standard : .standard,
      externalPointer: state.mode == .exhibiting ? state.externalPointer : nil,
      externalAllowsDrag: state.activeProfile?.interaction.allowsDrag == true,
      externalPointerLocked: state.externalPointerLocked,
      showsPointerSetupHelp: state.mode == .safeHold && state.pointerCaptureFailed,
      webServerURL: state.webServerRunning && state.savedProfile?.webAdministrationEnabled == true
        ? state.webServerURL : nil)
  }

  public static func settings(_ root: RootState, _ administration: AdministrationState)
    -> SettingsProps
  {
    SettingsProps(
      catalog: catalog(root, administration),
      draft: administration.draft
        ?? ProfileDraft(profile: KioskProfile(startURL: "", navigation: .init(rules: []))),
      passcode: administration.passcode,
      credentialsConfigured: root.credentialsConfigured,
      configuringCredential: root.credentialOperation != nil,
      credentialConfigurationFailed: root.credentialConfigurationFailed,
      biometricLabelKey: biometricLabel(root.biometricStatus),
      biometricUnavailableKey: biometricUnavailable(root.biometricStatus),
      biometricEnabled: root.biometricStatus?.enabled == true,
      biometricChanging: root.biometricOperation != nil,
      canChangeBiometric: canChangeBiometric(root),
      biometricChangeFailed: root.biometricChangeFailed,
      biometricEnrollmentChanged: root.biometricEnrollmentChanged,
      saveFailed: administration.saveFailed,
      validationMessages: settingsValidation(root, administration),
      startURL: administration.draft?.profile.startURL ?? "",
      automaticallyAllowedAddress: administration.draft?.profile.automaticallyAllowedOrigin.map {
        let defaultPort = $0.scheme == "https" ? 443 : 80
        return $0.port == defaultPort
          ? String($0.urlString.dropLast(":\($0.port)".count)) : $0.urlString
      },
      idleTimeout: administration.draft?.idleTimeoutText ?? "",
      canSave: root.mode == .administration && !administration.saving
        && ProfileRevision.next(after: root.savedProfile?.revision) != nil
        && administration.hasUnsavedDraft && administration.draft?.validatedProfile != nil
        && (!administration.catalogRequiresAvailableOutput
          || administration.draft?.validatedProfile.map(root.canPresent) == true),
      catalogOutputUnavailable: administration.catalogRequiresAvailableOutput
        && administration.draft?.validatedProfile.map { !root.canPresent($0) } == true,
      canStart: root.mode == .administration && root.credentialsConfigured
        && root.savedProfile.map(root.canPresent) == true
        && !administration.hasUnsavedDraft && root.saveOperation == nil
        && root.credentialOperation == nil && root.biometricOperation == nil
        && root.externalSceneOperation == nil
        && root.savedProfile?.validationIssues.isEmpty == true,
      saving: administration.saving,
      canPrepareExternalScene: root.mode == .administration
        && root.mobileDisplays?.canPrepareExhibitionWindow == true
        && root.externalSceneOperation == nil,
      externalScenePreparationFailed: root.externalScenePreparationFailed,
      macDisplays: root.macDisplays,
      showsExhibitionWindowPreparation: root.mobileDisplays?.canPrepareExhibitionWindow == true,
      supportsExternalDisplay: root.mobileDisplays?.supportsExternalDisplay == true,
      externalDisplayModes: root.mobileDisplays?.displayModes ?? [],
      externalDisplayCurrentMode: root.mobileDisplays?.currentMode,
      webServerURL: root.webServerURL,
      webServerFailure: root.webServerFailure,
      licenseSheetPresented: root.licenseSheetPresented
    )
  }

  private static func biometricLabel(_ status: BiometricStatus?) -> String {
    switch status?.availability {
    case .available(.faceID): "Unlock with Face ID"
    case .available(.touchID): "Unlock with Touch ID"
    default: "Biometric unlock"
    }
  }

  private static func biometricUnavailable(_ status: BiometricStatus?) -> String? {
    switch status?.availability {
    case nil: "Checking biometrics"
    case .available: nil
    case .unavailable(.notAvailable): "Biometrics are not available on this device"
    case .unavailable(.notEnrolled): "Set up Face ID or Touch ID on this device first"
    case .unavailable(.lockedOut): "Biometrics are locked. Unlock the device and try again"
    case .unavailable(.passcodeNotSet): "Set a device passcode to use biometrics"
    case .unavailable(.storageUnavailable): "Biometric settings are unavailable"
    case .unavailable(.disconnected): "Touch ID keyboard is disconnected"
    case .unavailable(.notPaired): "Touch ID keyboard is not paired"
    }
  }

  private static func canChangeBiometric(_ root: RootState) -> Bool {
    guard root.mode == .administration, root.credentialsConfigured,
      root.biometricOperation == nil, let status = root.biometricStatus
    else { return false }
    if status.enabled { return true }
    if case .available = status.availability { return true }
    return false
  }

  private static func validationMessage(_ issue: ProfileIssue) -> String {
    switch issue {
    case .unsupportedSchema: "Could not read the settings format"
    case .invalidRevision: "Could not read settings"
    case .invalidNavigationRules: "Check the domain"
    case .homeNotAllowed: "The start URL is not allowed by the navigation rules"
    case .invalidIdleTimeout: "Enter an idle time greater than zero"
    case .invalidRecoveryPolicy: "Check retry count and interval"
    case .invalidDisplayMode: "Check the resolution"
    }
  }

  private static func settingsValidation(_ root: RootState, _ administration: AdministrationState)
    -> [SettingsValidationMessage]
  {
    var messages = (administration.draft?.validationIssues ?? []).map {
      SettingsValidationMessage(id: $0, textKey: validationMessage($0))
    }
    if ProfileRevision.next(after: root.savedProfile?.revision) == nil {
      messages.removeAll { $0.id == .invalidRevision }
      messages.append(.init(id: .invalidRevision, textKey: "Settings have reached the save limit"))
    }
    return messages
  }

  public static func web(_ root: RootState, _ exhibition: ExhibitionState) -> WebSurfaceProps {
    WebSurfaceProps(
      generation: exhibition.generation,
      acceptsInput: root.mode == .exhibiting && exhibition.inputAvailable,
      phase: exhibition.phase, pageLoad: exhibition.pageLoad)
  }

  public static func unlock(
    _ root: RootState, _ administration: AdministrationState, now: Double
  ) -> UnlockProps {
    let biometricLabelKey: String?
    if root.biometricStatus?.enabled == true {
      switch root.biometricStatus?.availability {
      case .available(.faceID): biometricLabelKey = "Unlock with Face ID"
      case .available(.touchID): biometricLabelKey = "Unlock with Touch ID"
      default: biometricLabelKey = nil
      }
    } else {
      biometricLabelKey = nil
    }
    return UnlockProps(
      passcode: administration.passcode,
      failedAttempts: administration.failedAttempts,
      verifying: administration.verification != nil,
      cooldownRemaining: max(0, (administration.cooldownUntil ?? now) - now),
      biometricLabelKey: biometricLabelKey,
      biometricVerifying: root.biometricUnlockOperation != nil,
      biometricFailed: root.biometricUnlockFailed)
  }
}
