#!/bin/bash

# Poker HUD - Xcode Project Setup Script
# This script creates a proper Xcode project for the Poker HUD app

set -e

echo "🎯 Poker HUD - Xcode Project Setup"
echo "==================================="
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: Xcode is not installed or not in PATH"
    echo "Please install Xcode from the App Store"
    exit 1
fi

echo "✅ Xcode found: $(xcodebuild -version | head -n 1)"
echo ""

# Get project directory
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "📁 Project directory: $PROJECT_DIR"
echo ""

# Create Xcode project using swift package
echo "📦 Creating Swift Package structure..."

# Update Package.swift for macOS app
cat > "$PROJECT_DIR/Package.swift" << 'EOF'
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
EOF

echo "✅ Package.swift updated"
echo ""

echo "🔧 Next steps to run in Xcode:"
echo ""
echo "OPTION 1 - Open in Xcode (Recommended for SwiftUI app):"
echo "  1. Open Xcode"
echo "  2. File → New → Project"
echo "  3. Select: macOS → App"
echo "  4. Product Name: PokerHUD"
echo "  5. Interface: SwiftUI"
echo "  6. Language: Swift"
echo "  7. Save location: Select this folder"
echo "  8. Delete auto-generated ContentView.swift"
echo "  9. Add existing PokerHUD folder to project"
echo " 10. Add GRDB.swift package dependency"
echo " 11. Build and Run (⌘R)"
echo ""
echo "OPTION 2 - Use Swift Package Manager (Command-line testing):"
echo "  cd $PROJECT_DIR"
echo "  swift build"
echo "  Note: This won't run the SwiftUI app, but will test compilation"
echo ""

echo "📚 For detailed instructions, see GETTING_STARTED.md"
echo ""
echo "✨ Setup script complete!"
