// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "NotchShot",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "NotchShot", targets: ["NotchShot"])],
    targets: [
        .executableTarget(name: "NotchShot", resources: [.process("Resources")]),
        .testTarget(name: "NotchShotTests", dependencies: ["NotchShot"])
    ],
    swiftLanguageModes: [.v5]
)
