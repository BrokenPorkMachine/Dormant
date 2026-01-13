// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DormantChat",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DormantChat",
            targets: ["DormantChat"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(
            name: "DormantChat",
            dependencies: [],
            path: "DormantChat",
            exclude: ["DormantChatApp.swift"]
        ),
        .testTarget(
            name: "DormantChatTests",
            dependencies: [
                "DormantChat",
                "SwiftCheck"
            ],
            path: "Tests"
        ),
    ]
)