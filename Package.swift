// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TmuxIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TmuxIsland", path: "Sources/TmuxIsland")
    ]
)
