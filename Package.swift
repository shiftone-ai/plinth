// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "Plinth",
  platforms: [.macOS(.v14), .iOS("18.4")],
  products: [
    .library(name: "KioskCore", targets: ["KioskCore"]),
    .library(name: "KioskPresentation", targets: ["KioskPresentation"]),
    .library(name: "KioskRuntime", targets: ["KioskRuntime"]),
    .library(name: "KioskUI", targets: ["KioskUI"]),
    .library(name: "KioskMobileApp", targets: ["KioskMobileApp"]),
    .library(name: "KioskMacApp", targets: ["KioskMacApp"]),
    .executable(name: "Plinth", targets: ["Plinth"]),
  ],
  targets: [
    .target(name: "KioskCore"),
    .target(name: "KioskPresentation", dependencies: ["KioskCore"]),
    .target(
      name: "KioskRuntime", dependencies: ["KioskCore", "KioskPresentation"],
      swiftSettings: [.defaultIsolation(MainActor.self)]),
    .target(
      name: "KioskUI", dependencies: ["KioskCore", "KioskPresentation", "KioskRuntime"],
      swiftSettings: [.defaultIsolation(MainActor.self)]),
    .target(
      name: "KioskMobileApp",
      dependencies: ["KioskCore", "KioskPresentation", "KioskRuntime", "KioskUI"],
      swiftSettings: [.defaultIsolation(MainActor.self)]),
    .target(
      name: "KioskMacApp",
      dependencies: ["KioskCore", "KioskPresentation", "KioskRuntime", "KioskUI"],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(name: "KioskCoreTests", dependencies: ["KioskCore"]),
    .testTarget(name: "KioskPresentationTests", dependencies: ["KioskCore", "KioskPresentation"]),
    .testTarget(
      name: "KioskRuntimeTests", dependencies: ["KioskCore", "KioskMacApp", "KioskRuntime"]),
    .testTarget(
      name: "KioskAdapterTests", dependencies: ["KioskCore", "KioskMacApp", "KioskRuntime"]),
    .testTarget(
      name: "KioskNativeTests", dependencies: ["KioskCore", "KioskMacApp", "KioskRuntime"],
      exclude: ["Fixtures/README.md"],
      resources: [.copy("Fixtures/video.mp4")]),
    .executableTarget(
      name: "Plinth", dependencies: ["KioskMacApp"],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
  ],
  swiftLanguageModes: [.v6]
)
