import Foundation

@MainActor
public final class MonotonicClock: ClockPort {
  public var now: Double { ProcessInfo.processInfo.systemUptime }
  public init() {}
}
