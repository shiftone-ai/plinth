public struct TreeSnapshot: Equatable, Sendable {
  public let root: RootState
  public let exhibition: ExhibitionState
  public let administration: AdministrationState
  public init(root: RootState, exhibition: ExhibitionState, administration: AdministrationState) {
    self.root = root
    self.exhibition = exhibition
    self.administration = administration
  }
}
