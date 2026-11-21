// swift-tools-version:5.10
import PackageDescription

// The app's logic (SMS parsing, categories, safe-to-spend) lives here with no UI,
// so it can be unit-tested with `swift test` and shared by the app, the widget and the App Intent.
let package = Package(
    name: "KhurdaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "KhurdaCore", targets: ["KhurdaCore"])],
    targets: [
        .target(name: "KhurdaCore"),
        .testTarget(name: "KhurdaCoreTests", dependencies: ["KhurdaCore"])
    ]
)
