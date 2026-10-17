import KioskCore

enum CatalogComparison {
  static func differences(current: KioskProfile?, selected: CatalogSnapshot)
    -> [CatalogDifference]
  {
    var values: [CatalogDifference] = []
    append(&values, "Start URL", current?.startURL, selected.startURL) { .text($0) }
    append(&values, "Navigation", current?.navigation.mode, selected.navigation.mode) {
      .localized($0 == .allowlist ? "Allowlist" : "Blocklist")
    }
    append(&values, "Domain", current?.navigation.rules, selected.navigation.rules) {
      .text($0.map(\.inputAddress).joined(separator: ", "))
    }
    append(&values, "Allow HTTP", current?.navigation.allowsHTTP, selected.navigation.allowsHTTP) {
      .localized($0 ? "On" : "Off")
    }
    append(
      &values, "Allow scrolling", current?.interaction.allowsScroll,
      selected.interaction.allowsScroll
    ) {
      .localized($0 ? "On" : "Off")
    }
    append(
      &values, "Allow dragging", current?.interaction.allowsDrag, selected.interaction.allowsDrag
    ) {
      .localized($0 ? "On" : "Off")
    }
    append(&values, "Seconds until idle return", current?.idleTimeout, selected.idleTimeout) {
      .text(String($0))
    }
    append(&values, "Site data on return", current?.resetMode, selected.resetMode) {
      .localized($0 == .newVisitorSession ? "New browsing session" : "Keep cookies and site data")
    }
    append(
      &values, "Retry attempts", current?.recovery.maximumAttempts,
      selected.recovery.maximumAttempts
    ) {
      .text(String($0))
    }
    append(&values, "Retry delay", current?.recovery.delay, selected.recovery.delay) {
      .text(String($0))
    }
    return values + displayDifferences(current: current, selected: selected)
  }

  private static func displayDifferences(current: KioskProfile?, selected: CatalogSnapshot)
    -> [CatalogDifference]
  {
    var values: [CatalogDifference] = []
    append(
      &values,
      "Display destination", current.map { $0.exhibitionDestination ?? .device },
      selected.exhibitionDestination ?? .device
    ) { .localized($0 == .device ? "Device" : "External display") }
    append(
      &values,
      "Mode", current.map { $0.macOutput?.mode ?? .fixedFullscreen },
      selected.macOutput?.mode ?? .fixedFullscreen
    ) {
      .localized($0 == .fixedFullscreen ? "Fixed full screen" : "Window")
    }
    append(
      &values,
      "Display", current.map { $0.macOutput?.displayID ?? "" },
      selected.macOutput?.displayID ?? ""
    ) {
      $0.isEmpty ? .localized("Automatic") : .text($0)
    }
    append(
      &values,
      "Resolution", current.map { $0.externalDisplayMode },
      selected.externalDisplayMode
    ) {
      $0.map {
        let size = "\($0.width) × \($0.height)"
        return .text($0.pixelAspectRatio == 1 ? size : "\(size) @\($0.pixelAspectRatio)")
      } ?? .localized("Automatic")
    }
    append(
      &values,
      "Rotation", current.map { $0.externalDisplayRotation ?? .standard },
      selected.externalDisplayRotation ?? .standard
    ) {
      switch $0 {
      case .standard: .localized("Standard (0°)")
      case .clockwise: .localized("Right 90°")
      case .upsideDown: .text("180°")
      case .counterclockwise: .localized("Left 90°")
      }
    }
    return values
  }

  private static func append<Value: Equatable>(
    _ values: inout [CatalogDifference], _ label: String, _ old: Value?, _ new: Value,
    display: (Value) -> CatalogDisplayValue
  ) {
    if old != new {
      values.append(
        .init(
          labelKey: label, current: old.map(display) ?? .absent, selected: display(new)))
    }
  }

}
