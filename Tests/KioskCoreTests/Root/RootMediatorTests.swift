import Foundation
import KioskCore
import Testing

struct RootMediatorTests {
  @Test func informationPagesOpenOnlyFromAdministration() throws {
    var state = RootState()
    state.mode = .administration
    let request = envelope(
      .openInformationPageRequested(.privacy, locale: "zh-Hant"), source: .settings)
    let accepted = try #require(handled(RootMediator.reduce(state, request)))
    #expect(accepted.reply == .accepted)
    #expect(accepted.state.informationPageOperation == accepted.effects.first?.token)
    #expect(accepted.effects.map(\.kind) == [.openInformationPage(.privacy, locale: "zh-Hant")])

    let forged = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.openInformationPageRequested(.support, locale: "en"), source: .webSurface))))
    #expect(forged.reply == .rejected(.wrongSource))
    #expect(forged.effects.isEmpty)

    state.mode = .exhibiting
    let unavailable = try #require(handled(RootMediator.reduce(state, request)))
    #expect(unavailable.reply == .rejected(.invalidState))
    #expect(unavailable.effects.isEmpty)
  }

  @Test func openingInformationPageIsCancelledWhenExhibitionStarts() throws {
    var state = RootState()
    state.mode = .administration
    state.savedProfile = try fixtureProfile()
    state.credentialsConfigured = true
    let opened = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.openInformationPageRequested(.privacy, locale: "en"), source: .settings))
      ))
    let operation = try requireToken(opened.state.informationPageOperation)

    let started = try #require(
      handled(
        RootMediator.reduce(
          opened.state, envelope(.startExhibitionRequested, source: .settings, id: 2))))
    #expect(started.state.mode == .enteringKiosk)
    #expect(started.state.informationPageOperation == nil)
    #expect(started.effects.map(\.kind).contains(.cancelOperation(operation)))
  }

  @Test func licenseSheetIsRootOwnedAndClosesOnExhibitionStart() throws {
    var state = RootState()
    state.mode = .administration
    state.savedProfile = try fixtureProfile()
    state.credentialsConfigured = true
    let opened = try #require(
      handled(
        RootMediator.reduce(state, envelope(.openLicensesRequested, source: .settings))))
    #expect(opened.state.licenseSheetPresented)
    let closed = try #require(
      handled(
        RootMediator.reduce(
          opened.state, envelope(.closeLicensesRequested, source: .settings, id: 2))))
    #expect(!closed.state.licenseSheetPresented)
    let started = try #require(
      handled(
        RootMediator.reduce(
          opened.state, envelope(.startExhibitionRequested, source: .settings, id: 3))))
    #expect(!started.state.licenseSheetPresented)
  }

  @Test func missingProfileWithExistingCredentialsRequiresAuthentication() throws {
    let value = try #require(
      handled(
        RootMediator.reduce(
          .init(),
          envelope(
            .bootstrapped(profile: nil, credentialsConfigured: true, displayCount: 1)))))
    #expect(value.state.mode == .safeHold)
    #expect(value.childControls.isEmpty)
  }

  @Test func cancelledAcquisitionStillReleasesPossiblePresentationResources() throws {
    let begin = try #require(
      handled(
        RootMediator.reduce(
          .init(),
          envelope(
            .bootstrapped(
              profile: try fixtureProfile(), credentialsConfigured: true, displayCount: 1)))))
    let acquiredToken = try requireToken(begin.state.presentationOperation)
    let changed = try #require(
      handled(
        RootMediator.reduce(
          begin.state,
          envelope(.displayCountChanged(2), source: .platform, id: 2))))
    #expect(changed.state.mode == .safeHold)
    #expect(changed.state.presentationOperation == nil)
    #expect(changed.state.presentationAcquisition == acquiredToken)
    let late = try #require(
      handled(
        RootMediator.reduce(
          changed.state,
          envelope(.presentationApplied(acquiredToken), source: .platform, id: 3))))
    #expect(late.state.mode == .safeHold)
    #expect(late.state.presentationAcquired)
    #expect(late.childControls.isEmpty)
    var leaving = changed.state
    leaving.mode = .leavingKiosk
    let stop = try #require(
      handled(
        RootMediator.reduce(
          leaving,
          envelope(.exhibitionStopped, source: .exhibition, id: 4))))
    #expect(stop.effects.map(\.kind) == [.releasePresentation])
  }

  @Test func forgedPresentationCompletionCannotAcquireResources() throws {
    let begin = try #require(
      handled(
        RootMediator.reduce(
          .init(),
          envelope(
            .bootstrapped(
              profile: try fixtureProfile(), credentialsConfigured: true, displayCount: 1)))))
    let token = try requireToken(begin.state.presentationOperation)
    let forged = try #require(
      handled(
        RootMediator.reduce(
          begin.state,
          envelope(.presentationApplied(token), source: .webSurface, id: 2))))
    #expect(forged.reply == .rejected(.wrongSource))
    #expect(forged.state == begin.state)
    #expect(forged.childControls.isEmpty)
  }

  @Test func bootstrappingCapturesProfileBeforePresentation() throws {
    let profile = try fixtureProfile()
    let value = try #require(
      handled(
        RootMediator.reduce(
          .init(),
          envelope(
            .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1)))))
    #expect(value.state.mode == .enteringKiosk)
    #expect(value.state.activeProfile == profile)
    #expect(value.effects.map(\.kind) == [.applyPresentation(.init()), .readBiometricStatus])
    #expect(value.childControls == [.init(.administration, .initializeWebDraft(profile))])
    let token = try requireToken(value.state.presentationOperation)
    let applied = try #require(
      handled(
        RootMediator.reduce(
          value.state,
          envelope(.presentationApplied(token), source: .platform, id: 2))))
    #expect(applied.state.presentationAcquired)
    #expect(applied.childControls == [.init(.exhibition, .activateExhibition(profile))])
  }

  @Test(arguments: [0])
  func unsupportedDisplaysStayInSafeHold(_ count: Int) throws {
    let result = try #require(
      handled(
        RootMediator.reduce(
          .init(),
          envelope(
            .bootstrapped(
              profile: try fixtureProfile(), credentialsConfigured: true, displayCount: count)))))
    #expect(result.state.mode == .safeHold)
    #expect(result.effects.map(\.kind) == [.readBiometricStatus])
  }

  @Test func rejectsWebForgedAdministrativeEvents() throws {
    var state = RootState()
    state.mode = .unlocking
    state.unlockID = 4
    state.presentationAcquired = true
    let result = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.authenticationVerified(unlockID: 4), source: .webSurface))))
    #expect(result.state == state)
    #expect(result.reply == .rejected(.wrongSource))
    #expect(result.effects.isEmpty)
  }

  @Test func lateAuthenticationCannotUnlockAfterCancellation() throws {
    var state = RootState()
    state.mode = .unlocking
    state.unlockID = 4
    state.unlockReturnMode = .safeHold
    let cancelled = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.unlockCancelled, source: .administration))))
    let late = try #require(
      handled(
        RootMediator.reduce(
          cancelled.state,
          envelope(.authenticationVerified(unlockID: 4), source: .administration, id: 2))))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.state.mode == .safeHold)
    #expect(late.effects.isEmpty)
  }

  @Test func unsavedDraftAndAuthenticationGuardExhibitionStart() throws {
    var state = RootState()
    state.mode = .administration
    state.savedProfile = try fixtureProfile()
    state.credentialsConfigured = true
    let value = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.startExhibitionRequested, source: .settings),
          context: .init(hasUnsavedDraft: true))))
    #expect(value.reply == .rejected(.unsavedDraft))
    #expect(value.state.activeProfile == nil)
    #expect(value.effects.isEmpty)
    state.credentialsConfigured = false
    let unconfigured = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.startExhibitionRequested, source: .settings))))
    #expect(unconfigured.reply == .rejected(.unauthenticated))
  }

  @Test func failedAcquisitionDoesNotReleaseUnacquiredResources() throws {
    let begin = try #require(
      handled(
        RootMediator.reduce(
          .init(),
          envelope(
            .bootstrapped(
              profile: try fixtureProfile(), credentialsConfigured: true, displayCount: 1)))))
    let failure = try #require(
      handled(
        RootMediator.reduce(
          begin.state,
          envelope(
            .presentationFailed(try requireToken(begin.state.presentationOperation)),
            source: .platform, id: 2))))
    #expect(failure.state.mode == .safeHold)
    #expect(failure.state.presentationAcquired == false)
    #expect(failure.effects.isEmpty)
  }
}
