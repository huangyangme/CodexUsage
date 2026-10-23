// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexUsage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexUsage", targets: ["CodexUsage"])],
    targets: [.executableTarget(name: "CodexUsage", linkerSettings: [.linkedFramework("AppKit")])]
)
