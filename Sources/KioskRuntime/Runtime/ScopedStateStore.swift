import KioskCore

@MainActor
final class ScopedStateStore {
  var root = RootState()
  var exhibition = ExhibitionState()
  var administration = AdministrationState()

  var snapshot: TreeSnapshot {
    TreeSnapshot(root: root, exhibition: exhibition, administration: administration)
  }

  var context: ReadonlyContext {
    ReadonlyContext(
      webAvailable: exhibition.inputAvailable, webGeneration: exhibition.generation,
      hasUnsavedDraft: administration.hasUnsavedDraft,
      catalogSelectionID: administration.catalogSelection?.id,
      catalogRequiresAvailableOutput: administration.catalogRequiresAvailableOutput)
  }
}
