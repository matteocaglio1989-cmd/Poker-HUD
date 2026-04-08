// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PokerHUD",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Library product consumed by the Xcode App target wrapper
        // (`PokerHUDApp/PokerHUDApp/PokerHUDApp.xcodeproj`) which
        // provides the archivable `.app` bundle required for Mac App
        // Store submission. The Xcode target imports `PokerHUD` and
        // calls `PokerHUDApp.main()` from a thin entry-point file.
        .library(
            name: "PokerHUD",
            targets: ["PokerHUD"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "PokerHUD",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "Auth", package: "supabase-swift")
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
