import KioskCore

public enum Presenters {
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
      showsPointerSetupHelp: state.mode == .safeHold && state.pointerCaptureFailed)
  }

  public static func settings(_ root: RootState, _ administration: AdministrationState)
    -> SettingsProps
  {
    SettingsProps(
      draft: administration.draft
        ?? ProfileDraft(profile: KioskProfile(startURL: "", navigation: .init(rules: []))),
      passcode: administration.passcode,
      credentialsConfigured: root.credentialsConfigured,
      configuringCredential: root.credentialOperation != nil,
      credentialConfigurationFailed: root.credentialConfigurationFailed,
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
        && administration.hasUnsavedDraft && administration.draft?.validatedProfile != nil,
      canStart: root.mode == .administration && root.credentialsConfigured
        && root.savedProfile.map(root.canPresent) == true
        && !administration.hasUnsavedDraft && root.saveOperation == nil
        && root.credentialOperation == nil
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
      externalDisplayCurrentMode: root.mobileDisplays?.currentMode
    )
  }

  private static func validationMessage(_ issue: ProfileIssue) -> String {
    switch issue {
    case .unsupportedSchema: "設定の形式を読み込めません"
    case .invalidRevision: "設定を読み込めません"
    case .invalidNavigationRules: "ドメインを確認してください"
    case .homeNotAllowed: "開始URLが閲覧先のルールで許可されていません"
    case .invalidIdleTimeout: "無操作の秒数は0より大きい数で入力してください"
    case .invalidRecoveryPolicy: "再試行の回数・間隔を確認してください"
    case .invalidDisplayMode: "解像度を確認してください"
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
      messages.append(.init(id: .invalidRevision, textKey: "設定の保存回数が上限に達しています"))
    }
    return messages
  }

  public static func web(_ root: RootState, _ exhibition: ExhibitionState) -> WebSurfaceProps {
    WebSurfaceProps(
      generation: exhibition.generation,
      acceptsInput: root.mode == .exhibiting && exhibition.inputAvailable,
      phase: exhibition.phase, pageLoad: exhibition.pageLoad)
  }

  public static func unlock(_ administration: AdministrationState, now: Double) -> UnlockProps {
    UnlockProps(
      passcode: administration.passcode,
      failedAttempts: administration.failedAttempts,
      verifying: administration.verification != nil,
      cooldownRemaining: max(0, (administration.cooldownUntil ?? now) - now))
  }
}
