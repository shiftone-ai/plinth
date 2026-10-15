@MainActor
public protocol ClockPort: AnyObject {
  var now: Double { get }
}
