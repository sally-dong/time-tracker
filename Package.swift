// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimeTracker",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TimeTracker", targets: ["TimeTracker"])],
    targets: [
        .target(name: "TrackerCore"),
        .executableTarget(name: "TimeTracker", dependencies: ["TrackerCore"]),
        .executableTarget(name: "TrackerChecks", dependencies: ["TrackerCore"], path: "Tests/TrackerCoreTests")
    ]
)
