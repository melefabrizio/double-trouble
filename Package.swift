// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "ClaudeLauncher", dependencies: ["LauncherCore"]),
        // Tests as a plain executable: `swift run CoreChecks` (works with Command Line Tools only).
        .executableTarget(name: "CoreChecks", dependencies: ["LauncherCore"]),
    ],
    swiftLanguageModes: [.v5]
)
