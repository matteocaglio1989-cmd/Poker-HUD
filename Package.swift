// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PokerHUD",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "PokerHUD",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "PokerHUD"
        ),
        .testTarget(
            name: "PokerHUDTests",
            dependencies: ["PokerHUD"],
            path: "PokerHUDTests"
        )
    ]
)
