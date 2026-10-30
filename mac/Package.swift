// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SiteLink",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "SiteLink", path: "Sources/SiteLink")]
)
