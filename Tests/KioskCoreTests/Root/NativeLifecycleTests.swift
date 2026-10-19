import KioskCore
import Testing

struct NativeLifecycleTests {
  @Test func delayedCredentialSetupWhileBackgroundedWaitsForForeground() throws {
    var state = RootState()
    state.mobileDisplays = .init(deviceAvailable: true, externalAvailable: false)
    state.mode = .administration
    state.savedProfile = try fixtureProfile()
    state.savedProfile?.webAdministrationEnabled = true
    let setup = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(
            .credentialConfigurationRequested("new-passcode"),
            source: .administration))))
    let backgrounded = try #require(
      handled(
        RootMediator.reduce(
          setup.state, envelope(.applicationDeactivated, source: .platform, id: 2))))
    let token = try #require(backgrounded.state.credentialOperation)
    let finished = try #require(
      handled(
        RootMediator.reduce(
          backgrounded.state,
          envelope(.credentialConfigured(token, succeeded: true), source: .credentials, id: 3))))
    #expect(finished.state.webServerOperation == nil)
    let foregrounded = try #require(
      handled(
        RootMediator.reduce(
          finished.state, envelope(.applicationActivated, source: .platform, id: 4))))
    #expect(foregrounded.state.webServerOperation != nil)
  }

  @Test func credentialSetupBlocksStartAndAcceptsOnlyItsOwnResult() throws {
    var state = RootState()
    state.mode = .administration
    state.displayCount = 1
    state.savedProfile = try fixtureProfile()
    let setup = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.credentialConfigurationRequested("staff-passcode"), source: .administration))))
    let token = try requireToken(setup.state.credentialOperation)
    #expect(setup.effects == [Effect(token, .configurePasscode("staff-passcode"))])
    let forged = try #require(
      handled(
        RootMediator.reduce(
          setup.state,
          envelope(.credentialConfigured(token, succeeded: true), source: .webSurface, id: 2))))
    #expect(forged.state == setup.state)
    let success = try #require(
      handled(
        RootMediator.reduce(
          setup.state,
          envelope(.credentialConfigured(token, succeeded: true), source: .credentials, id: 3))))
    #expect(success.state.credentialsConfigured)
    #expect(success.state.credentialOperation == nil)
    #expect(
      success.childControls == [
        .init(.administration, .clearPasscode),
        .init(.administration, .invalidateWebAuthentication),
      ])
  }

  @Test func unlockTimeoutRearmsEarlyNotificationAndInvalidatesDelayedSuccess() throws {
    var state = RootState()
    state.mode = .safeHold
    let opened = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(.unlockRequested, source: .platform, now: 10))))
    #expect(opened.state.unlockDeadline == 70)
    let timer = try requireToken(opened.state.unlockTimeoutOperation)
    let early = try #require(
      handled(
        RootMediator.reduce(
          opened.state,
          envelope(.unlockDeadlineReached(timer), source: .idleClock, id: 2, now: 20))))
    #expect(early.state.mode == .unlocking)
    #expect(early.effects.map(\.kind) == [.scheduleUnlockTimeout(deadline: 70)])
    let rearmed = try requireToken(early.state.unlockTimeoutOperation)
    let expired = try #require(
      handled(
        RootMediator.reduce(
          early.state,
          envelope(.unlockDeadlineReached(rearmed), source: .idleClock, id: 3, now: 70))))
    #expect(expired.state.mode == .safeHold)
    #expect(expired.state.unlockTimeoutOperation == nil)
    #expect(expired.childControls == [.init(.administration, .cancelAuthentication)])
    let late = try #require(
      handled(
        RootMediator.reduce(
          expired.state,
          envelope(.authenticationVerified(unlockID: 1), source: .administration, id: 4, now: 71))))
    #expect(late.reply == .rejected(.staleOperation))
    #expect(late.effects.isEmpty)
  }

  @Test(arguments: [Event.applicationDeactivated, .systemWillSleep, .displayCountChanged(2)])
  func nativeInterruptionStopsExhibitionAndAuthentication(_ event: Event) throws {
    var state = RootState()
    state.mode = .unlocking
    state.unlockID = 5
    state.unlockReturnMode = .exhibiting
    state.presentationAcquired = true
    state.unlockTimeoutOperation = .init(owner: .root, operationID: 5)
    let interrupted = try #require(
      handled(
        RootMediator.reduce(
          state,
          envelope(event, source: .platform, id: 6))))
    #expect(interrupted.state.mode == .safeHold)
    #expect(interrupted.state.presentationAcquired)
    #expect(interrupted.state.unlockTimeoutOperation == nil)
    #expect(
      interrupted.effects.map(\.kind) == [
        .cancelOperation(try requireToken(state.unlockTimeoutOperation))
      ])
    #expect(
      interrupted.childControls == [
        .init(.administration, .cancelAuthentication), .init(.exhibition, .stopExhibition),
      ])
  }

  @Test func failedBootstrapCannotExposeAdministration() throws {
    let initial = try #require(handled(RootMediator.reduce(.init(), envelope(.bootstrapRequested))))
    let token = try requireToken(initial.state.bootstrapOperation)
    #expect(initial.effects.map(\.kind) == [.bootstrap])
    let failed = try #require(
      handled(
        RootMediator.reduce(
          initial.state,
          envelope(
            .bootstrapFailed(
              token, displayCount: 1, credentialsConfigured: true, profileCorrupt: true),
            source: .profileRepository, id: 2))))
    #expect(failed.state.mode == .safeHold)
    #expect(failed.state.bootstrapReadFailed)
    #expect(failed.state.credentialsConfigured)
    #expect(failed.state.profileCorrupt)
    #expect(failed.childControls.isEmpty)
    #expect(failed.state.savedProfile == nil)
  }
}
