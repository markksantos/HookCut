// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HookCut",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HookCut", targets: ["HookCut"])
    ],
    targets: [
        .executableTarget(
            name: "HookCut",
            path: "HookCut",
            exclude: ["Info.plist", "HookCut.entitlements"]
        )
    ]
)
