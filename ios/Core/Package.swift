// swift-tools-version: 6.2
// Foundation only, so `swift test` runs on macOS. Framework calls (Keychain, UIKit) live in the App target.
import PackageDescription

let package = Package(
    name: "Core",
    // Lower than the app on purpose: the app's deployment target (ios/project.yml) is the one place that decides it.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MimamoriCore", targets: ["MimamoriCore"]),
    ],
    targets: [
        .target(name: "MimamoriCore"),
        .testTarget(name: "MimamoriCoreTests", dependencies: ["MimamoriCore"]),
    ]
)
