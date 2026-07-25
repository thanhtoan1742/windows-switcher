// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowsSwitcher",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "WindowsSwitcherCore",
            path: "Sources/WindowsSwitcherCore"
        ),
        .executableTarget(
            name: "WindowsSwitcher",
            dependencies: ["WindowsSwitcherCore"],
            path: "Sources/WindowsSwitcher"
        ),
        .testTarget(
            name: "WindowsSwitcherTests",
            dependencies: ["WindowsSwitcherCore"],
            path: "Tests/WindowsSwitcherTests"
        )
    ]
)
