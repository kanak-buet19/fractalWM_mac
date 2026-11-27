// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FractalWM",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: no AppKit. Layout tree and layout engine live here.
        .target(name: "FractalCore"),
        // The menu-bar app.
        .executableTarget(name: "FractalWM", dependencies: ["FractalCore"]),
    ]
)
