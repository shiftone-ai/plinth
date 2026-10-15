import KioskCore

@MainActor
public final class ComponentNode {
  public let id: NodeID
  public private(set) weak var parent: ComponentNode?
  public private(set) var children: [ComponentNode] = []

  init(id: NodeID) { self.id = id }

  func attach(_ child: ComponentNode) {
    precondition(child.id.parent == id && child.parent == nil)
    child.parent = self
    children.append(child)
  }
}
