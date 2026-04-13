# Development Environment Setup - Phase 1 Testing

This guide will help you set up a development environment to test Phase 1 of Poker HUD.

---

## 🎯 Quick Setup (5-10 minutes)

### Prerequisites

Check what you have:

```bash
# Check if Xcode is installed
xcode-select -p

# Check Swift version
swift --version
```

**You need:**
- macOS 14.0+ (Sonoma)
- Xcode 15.0+ **OR** Swift 5.9+

---

## Option 1: Full Xcode App (RECOMMENDED - for UI testing)

This option lets you run the full SwiftUI application.

### Step 1: Install Xcode (if not installed)

1. Open **App Store**
2. Search for **"Xcode"**
3. Click **Get** / **Install** (it's ~15GB)
4. Wait for installation (15-30 minutes)

### Step 2: Create Xcode Project

1. **Launch Xcode**

2. **File → New → Project**

3. Select **macOS** tab, choose **App**, click **Next**

4. Configure:
   ```
   Product Name: PokerHUD
   Team: None (or your team)
   Organization Identifier: com.pokerhud
   Interface: SwiftUI
   Language: Swift
   Storage: None
   Include Tests: No
   ```

5. Click **Next**

6. **Navigate to:** `<repo-root>/`

7. Click **Create**

8. **Xcode will create some default files - we'll replace them**

### Step 3: Add Our Source Files

1. In Xcode's **Project Navigator** (left sidebar), **delete** these auto-generated files:
   - `PokerHUDApp.swift` (the default one)
   - `ContentView.swift`
   - `Assets.xcassets` (optional, can keep)

2. **Right-click** on the **PokerHUD** folder → **Add Files to "PokerHUD"...**

3. **Navigate to** your project folder

4. **Select** these folders (hold ⌘ to select multiple):
   - `PokerHUD/App`
   - `PokerHUD/Models`
   - `PokerHUD/Database`
   - `PokerHUD/Parsers`
   - `PokerHUD/Engine`
   - `PokerHUD/Views`

5. **IMPORTANT:** Uncheck **"Copy items if needed"** (files are already in right place)

6. Make sure **"Create groups"** is selected

7. Click **Add**

### Step 4: Add Tests

1. **Right-click** on **PokerHUDTests** folder → **Add Files to "PokerHUDTests"...**

2. Select `PokerHUDTests/ParserTests` folder

3. Uncheck **"Copy items if needed"**

4. Click **Add**

### Step 5: Add GRDB Dependency

1. Click on your **project** (top of navigator)

2. Select the **PokerHUD** target

3. Click the **General** tab

4. Scroll to **Frameworks, Libraries, and Embedded Content**

5. Click the **+** button

6. Click **Add Package Dependency...**

7. Enter URL:
   ```
   https://github.com/groue/GRDB.swift
   ```

8. Set **Dependency Rule:** Up to Next Major Version **7.0.0**

9. Click **Add Package**

10. Wait for package to resolve (30-60 seconds)

11. Select **GRDB** in the list, click **Add Package**

### Step 6: Configure Build Settings

1. Select your **project** → **PokerHUD** target

2. Go to **Build Settings** tab

3. Search for **"deployment"**

4. Set **macOS Deployment Target** to **14.0**

### Step 7: Build the Project

1. Select **Product → Build** (or press **⌘B**)

2. Wait for build to complete (~30 seconds first time)

3. Fix any errors:
   - Missing imports? Make sure GRDB is added
   - File not found? Check files are added to target
   - Deployment target? Set to macOS 14.0

### Step 8: Run the App!

1. **Product → Run** (or press **⌘R**)

2. The Poker HUD app should launch! 🎉

### Step 9: Test Import

1. Click **"Import Hands"** button

2. Navigate to:
   ```
   <repo-root>/SampleData/sample_pokerstars.txt
   ```

3. Click **Open**

4. Watch the import progress

5. Check **Dashboard** for imported hands

6. Go to **Reports** tab to see statistics

---

## Option 2: Swift Package Manager (Command-line testing)

This option compiles the code but won't run the SwiftUI app. Good for testing compilation only.

### Step 1: Update Package.swift

The `Package.swift` is already configured. Just verify it's correct:

```bash
cd <repo-root>/
cat Package.swift
```

### Step 2: Build with SPM

```bash
cd <repo-root>/
swift build
```

**Note:** This will download GRDB and compile all code, but **won't run the app** because it's a SwiftUI application.

### Step 3: Run Tests

```bash
swift test
```

---

## Option 3: Use Pre-built Project (Fastest)

I can create a complete `.xcodeproj` file for you. Let me know if you want this!

---

## Troubleshooting

### "xcodebuild requires Xcode"

**Solution:** Install Xcode from App Store, then run:
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### "No such module 'GRDB'"

**Solutions:**
```bash
# In Terminal (if using SPM):
cd <repo-root>/
swift package resolve
swift package update

# In Xcode:
File → Packages → Reset Package Caches
File → Packages → Update to Latest Package Versions
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
```

### Build errors about missing files

**Solution:**
1. Make sure all files are added to the target
2. Check **Target Membership** in File Inspector (right sidebar)
3. Each `.swift` file should have **PokerHUD** checked

### "Cannot find type 'Hand' in scope"

**Solution:**
```bash
# Make sure all model files are in the target
# In Xcode, select each .swift file
# Check the "Target Membership" in right sidebar
# Make sure "PokerHUD" is checked for source files
# Make sure "PokerHUDTests" is checked for test files
```

### Database errors

**Solution:**
```bash
# Delete existing database
rm -rf ~/Library/Application\ Support/PokerHUD/

# Restart the app
```

---

## Verification Checklist

After setup, verify:

- [ ] Project builds without errors (⌘B)
- [ ] App launches (⌘R)
- [ ] Dashboard displays
- [ ] "Import Hands" button works
- [ ] Sample data imports (3 hands)
- [ ] Reports tab shows player statistics
- [ ] Stats look reasonable (VPIP, PFR, etc.)

---

## What You Should See

### On Launch
```
┌─────────────────────────────────────┐
│  Dashboard                          │
│                                     │
│  ┌───────┐ ┌───────┐ ┌───────┐    │
│  │Total  │ │Players│ │Active │    │
│  │Hands  │ │Tracked│ │Tables │    │
│  │  0    │ │  0    │ │  0    │    │
│  └───────┘ └───────┘ └───────┘    │
│                                     │
│  [Import Hands]                     │
│                                     │
│  No hands imported yet              │
└─────────────────────────────────────┘
```

### After Import (Sample Data)
```
Dashboard:
- Total Hands: 3
- Players Tracked: 5
- Recent Hands list shows 3 hands

Reports:
┌─────────────────────────────────────────────────┐
│ Player      │Hands│VPIP│PFR│3Bet│AF│WTSD│W$SD│  │
├─────────────────────────────────────────────────┤
│ HeroPlayer  │  3  │66.7│33.3│33.3│2.0│33.3│0.0│  │
│ AggroAlice  │  3  │100 │66.7│33.3│3.5│33.3│100│  │
│ TightTina   │  3  │33.3│ 0.0│0.0 │0.0│ 0.0│0.0│  │
│ ManiacMike  │  3  │66.7│ 0.0│0.0 │1.0│33.3│100│  │
│ PassivePete │  3  │ 0.0│ 0.0│0.0 │0.0│ 0.0│0.0│  │
│ SolidSam    │  3  │ 0.0│ 0.0│0.0 │0.0│ 0.0│0.0│  │
└─────────────────────────────────────────────────┘
```

---

## Next Steps After Setup

1. **Test with sample data** ✅
2. **Import your real PokerStars hands:**
   ```
   ~/Library/Application Support/PokerStars/HandHistory/[YourUsername]/
   ```
3. **Analyze your stats** 📊
4. **Explore the code** 🔍
5. **Prepare for Phase 2** 🚀

---

## Quick Commands Reference

```bash
# Navigate to project
cd <repo-root>/

# Open in Xcode (if .xcodeproj exists)
open PokerHUD.xcodeproj

# Build with SPM
swift build

# Run tests
swift test

# Clean build
swift package clean

# Update dependencies
swift package update

# View database
sqlite3 ~/Library/Application\ Support/PokerHUD/poker.db
```

---

## Development Workflow

1. **Make changes** in Xcode
2. **Build** (⌘B) to check for errors
3. **Run** (⌘R) to test
4. **Test** (⌘U) to run unit tests
5. **Commit** changes to git

---

## Support

If you get stuck:

1. Check error message in Xcode console
2. Review this guide
3. Check `GETTING_STARTED.md`
4. Check `QUICKSTART.md`
5. Create a GitHub issue with error details

---

## Resources

- **Xcode Help:** Help → Xcode Help
- **Swift Documentation:** https://swift.org/documentation/
- **GRDB Documentation:** https://github.com/groue/GRDB.swift
- **SwiftUI Tutorials:** https://developer.apple.com/tutorials/swiftui

---

**You're ready to test Phase 1! 🚀**

Good luck! 🃏♠️♥️♣️♦️
