import KioskCore
import Testing

struct InputPolicyTests {
  @Test(arguments: [AppMode.safeHold, .enteringKiosk, .exhibiting])
  func administratorEntryRemainsOperableWithoutAWebSurface(_ mode: AppMode) {
    let down = InputPolicy.evaluate(
      .primaryDown, scope: .administratorEntry, mode: mode,
      webAvailable: false, generation: 1, policy: .init(), state: .init())
    #expect(down.passes)
    #expect(!down.recordsVisitorActivity)
    let up = InputPolicy.evaluate(
      .primaryUp, scope: .administratorEntry, mode: mode,
      webAvailable: false, generation: 1, policy: .init(), state: down.state)
    #expect(up.passes)
    #expect(up.state.pressedScope == nil)
    #expect(!up.recordsVisitorActivity)
    let web = InputPolicy.evaluate(
      .primaryDown, scope: .web, mode: mode,
      webAvailable: false, generation: 1, policy: .init(), state: .init())
    #expect(!web.passes)
  }
  @Test func crossingIntoAuthenticationDoesNotForwardOrphanUpOrLeaveWebPressed() {
    let down = InputPolicy.evaluate(
      .primaryDown, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: .init())
    let up = InputPolicy.evaluate(
      .primaryUp, scope: .authentication, mode: .unlocking,
      webAvailable: true, generation: 1, policy: .init(), state: down.state)
    #expect(up.passes == false)
    #expect(up.state.pressedScope == nil)
    #expect(up.state.pressedGeneration == nil)
    let fresh = InputPolicy.evaluate(
      .primaryDown, scope: .authentication, mode: .unlocking,
      webAvailable: true, generation: 1, policy: .init(), state: up.state)
    #expect(fresh.passes)
    #expect(fresh.state.pressedScope == .authentication)
    #expect(fresh.recordsVisitorActivity == false)
  }

  @Test func anotherAdministrationClickWorksWhenAControlConsumesMouseUp() {
    let firstDown = InputPolicy.evaluate(
      .primaryDown, scope: .administration, mode: .administration,
      webAvailable: false, generation: 1, policy: .init(), state: .init())
    let nextDown = InputPolicy.evaluate(
      .primaryDown, scope: .administration, mode: .administration,
      webAvailable: false, generation: 1, policy: .init(), state: firstDown.state)
    let nextUp = InputPolicy.evaluate(
      .primaryUp, scope: .administration, mode: .administration,
      webAvailable: false, generation: 1, policy: .init(), state: nextDown.state)
    #expect(firstDown.passes)
    #expect(nextDown.passes)
    #expect(nextUp.passes)
    #expect(nextUp.state.pressedScope == nil)
  }

  @Test func anotherWebClickWorksInTheSameGenerationWhenMouseUpIsConsumed() {
    let firstDown = InputPolicy.evaluate(
      .primaryDown, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: .init())
    let nextDown = InputPolicy.evaluate(
      .primaryDown, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: firstDown.state)
    let nextUp = InputPolicy.evaluate(
      .primaryUp, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: nextDown.state)
    #expect(firstDown.passes)
    #expect(nextDown.passes)
    #expect(nextUp.passes)
    #expect(nextUp.state.pressedScope == nil)
  }

  struct Case: Sendable {
    let input: NativeInput
    let passes: Bool
  }

  @Test(arguments: [
    Case(input: .cursorMoved, passes: true), Case(input: .primaryDown, passes: true),
    Case(input: .primaryUp, passes: false), Case(input: .primaryDrag, passes: false),
    Case(input: .scroll, passes: false), Case(input: .otherButton, passes: false),
    Case(input: .gesture, passes: false), Case(input: .key, passes: false),
    Case(input: .applicationShortcut, passes: false),
  ])
  func appliesExhibitionDefaults(_ test: Case) {
    let decision = InputPolicy.evaluate(
      test.input, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: .init())
    #expect(decision.passes == test.passes)
    #expect(decision.recordsVisitorActivity == test.passes)
  }

  @Test func holdsPressSequenceAcrossResetWithoutOrphanUp() {
    let down = InputPolicy.evaluate(
      .primaryDown, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: .init())
    #expect(down.passes)
    let secondDown = InputPolicy.evaluate(
      .primaryDown, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 2, policy: .init(), state: down.state)
    #expect(secondDown.passes == false)
    let up = InputPolicy.evaluate(
      .primaryUp, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 2, policy: .init(), state: secondDown.state)
    #expect(up.passes == false)
    #expect(up.state.pressedGeneration == nil)
    let fresh = InputPolicy.evaluate(
      .primaryDown, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 2, policy: .init(), state: up.state)
    #expect(fresh.passes)
  }

  @Test func preservesPairedUpAndScopedAdministratorInput() {
    let up = InputPolicy.evaluate(
      .primaryUp, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: .init(pressedGeneration: 1))
    #expect(up.passes)
    let authentication = InputPolicy.evaluate(
      .key, scope: .authentication, mode: .unlocking,
      webAvailable: true, generation: 1, policy: .init(), state: .init())
    #expect(authentication.passes)
    #expect(authentication.recordsVisitorActivity == false)
    let hiddenWeb = InputPolicy.evaluate(
      .cursorMoved, scope: .web, mode: .unlocking,
      webAvailable: true, generation: 1, policy: .init(), state: .init())
    #expect(hiddenWeb.passes == false)
  }
}
