# Getting Started with Poker HUD

This guide will help you set up and run the Poker HUD application from scratch.

## Prerequisites

Before you begin, ensure you have:
- **macOS 14.0 (Sonoma)** or later
- **Xcode 15.0** or later (available from the Mac App Store)
- **Git** (comes with Xcode Command Line Tools)

## Step-by-Step Setup

### 1. Install Xcode and Command Line Tools

1. Install Xcode from the Mac App Store
2. Open Terminal and install Command Line Tools:
```bash
xcode-select --install
```

### 2. Clone the Repository

```bash
cd ~/Desktop/Code
git clone https://github.com/matteocaglio1989-cmd/Poker-HUD.git
cd Poker-HUD
```

### 3. Create an Xcode Project

Since the code files are already created, you need to set up an Xcode project:

#### Option A: Using Xcode GUI (Recommended for beginners)

1. **Open Xcode**
2. **File → New → Project**
3. Select **macOS** tab
4. Choose **App** template
5. Click **Next**
6. Configure your project:
   - **Product Name:** `PokerHUD`
   - **Team:** Select your team or None
   - **Organization Identifier:** `com.pokerhud`
   - **Bundle Identifier:** `com.pokerhud.PokerHUD`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Storage:** None
   - Uncheck "Use Core Data"
   - Uncheck "Include Tests" (we'll add our custom tests)
7. Click **Next**
8. Save it in the existing `Poker-HUD` directory (replace the folder if prompted)

#### Option B: Manual Setup (Advanced)

Create an Xcode project file structure manually or use the provided files.

### 4. Add Source Files to Xcode

1. In Xcode, **right-click on the PokerHUD folder** in the Project Navigator
2. Select **Add Files to "PokerHUD"...**
3. Navigate to your cloned repository
4. Select all the source folders:
   - `PokerHUD/App`
   - `PokerHUD/Models`
   - `PokerHUD/Database`
   - `PokerHUD/Parsers`
   - `PokerHUD/Engine`
   - `PokerHUD/Views`
5. Make sure **"Copy items if needed"** is UNCHECKED (since files are already in the right place)
6. Click **Add**

### 5. Add GRDB.swift Dependency

1. In Xcode, select your project in the navigator
2. Select the **PokerHUD** target
3. Go to the **General** tab
4. Scroll to **Frameworks, Libraries, and Embedded Content**
5. Click the **+** button
6. Click **Add Package Dependency...**
7. Enter the URL: `https://github.com/groue/GRDB.swift`
8. Set **Dependency Rule** to: **Up to Next Major Version** (7.0.0)
9. Click **Add Package**
10. Ensure GRDB is checked in the next dialog
11. Click **Add Package**

### 6. Configure Build Settings

1. Select your project in the navigator
2. Select the **PokerHUD** target
3. Go to **Build Settings**
4. Search for **"Minimum Deployment"**
5. Set **macOS Deployment Target** to **14.0**

### 7. Add Info.plist (if needed)

If Xcode created a default Info.plist, replace it with the one from this repository at `PokerHUD/Info.plist`.

### 8. Build the Project

1. Select **Product → Build** (⌘B)
2. Wait for dependencies to download and the project to compile
3. Fix any build errors if they appear (usually related to missing imports or file paths)

### 9. Run the Application

1. Select **Product → Run** (⌘R)
2. The Poker HUD app should launch

## First-Time Usage

### Importing Sample Data

1. When the app launches, you'll see the **Dashboard**
2. Click the **"Import Hands"** button
3. Navigate to `SampleData/sample_pokerstars.txt` in your project folder
4. Select the file and click **Open**
5. The app will import the sample hands
6. You should see:
   - Total Hands count increase
   - Recent hands appear in the list

### Viewing Statistics

1. Click on **"Reports"** in the sidebar
2. You'll see player statistics including:
   - Player names
   - Hands played
   - VPIP, PFR, 3-Bet %
   - Aggression Factor
   - WTSD, W$SD
   - BB/100
   - Player Type classification

### Exploring the App

- **Dashboard:** Overview and import functionality
- **Reports:** Detailed player statistics
- **Opponents:** (Coming in Phase 3)
- **Hand Replayer:** (Coming in Phase 4)
- **Settings:** Configure poker sites and database

## Common Issues & Solutions

### Issue: Build fails with "No such module 'GRDB'"

**Solution:**
1. Go to **File → Packages → Reset Package Caches**
2. Go to **File → Packages → Update to Latest Package Versions**
3. Clean the build folder: **Product → Clean Build Folder** (⌘⇧K)
4. Rebuild the project

### Issue: "Cannot find type 'Hand' in scope"

**Solution:**
1. Make sure all source files are added to the target
2. Check that files are in the correct folders
3. Verify imports at the top of each file

### Issue: Database errors when running

**Solution:**
1. Delete the app's database:
```bash
rm -rf ~/Library/Application\ Support/PokerHUD/
```
2. Relaunch the app to recreate the database

### Issue: App crashes on launch

**Solution:**
1. Check the Xcode console for error messages
2. Ensure Info.plist is properly configured
3. Verify all model files are included in the target

## Testing Your Changes

### Running Tests

1. Select **Product → Test** (⌘U)
2. View test results in the Test Navigator

### Adding Test Data

Create your own hand history files:
1. Copy the format from `SampleData/sample_pokerstars.txt`
2. Modify player names and actions
3. Import through the app

## Development Workflow

### Making Changes

1. Edit source files in Xcode
2. Build frequently (⌘B) to catch errors early
3. Run (⌘R) to test changes
4. Commit changes to git:
```bash
git add .
git commit -m "Description of changes"
git push
```

### Adding New Features

Follow the blueprint in `poker-hud-blueprint_1.md` for the next phases:
- **Phase 2:** HUD Overlay
- **Phase 3:** Advanced Reports
- **Phase 4:** Hand Replayer
- **Phase 5:** Multi-Site Support

## Project Structure Overview

```
PokerHUD/
├── PokerHUD/                   # Main app code
│   ├── App/                    # App entry point and state
│   ├── Models/                 # Data models
│   ├── Database/               # Database layer (GRDB)
│   ├── Parsers/                # Hand history parsers
│   ├── Engine/                 # Business logic
│   ├── Views/                  # SwiftUI views
│   │   ├── Dashboard/
│   │   ├── Reports/
│   │   └── Settings/
│   └── Info.plist
├── PokerHUDTests/              # Unit tests
│   └── ParserTests/
├── SampleData/                 # Sample hand histories
├── README.md                   # Project documentation
├── GETTING_STARTED.md          # This file
└── poker-hud-blueprint_1.md    # Complete project blueprint
```

## Next Steps

1. **Import real hand histories:** Use your actual PokerStars hand history files
2. **Explore the code:** Understand how parsing and stats work
3. **Add features:** Follow Phase 2 to add HUD overlay functionality
4. **Contribute:** Submit pull requests with improvements

## Resources

- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [GRDB.swift Documentation](https://github.com/groue/GRDB.swift)
- [macOS App Development](https://developer.apple.com/macos/)

## Support

If you encounter issues:
1. Check the console output in Xcode
2. Review this guide
3. Search existing GitHub issues
4. Create a new issue with details: https://github.com/matteocaglio1989-cmd/Poker-HUD/issues

---

**You're all set!** Start importing hands and analyzing your poker game. Good luck at the tables! 🃏♠️♥️♣️♦️
