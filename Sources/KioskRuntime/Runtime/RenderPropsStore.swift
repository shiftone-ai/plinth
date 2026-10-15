import Observation

@Observable
@MainActor
public final class RenderPropsStore<Props: Equatable & Sendable> {
  public private(set) var props: Props
  public private(set) var revision: UInt64 = 0
  init(_ props: Props) { self.props = props }
  func apply(_ value: Props) {
    guard props != value else { return }
    props = value
    revision += 1
  }
}
