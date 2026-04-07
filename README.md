# Poker HUD - macOS Poker Tracker & HUD

A native macOS application for tracking and analyzing poker hands with real-time HUD overlay. Built with Swift/SwiftUI and GRDB.swift.

## Current Status: Phase 2 - HUD Overlay ✅

Phase 2 is complete with the following features on top of the Phase 1 foundation:
- ✅ Floating NSPanel HUD overlays with per-seat auto-positioning
- ✅ Accessibility API window-title enrichment for reliable multi-table binding
- ✅ Real-time stat updates with visual flash feedback on new hands
- ✅ File watcher for auto-import (recursive)
- ✅ Menu bar HUD-only mode
- ✅ StoreKit 2 subscription gating with 3-hour cumulative free trial

## Features Roadmap

### Phase 1 - Foundation ✅ (COMPLETE)
- [x] Database schema and migrations
- [x] Hand history parser (PokerStars)
- [x] Basic stats calculator
- [x] Import engine
- [x] Dashboard UI
- [x] Reports UI
- [x] Basic tests

### Phase 2 - HUD Overlay ✅ (COMPLETE)
- [x] Table detection via Accessibility API
- [x] Floating HUD windows (NSPanel)
- [x] Real-time stat display
- [x] Auto-positioning per seat
- [x] File watcher for auto-import
- [x] Menu bar HUD-only mode

### Phase 3 - Advanced Reports (Next)
- [ ] Situational views (C-Bet, 3-Bet, River Play)
- [ ] Filter engine with autocomplete
- [ ] Hole card heat maps
- [ ] Opponent analysis
- [ ] Session tracking and reports
- [ ] Export functionality

### Phase 4 - Hand Replayer
- [ ] Visual poker table
- [ ] Step-through hand replay
- [ ] Hand tagging and bookmarking
- [ ] Player notes system
- [ ] Multiple table themes

### Phase 5 - Multi-Site & Polish
- [ ] Additional poker site parsers (GGPoker, 888, partypoker, etc.)
- [ ] Tournament detection
- [ ] HUD editor (drag-and-drop)
- [ ] HUD pop-ups with detailed stats
- [ ] Import from HM2/PT4 databases
- [ ] Auto-update system

## Project Structure

```
PokerHUD/
├── App/
│   ├── PokerHUDApp.swift       # Main app entry point
│   └── AppState.swift          # Global app state
├── Models/
│   ├── Site.swift              # Poker site model
│   ├── Player.swift            # Player model
│   ├── Hand.swift              # Hand model
│   ├── HandPlayer.swift        # Player in hand model
│   ├── Action.swift            # Player action model
│   ├── Tournament.swift        # Tournament model
│   ├── Session.swift           # Session model
│   └── PlayerStats.swift       # Computed statistics
├── Database/
│   ├── DatabaseManager.swift   # GRDB setup and migrations
│   ├── HandRepository.swift    # Hand data access
│   ├── PlayerRepository.swift  # Player data access
│   └── StatsRepository.swift   # Statistics queries
├── Parsers/
│   ├── HandHistoryParser.swift # Parser protocol
│   ├── PokerStarsParser.swift  # PokerStars implementation
│   └── ParserFactory.swift     # Auto-detect parser
├── Engine/
│   ├── ImportEngine.swift      # Import orchestration
│   └── StatsCalculator.swift   # Statistics calculation
├── Views/
│   ├── MainView.swift          # Main navigation
│   ├── Dashboard/
│   │   └── DashboardView.swift # Dashboard with import
│   ├── Reports/
│   │   └── ReportsView.swift   # Statistics reports
│   └── Settings/
│       └── SettingsView.swift  # Settings panel
└── PokerHUDTests/
    └── ParserTests/
        └── PokerStarsParserTests.swift
```

## Building the Project

### Requirements
- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Setup Instructions

1. **Clone the repository**
```bash
git clone https://github.com/matteocaglio1989-cmd/Poker-HUD.git
cd Poker-HUD
```

2. **Open in Xcode**

Since this project uses Swift Package Manager, you need to create an Xcode project:

```bash
# Create Xcode project for macOS
mkdir -p PokerHUD.xcodeproj
```

Or use Xcode to create a new macOS App project:
- Open Xcode
- File → New → Project
- Choose "macOS" → "App"
- Product Name: PokerHUD
- Interface: SwiftUI
- Language: Swift
- Add the files from this repository to the project

3. **Add Dependencies**

Add GRDB.swift to your project:
- File → Add Package Dependencies
- Enter: `https://github.com/groue/GRDB.swift`
- Version: 7.0.0 or later

4. **Build and Run**
- Select "PokerHUD" scheme
- Product → Run (⌘R)

## Usage

### Importing Hand Histories

1. Launch Poker HUD
2. Click "Import Hands" on the Dashboard
3. Select one or more PokerStars hand history files (.txt)
4. The app will parse and import hands automatically
5. View statistics in the Reports tab

### Supported Poker Sites

Currently supported:
- ✅ PokerStars (.txt format)

Coming in Phase 5:
- GGPoker
- 888poker
- partypoker
- Winamax
- iPoker Network
- WPN (Winning Poker Network)
- Ignition/Bovada

### Statistics Available

**Preflop:**
- VPIP (Voluntarily Put $ In Pot)
- PFR (Pre-Flop Raise)
- 3-Bet %
- 4-Bet %
- Fold to 3-Bet %

**Postflop:**
- C-Bet % (Flop/Turn/River)
- Fold to C-Bet %
- Aggression Factor
- WTSD (Went To ShowDown)
- W$SD (Won $ at ShowDown)

**Results:**
- BB/100 (Big blinds won per 100 hands)
- Total winnings
- Hands played

## Database Location

The SQLite database is stored at:
```
~/Library/Application Support/PokerHUD/poker.db
```

You can backup this file to preserve your hand history data.

## Testing

Run tests in Xcode:
- Product → Test (⌘U)

Or via command line:
```bash
swift test
```

## Development

### Adding a New Poker Site Parser

1. Create a new parser class conforming to `HandHistoryParser`
2. Implement `canParse(_:)` and `parse(_:)` methods
3. Add parser to `ParserFactory.parsers` array
4. Add tests in `PokerHUDTests/ParserTests/`

Example:
```swift
class GGPokerParser: HandHistoryParser {
    let siteName = "GGPoker"

    func canParse(_ text: String) -> Bool {
        text.contains("GGPoker Hand #")
    }

    func parse(_ text: String) throws -> [ParsedHand] {
        // Implementation
    }
}
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## Architecture

This app follows **MVVM + Repository** pattern:

- **Models**: Plain Swift structs conforming to GRDB protocols
- **Repositories**: Data access layer for database operations
- **ViewModels**: Business logic and state management (via `@StateObject`)
- **Views**: SwiftUI views for presentation
- **Engine**: Core business logic (parsing, importing, calculating)

## Performance Considerations

- Database queries use indexes for fast lookups
- Parsing runs in background threads
- Stats are pre-calculated during import
- Incremental updates avoid full recalculation

## Privacy & Terms of Service

**Important:** Some poker sites have policies regarding HUD usage. Always check and comply with the terms of service for the poker sites you play on.

## License

This project is open source. See LICENSE file for details.

## Credits

Built with:
- [GRDB.swift](https://github.com/groue/GRDB.swift) - SQLite database toolkit
- Swift & SwiftUI - Native macOS development

Inspired by:
- Hold'em Manager 3
- PokerTracker 4

## Support

For issues, questions, or feature requests:
- GitHub Issues: https://github.com/matteocaglio1989-cmd/Poker-HUD/issues

---

**Phase 1 Status:** Foundation Complete ✅
**Next Up:** Phase 2 - HUD Overlay Implementation
