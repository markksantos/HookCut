// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HookCut",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HookCut", targets: ["HookCut"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "HookCut",
            dependencies: ["WhisperKit"],
            path: "HookCut",
            exclude: ["Info.plist", "HookCut.entitlements"],
            resources: [
                .process("Assets.xcassets"),
                .copy("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
