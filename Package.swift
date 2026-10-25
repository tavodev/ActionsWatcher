// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ActionsWatcher",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ActionsWatcher", targets: ["ActionsWatcher"])],
    targets: [
        .target(name: "ActionsWatcherCore"),
        .executableTarget(name: "ActionsWatcher", dependencies: ["ActionsWatcherCore"]),
        .testTarget(name: "ActionsWatcherCoreTests", dependencies: ["ActionsWatcherCore"])
    ]
)
