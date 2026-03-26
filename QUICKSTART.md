# 🚀 Poker HUD - Quick Start

**Get up and running in 5 minutes!**

---

## ⚡ TL;DR

```bash
# 1. Open in Xcode
open -a Xcode .

# 2. Add GRDB package dependency
# File → Add Package Dependencies → https://github.com/groue/GRDB.swift

# 3. Build and Run (⌘R)

# 4. Import sample data
# Click "Import Hands" → Select SampleData/sample_pokerstars.txt
```

---

## 📋 Prerequisites Checklist

- [ ] macOS 14.0+ (Sonoma or later)
- [ ] Xcode 15.0+ installed
- [ ] 5 minutes of time

---

## 🎯 Step-by-Step (First Time)

### 1. Create Xcode Project (5 min)

**Option A: Use Xcode (Recommended)**

1. Open **Xcode**
2. **File → New → Project**
3. **macOS** → **App** → **Next**
4. Settings:
   - Product Name: `PokerHUD`
   - Interface: `SwiftUI`
   - Language: `Swift`
5. Save in: `Poker-HUD` folder
6. **Delete** the auto-generated files (ContentView.swift, etc.)
7. **Right-click PokerHUD folder** → **Add Files to "PokerHUD"**
8. Add these folders:
   - `PokerHUD/App`
   - `PokerHUD/Models`
   - `PokerHUD/Database`
   - `PokerHUD/Parsers`
   - `PokerHUD/Engine`
   - `PokerHUD/Views`
9. Make sure "Copy items if needed" is **UNCHECKED**

### 2. Add Dependencies (1 min)

1. Click your project in navigator
2. Select **PokerHUD** target
3. **General** tab
4. Scroll to **Frameworks, Libraries, and Embedded Content**
5. Click **+** → **Add Package Dependency**
6. URL: `https://github.com/groue/GRDB.swift`
7. Version: **Up to Next Major** (7.0.0)
8. **Add Package**

### 3. Build (1 min)

1. **Product → Build** (⌘B)
2. Wait for dependencies to download
3. Fix any errors (check imports, file paths)

### 4. Run (30 sec)

1. **Product → Run** (⌘R)
2. App should launch!

### 5. Import Sample Data (30 sec)

1. Click **"Import Hands"** button
2. Navigate to `SampleData/sample_pokerstars.txt`
3. **Open**
4. Watch hands import
5. View stats in **Reports** tab

---

## 🎬 Using the App

### Dashboard
- **Import Hands:** Add hand history files
- **Stats Cards:** Total hands, players, tables
- **Recent Hands:** Last 20 hands imported

### Reports
- **Player Stats Table:** All tracked players
- **Filters:** Time range, minimum hands
- **Stats:** VPIP, PFR, 3-Bet, AF, WTSD, W$SD, BB/100

### Settings
- Configure poker sites
- Database management
- About information

---

## 📊 Understanding Stats

| Stat | Meaning | Good Range |
|------|---------|------------|
| **VPIP** | How often player enters pot | 15-25% (TAG) |
| **PFR** | How often player raises preflop | 12-20% (TAG) |
| **3-Bet** | How often player 3-bets | 5-10% |
| **AF** | Aggression Factor | 2.0-3.0 |
| **WTSD** | Goes to showdown | 20-30% |
| **W$SD** | Wins at showdown | 45-55% |
| **BB/100** | Winrate per 100 hands | >3 BB/100 (good) |

### Player Types
- **TAG** (Tight-Aggressive): VPIP <25%, PFR >15%
- **LAG** (Loose-Aggressive): VPIP >25%, PFR >18%
- **NIT**: VPIP <15%, PFR <12%
- **FISH**: VPIP >35%, PFR <15%

---

## 📁 File Locations

### App Database
```
~/Library/Application Support/PokerHUD/poker.db
```

### Sample Data
```
./SampleData/sample_pokerstars.txt
```

### Your Hand Histories (PokerStars)
```
~/Library/Application Support/PokerStars/HandHistory/[YourUsername]/
```

---

## 🐛 Troubleshooting

### "No such module 'GRDB'"
```bash
# In Xcode:
File → Packages → Reset Package Caches
Product → Clean Build Folder (⌘⇧K)
Product → Build (⌘B)
```

### Build Errors
- ✅ Check all files are added to target
- ✅ Verify GRDB dependency is added
- ✅ Ensure macOS deployment target is 14.0+

### Database Errors
```bash
# Delete database and restart
rm -rf ~/Library/Application\ Support/PokerHUD/
```

### Import Not Working
- ✅ File must be PokerStars .txt format
- ✅ Check console for error messages
- ✅ Try sample file first

---

## 🎓 Learn More

| Topic | Read This |
|-------|-----------|
| **Setup Help** | `GETTING_STARTED.md` |
| **Architecture** | `ARCHITECTURE.md` |
| **Features** | `README.md` |
| **What's Done** | `PROJECT_SUMMARY.md` |
| **Full Spec** | `poker-hud-blueprint_1.md` |
| **File Guide** | `FILE_INDEX.md` |

---

## 🔧 Common Tasks

### Import Your Real Hands

1. Find PokerStars hand histories:
   ```
   ~/Library/Application Support/PokerStars/HandHistory/[Username]/
   ```
2. Click **Import Hands** in app
3. Select hand history file(s)
4. Wait for import to complete
5. View stats in **Reports**

### View Database

```bash
# Open SQLite database
sqlite3 ~/Library/Application\ Support/PokerHUD/poker.db

# Show tables
.tables

# Query hands
SELECT * FROM hands LIMIT 10;

# Query player stats
SELECT COUNT(*) FROM hand_players;

# Exit
.quit
```

### Reset Everything

```bash
# Delete app data
rm -rf ~/Library/Application\ Support/PokerHUD/

# Restart app (database will be recreated)
```

---

## 🎯 Next Steps

### For Users
1. ✅ Import sample data
2. ✅ Import your real hands
3. ✅ Analyze your stats
4. ⏳ Wait for Phase 2 (HUD overlay)

### For Developers
1. ✅ Understand the architecture
2. ✅ Review parser code
3. ✅ Run tests (⌘U)
4. ⏳ Prepare for Phase 2

---

## 📞 Support

### Quick Links
- **Issues:** [GitHub Issues](https://github.com/matteocaglio1989-cmd/Poker-HUD/issues)
- **Docs:** See `*.md` files in project root
- **Code:** Browse `PokerHUD/` folder

### Before Asking for Help
1. Read error message in Xcode console
2. Check GETTING_STARTED.md
3. Try sample data first
4. Search existing GitHub issues

---

## ✅ Checklist for Success

**Setup**
- [ ] Xcode 15+ installed
- [ ] Project opened in Xcode
- [ ] GRDB.swift dependency added
- [ ] Build succeeds (⌘B)

**First Run**
- [ ] App launches
- [ ] Dashboard displays
- [ ] Import button works
- [ ] Sample data imports successfully

**Testing**
- [ ] 3 hands imported from sample file
- [ ] Player stats visible in Reports
- [ ] Stats look correct (VPIP, PFR, etc.)
- [ ] Can filter by time range

---

## 🚀 You're Ready!

**Time to analyze your poker game!**

1. Import hands ✅
2. View stats ✅
3. Find leaks ✅
4. Win more 💰

---

**Phase 1 Complete** | **Ready to Play** 🃏

Good luck at the tables! ♠️♥️♣️♦️
