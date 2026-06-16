// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SweepDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SweepDock", targets: ["SweepDock"])
    ],
    targets: [
        .executableTarget(
            name: "SweepDock"
        )
    ]
)
