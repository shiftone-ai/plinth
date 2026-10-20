import Foundation
import KioskCore
import KioskPresentation

public enum RemoteIntentEventMapper {
  public static func event(for intent: SettingsIntent) -> Event? {
    switch intent {
    case .remoteTab(let tab): .remoteTabSelected(tab)
    case .remoteEnabled(let enabled): .remoteEnabledRequested(enabled)
    case .remoteSelectDevice(let id): .remoteDeviceSelected(id)
    case .remoteRefresh: .remoteRefreshRequested
    case .remotePairingCode: .remotePairingCodeRequested
    case .remotePairingInput(let value): .remotePairingCodeEdited(value)
    case .remotePairingRequest: .remotePairingRequestRequested(UUID())
    case .remotePairingApproval(let approved): .remotePairingApprovalRequested(approved)
    case .remoteRevokeController(let id): .remoteControllerRevokeRequested(id)
    case .remoteStatus: .remoteStatusRequested(UUID())
    case .remoteEditOpen: .remoteEditOpened
    case .remoteEditStartURL(let value): .remoteEditChanged(value)
    case .remoteEditDraft(let edit): .remoteEditDraftChanged(edit)
    case .remoteEditAddRule: .remoteEditRuleAdded
    case .remoteEditRemoveRule(let id): .remoteEditRuleRemoved(id)
    case .remoteEditReview: .remoteEditReviewRequested
    case .remoteEditCancel: .remoteEditCancelled
    case .remoteEditSave: .remoteEditSaveRequested(UUID())
    case .remoteExhibitionReview(let action): .remoteExhibitionReviewRequested(action)
    case .remoteExhibitionCancelReview: .remoteExhibitionReviewCancelled
    case .remoteExhibitionRequest(let action): .remoteExhibitionRequested(UUID(), action)
    default: nil
    }
  }
}
