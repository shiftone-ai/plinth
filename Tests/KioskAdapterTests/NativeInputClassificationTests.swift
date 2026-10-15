import AppKit
import KioskCore
import KioskMacApp
import KioskRuntime
import Testing

@MainActor
struct NativeInputClassificationTests {
  @Test(arguments: ["a", "c", "v", "x", "z"])
  func editingShortcutsUseCharactersRatherThanUSVirtualKeyPositions(_ character: String) throws {
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: 0, windowNumber: 0, context: nil, characters: character,
        charactersIgnoringModifiers: character, isARepeat: false, keyCode: 42))
    #expect(NativeInputAdapter.classify(event) == .key)
    let administration = InputPolicy.evaluate(
      .key, scope: .administration, mode: .administration,
      webAvailable: false, generation: 1, policy: .init(), state: .init())
    let exhibition = InputPolicy.evaluate(
      .key, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: .init())
    #expect(administration.passes)
    #expect(exhibition.passes == false)
  }

  @Test func controlClickCannotBecomeAPrimaryButtonSequence() throws {
    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero,
        modifierFlags: .control, timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 1, clickCount: 1, pressure: 1))
    let input = NativeInputAdapter.classify(event)
    #expect(input == .otherButton)
    let decision = InputPolicy.evaluate(
      input, scope: .web, mode: .exhibiting,
      webAvailable: true, generation: 1, policy: .init(), state: .init())
    #expect(decision.passes == false)
    #expect(decision.state.pressedGeneration == nil)
  }
}
