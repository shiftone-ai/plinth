import KioskCore
import Testing

@testable import KioskPresentation

struct CatalogComparisonTests {
  @Test func sameResolutionWithDifferentPixelAspectRatiosHasDistinctValues() throws {
    let origin = try #require(Origin(urlString: "https://example.com"))
    let current = KioskProfile(
      startURL: "https://example.com/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)]),
      externalDisplayMode: .init(width: 1536, height: 2048, pixelAspectRatio: 1))
    var selected = current
    selected.externalDisplayMode = .init(width: 1536, height: 2048, pixelAspectRatio: 1.25)

    let snapshot = try #require(CatalogSnapshot(selected))
    let differences = CatalogComparison.differences(current: current, selected: snapshot)
    let resolution = try #require(differences.first { $0.labelKey == "Resolution" })
    #expect(resolution.current != resolution.selected)
    guard case .text(let text) = resolution.selected else {
      Issue.record("Expected a visible display mode description")
      return
    }
    #expect(text.contains("1.25"))
  }
}
