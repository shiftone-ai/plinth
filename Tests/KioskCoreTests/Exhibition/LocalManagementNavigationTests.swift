import KioskCore
import Testing

struct LocalManagementNavigationTests {
  @Test func subframeCannotNavigateToTheDeviceManagementServer() throws {
    var profile = try fixtureProfile()
    profile.navigation.allowsHTTP = true
    let ready = try readyExhibition(profile: profile)
    let loopback = try #require(Origin(urlString: "http://127.0.0.1:47623/"))
    let device = try #require(Origin(urlString: "http://192.0.2.5:47623/"))
    let protected = try #require(
      handled(
        ExhibitionMediator.reduce(
          ready, envelope(.localWebServerOriginsChanged([loopback, device]), source: .root))))
    for address in ["http://127.0.0.1:47623/", "http://192.0.2.5:47623/"] {
      let request = try #require(
        handled(
          ExhibitionMediator.reduce(
            protected.state,
            envelope(
              .navigationRequested(
                url: address, generation: protected.state.generation, mainFrame: false,
                newWindow: false, isGET: true), source: .webSurface))))
      #expect(request.reply == .navigation(.cancel(.urlBlocked)))
    }
    let other = try #require(
      handled(
        ExhibitionMediator.reduce(
          protected.state,
          envelope(
            .navigationRequested(
              url: "http://192.0.2.6:47623/", generation: protected.state.generation,
              mainFrame: false, newWindow: false, isGET: true), source: .webSurface))))
    #expect(other.reply == .navigation(.allow))
  }
}
