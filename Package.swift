// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PokerHUD",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PokerHUD",
            targets: ["PokerHUD"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "PokerHUD",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "PokerHUDTests",
            dependencies: ["PokerHUD"]
        )
    ]
)
