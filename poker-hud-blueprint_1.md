# Poker HUD for macOS — Complete Project Blueprint

## For use with Claude Code

---

## 1. Project Overview

Build a native **macOS Poker HUD & Tracker** application — an open-source alternative to Holdem Manager 3 — using **Swift/SwiftUI** with a local database. The app parses hand history files from online poker rooms, stores hand data, computes player statistics, overlays a real-time HUD on poker tables, and provides deep post-session analysis.

**GitHub repo:** `matteocaglio1989-cmd/Poker-HUD`

---

## 2. Feature Parity with Holdem Manager 3

### 2.1 Core: Hand History Import & Database

| Feature | Description |
|---------|-------------|
| Auto-import | Watch poker room hand history folders, parse new files in real-time |
| Manual import | Drag-and-drop or file picker for bulk .txt/.xml hand history files |
| Multi-site parsers | PokerStars, 888poker, partypoker, GGPoker, Winamax, iPoker, WPN, Ignition, PokerBros, PPPoker |
| Hand storage | Local SQLite (via GRDB.swift or SQLite.swift) — no PostgreSQL dependency |
| Tournament detection | Automatic + manual tournament identification from hand histories |
| Database management | Import/export, merge, backup, purge by date/site/stakes |

### 2.2 Heads-Up Display (HUD)

| Feature | Description |
|---------|-------------|
| Overlay HUD | Semi-transparent overlay window positioned on poker table windows |
| Real-time stats | VPIP, PFR, 3-Bet%, Aggression%, Fold to 3-Bet, C-Bet%, WTSD%, W$SD%, hands count |
| Graphical HUD | Color-coded ring/circle visualization (green-red preflop activity rings) |
| Standard HUD | Numeric stat panels with customizable layout |
| HUD Editor | Drag-and-drop stat placement, color ranges (e.g. 3-bet <5% = red, 5-8% = orange, >8% = green) |
| Pop-ups | Click any stat to expand detailed situational pop-up (e.g. positional breakdown) |
| Stat line | Compact row of key preflop/postflop stats beneath the ring HUD |
| Auto-positioning | Detect player seat positions and auto-place HUD panels |
| Multi-table support | Independent HUD per table window |
| "vs Hero" stats | How each opponent specifically plays against you |
| HUD-only mode | Minimal resource mode — HUD runs while main app is closed (menu bar icon) |
| 2000+ stats | Comprehensive stat library covering every conceivable poker situation |

### 2.3 Reports & Analysis

| Feature | Description |
|---------|-------------|
| Overall results | Cash game and tournament results with graphs (winnings over time, by session, by stake) |
| Situational Views | Pre-built dashboards: C-Betting, 3-Betting, River Play, Tournament All-Ins, Bubble Play |
| Positional reports | Win-rate and stats broken down by position (UTG through BTN, SB, BB) |
| Hole card reports | Results by starting hand, with heat-map grid |
| Session reports | Per-session breakdown with duration, hands played, win/loss |
| Opponent analysis | Select any opponent → full stat profile, comparison vs. your stats or other players |
| Custom filters | Autocomplete filter bar on any report; combine AND/OR operators between filters |
| Quick filters | Pre-built filter shortcuts for common situations |
| Leak detection | Identify consistently misplayed spots (e.g. calling river bets with weak top pair) |
| Graphs | Line graphs, bar charts, EV-adjusted results, showdown vs. non-showdown winnings |
| Export | Export reports as CSV, PDF, or image |

### 2.4 Hand Replayer

| Feature | Description |
|---------|-------------|
| Visual replayer | Table visualization showing cards, player actions, pot size, board |
| Session replay | Step through all hands in a session sequentially |
| Hand marking | Tag/bookmark interesting hands during replay |
| Player notes | Add notes to any opponent during replay or live play |
| Pot size indicator | Graphical pot size display for quick navigation |
| Multiple themes | Selectable table felt colors, card decks |
| BB display mode | Option to show all amounts in big blinds instead of currency |
| Stats-at-time-of-play | Show HUD stats as they were at the moment each hand was played |

### 2.5 Live Play Dashboard

| Feature | Description |
|---------|-------------|
| Session monitor | Real-time session stats: current win/loss, hands/hour, duration |
| Active tables | Overview of all open tables with key metrics |
| Session graph | Live-updating graph during play |
| Quick hand review | Instantly review last N hands without leaving live play |

### 2.6 Settings & Configuration

| Feature | Description |
|---------|-------------|
| Site settings | Configure hand history paths per poker room |
| Currency/locale | Display winnings in preferred currency |
| Rakeback tracking | Track rake paid and rakeback received |
| Aliases | Create player aliases across sites |
| Import HM2/PT4 DB | Import databases from Holdem Manager 2 / PokerTracker 4 |
| Keyboard shortcuts | Customizable hotkeys |
| Auto-update | Sparkle-based update mechanism |

### 2.7 Apps / Extensions (Phase 2+)

| Feature | Description |
|---------|-------------|
| Range Wizard | Compare ranges between player types |
| Player type classification | Auto-tag opponents as LAG, TAG, Nit, Fish, etc. based on stats |
| Hand grabbers | Support for sites that don't natively provide hand histories |
| Third-party plugin API | Allow external developers to build add-ons |

---

## 3. Recommended Tech Stack

```
┌──────────────────────────────────────────────────┐
│  macOS App (Swift 5.9+ / SwiftUI)                │
│                                                   │
│  ┌─────────────┐  ┌──────────────┐               │
│  │   SwiftUI   │  │  AppKit for  │               │
│  │   Main UI   │  │  HUD Overlay │               │
│  └──────┬──────┘  └──────┬───────┘               │
│         │                │                        │
│  ┌──────┴────────────────┴───────┐               │
│  │        Core Engine            │               │
│  │  - Hand Parser (per-site)     │               │
│  │  - Stats Calculator           │               │
│  │  - File Watcher (FSEvents)    │               │
│  │  - Table Detector (AX API)    │               │
│  └──────────────┬────────────────┘               │
│                 │                                  │
│  ┌──────────────┴────────────────┐               │
│  │   SQLite via GRDB.swift       │               │
│  │   (local database, no server) │               │
│  └───────────────────────────────┘               │
└──────────────────────────────────────────────────┘
```

| Layer | Technology | Why |
|-------|-----------|-----|
| UI Framework | SwiftUI + AppKit (hybrid) | SwiftUI for main app; AppKit NSPanel for HUD overlay windows |
| Language | Swift 5.9+ | Native macOS, performance, strong typing |
| Database | SQLite via GRDB.swift | No server, fast, HM3-like approach (they dropped PostgreSQL too) |
| File watching | FSEvents / DispatchSource | Native macOS file system event monitoring |
| Table detection | Accessibility API (AXUIElement) | Detect poker client windows and seat positions |
| Charts | Swift Charts (macOS 14+) or Charts (danielgindi) | Native charting for reports and graphs |
| Overlay | NSPanel (level: .floating) | Transparent, always-on-top HUD windows |
| Architecture | MVVM + Repository pattern | Clean separation, testable |
| Package manager | Swift Package Manager | Modern, no CocoaPods needed |
| Distribution | DMG or Sparkle for auto-update | Standard macOS distribution |

---

## 4. Database Schema (SQLite)

### Core Tables

```sql
-- Poker sites
CREATE TABLE sites (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    hand_history_path TEXT,
    auto_import INTEGER DEFAULT 1
);

-- Players encountered
CREATE TABLE players (
    id INTEGER PRIMARY KEY,
    site_id INTEGER REFERENCES sites(id),
    username TEXT NOT NULL,
    alias TEXT,
    notes TEXT,
    player_type TEXT, -- LAG, TAG, NIT, FISH, etc.
    UNIQUE(site_id, username)
);

-- Tournaments
CREATE TABLE tournaments (
    id INTEGER PRIMARY KEY,
    site_id INTEGER REFERENCES sites(id),
    tournament_id TEXT NOT NULL,
    name TEXT,
    buy_in REAL,
    rake REAL,
    bounty REAL,
    prize_pool REAL,
    finish_position INTEGER,
    total_players INTEGER,
    payout REAL,
    start_time TEXT,
    end_time TEXT,
    game_type TEXT, -- HOLDEM, OMAHA, etc.
    UNIQUE(site_id, tournament_id)
);

-- Individual hands
CREATE TABLE hands (
    id INTEGER PRIMARY KEY,
    site_id INTEGER REFERENCES sites(id),
    hand_id TEXT NOT NULL,
    tournament_id INTEGER REFERENCES tournaments(id),
    table_name TEXT,
    game_type TEXT NOT NULL,        -- HOLDEM, OMAHA, etc.
    limit_type TEXT NOT NULL,       -- NL, PL, FL
    table_size INTEGER,             -- 2-10
    small_blind REAL,
    big_blind REAL,
    ante REAL DEFAULT 0,
    board TEXT,                     -- e.g. "Ah Kd 7s 2c Jh"
    pot_total REAL,
    rake REAL,
    played_at TEXT NOT NULL,
    raw_text TEXT,                  -- original hand history
    UNIQUE(site_id, hand_id)
);

-- Player actions in each hand
CREATE TABLE hand_players (
    id INTEGER PRIMARY KEY,
    hand_id INTEGER REFERENCES hands(id) ON DELETE CASCADE,
    player_id INTEGER REFERENCES players(id),
    seat INTEGER,
    position TEXT,          -- UTG, MP, CO, BTN, SB, BB
    hole_cards TEXT,        -- e.g. "Ah Ks"
    is_hero INTEGER DEFAULT 0,
    starting_stack REAL,
    total_bet REAL,
    total_won REAL,
    net_result REAL,
    went_to_showdown INTEGER DEFAULT 0,
    won_at_showdown INTEGER DEFAULT 0,
    -- Preflop
    vpip INTEGER DEFAULT 0,
    pfr INTEGER DEFAULT 0,
    three_bet INTEGER DEFAULT 0,
    four_bet INTEGER DEFAULT 0,
    cold_call INTEGER DEFAULT 0,
    squeeze INTEGER DEFAULT 0,
    fold_to_three_bet INTEGER,
    -- Flop
    cbet_flop INTEGER,
    fold_to_cbet_flop INTEGER,
    check_raise_flop INTEGER,
    -- Turn
    cbet_turn INTEGER,
    fold_to_cbet_turn INTEGER,
    -- River
    cbet_river INTEGER,
    fold_to_cbet_river INTEGER,
    -- General
    aggression_factor REAL,
    all_in INTEGER DEFAULT 0,
    UNIQUE(hand_id, player_id)
);

-- Individual actions log
CREATE TABLE actions (
    id INTEGER PRIMARY KEY,
    hand_id INTEGER REFERENCES hands(id) ON DELETE CASCADE,
    player_id INTEGER REFERENCES players(id),
    street TEXT NOT NULL,    -- PREFLOP, FLOP, TURN, RIVER
    action_order INTEGER,
    action_type TEXT NOT NULL,-- FOLD, CHECK, CALL, BET, RAISE, ALL_IN
    amount REAL DEFAULT 0,
    pot_before REAL,
    pot_after REAL
);

-- Player notes and tags
CREATE TABLE player_notes (
    id INTEGER PRIMARY KEY,
    player_id INTEGER REFERENCES players(id),
    note TEXT,
    color TEXT,             -- color tag
    created_at TEXT,
    updated_at TEXT
);

-- Hand tags/bookmarks
CREATE TABLE hand_tags (
    id INTEGER PRIMARY KEY,
    hand_id INTEGER REFERENCES hands(id),
    tag TEXT NOT NULL,      -- "bluff", "bad beat", "review", etc.
    note TEXT,
    created_at TEXT
);

-- Sessions tracking
CREATE TABLE sessions (
    id INTEGER PRIMARY KEY,
    site_id INTEGER REFERENCES sites(id),
    table_name TEXT,
    game_type TEXT,
    stakes TEXT,
    start_time TEXT,
    end_time TEXT,
    hands_played INTEGER DEFAULT 0,
    net_result REAL DEFAULT 0,
    is_tournament INTEGER DEFAULT 0,
    tournament_id INTEGER REFERENCES tournaments(id)
);

-- Indexes for performance
CREATE INDEX idx_hands_played_at ON hands(played_at);
CREATE INDEX idx_hands_site ON hands(site_id);
CREATE INDEX idx_hand_players_player ON hand_players(player_id);
CREATE INDEX idx_hand_players_hand ON hand_players(hand_id);
CREATE INDEX idx_actions_hand ON actions(hand_id);
CREATE INDEX idx_actions_player ON actions(player_id);
CREATE INDEX idx_sessions_site ON sessions(site_id);
```

---

## 5. Project Structure for Claude Code

```
Poker-HUD/
├── PokerHUD.xcodeproj/
├── PokerHUD/
│   ├── App/
│   │   ├── PokerHUDApp.swift          # @main entry point
│   │   ├── AppState.swift             # Global app state
│   │   └── MenuBarController.swift    # HUD-only mode tray icon
│   │
│   ├── Models/
│   │   ├── Hand.swift                 # Hand data model
│   │   ├── Player.swift               # Player model
│   │   ├── Tournament.swift           # Tournament model
│   │   ├── Action.swift               # Player action model
│   │   ├── Session.swift              # Session model
│   │   ├── HUDStat.swift              # Individual stat definition
│   │   └── PlayerStats.swift          # Computed aggregate stats
│   │
│   ├── Database/
│   │   ├── DatabaseManager.swift      # GRDB setup, migrations
│   │   ├── HandRepository.swift       # Hand CRUD operations
│   │   ├── PlayerRepository.swift     # Player queries
│   │   ├── StatsRepository.swift      # Aggregate stat queries
│   │   └── FilterEngine.swift         # Report filter logic
│   │
│   ├── Parsers/
│   │   ├── HandHistoryParser.swift    # Protocol / base parser
│   │   ├── PokerStarsParser.swift     # PokerStars hand histories
│   │   ├── GGPokerParser.swift        # GGPoker format
│   │   ├── PartyPokerParser.swift     # partypoker format
│   │   ├── WinamaxParser.swift        # Winamax format
│   │   ├── EightEightEightParser.swift# 888poker format
│   │   ├── IPokerParser.swift         # iPoker network
│   │   ├── WPNParser.swift            # Winning Poker Network
│   │   ├── IgnitionParser.swift       # Ignition/Bovada
│   │   └── ParserFactory.swift        # Auto-detect site from file
│   │
│   ├── Engine/
│   │   ├── FileWatcher.swift          # FSEvents directory monitor
│   │   ├── ImportEngine.swift         # Orchestrates parsing + DB insert
│   │   ├── StatsCalculator.swift      # Compute all 2000+ stats
│   │   ├── SessionDetector.swift      # Group hands into sessions
│   │   ├── TournamentDetector.swift   # Auto-detect tournament metadata
│   │   └── PlayerClassifier.swift     # Auto-tag player types
│   │
│   ├── HUD/
│   │   ├── HUDWindowController.swift  # NSPanel overlay management
│   │   ├── HUDOverlayView.swift       # SwiftUI HUD content
│   │   ├── GraphicalHUDView.swift     # Ring/circle graphical HUD
│   │   ├── StandardHUDView.swift      # Numeric stat panel HUD
│   │   ├── HUDPopupView.swift         # Expandable stat pop-ups
│   │   ├── HUDEditorView.swift        # Drag-and-drop HUD customizer
│   │   ├── HUDPositioner.swift        # Auto-detect seat positions
│   │   ├── TableDetector.swift        # AXUIElement poker window finder
│   │   └── HUDConfiguration.swift     # Saved HUD layouts
│   │
│   ├── Views/
│   │   ├── MainView.swift             # Top-level navigation
│   │   ├── Dashboard/
│   │   │   ├── DashboardView.swift    # Home screen / overview
│   │   │   └── LivePlayView.swift     # Live session monitor
│   │   ├── Reports/
│   │   │   ├── ReportsView.swift      # Reports container
│   │   │   ├── CashGameReport.swift   # Cash game results
│   │   │   ├── TournamentReport.swift # Tournament results
│   │   │   ├── PositionalReport.swift # Stats by position
│   │   │   ├── HoleCardReport.swift   # Starting hand grid
│   │   │   └── SessionsReport.swift   # Session breakdown
│   │   ├── Situational/
│   │   │   ├── SituationalView.swift  # Situational view container
│   │   │   ├── CBetView.swift         # C-Bet analysis dashboard
│   │   │   ├── ThreeBetView.swift     # 3-Bet analysis dashboard
│   │   │   ├── RiverPlayView.swift    # River play analysis
│   │   │   └── AllInView.swift        # Tournament all-in spots
│   │   ├── Opponents/
│   │   │   ├── OpponentListView.swift # Browse all opponents
│   │   │   └── OpponentDetailView.swift# Deep dive on one player
│   │   ├── Replayer/
│   │   │   ├── ReplayerView.swift     # Hand replayer UI
│   │   │   ├── TableCanvasView.swift  # Visual poker table
│   │   │   └── ActionTimeline.swift   # Step-through controls
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift     # Settings container
│   │   │   ├── SiteSettingsView.swift # Per-site config
│   │   │   ├── HUDSettingsView.swift  # HUD preferences
│   │   │   └── DatabaseSettings.swift # DB management
│   │   └── Components/
│   │       ├── StatBadge.swift        # Reusable stat display
│   │       ├── FilterBar.swift        # Autocomplete filter bar
│   │       ├── WinningsGraph.swift    # Chart component
│   │       └── HandGrid.swift         # Starting hand grid
│   │
│   ├── Utilities/
│   │   ├── CardUtils.swift            # Card/hand parsing helpers
│   │   ├── EquityCalculator.swift     # Basic equity calculations
│   │   ├── Formatters.swift           # Currency, number formatting
│   │   └── Preferences.swift          # UserDefaults wrapper
│   │
│   └── Resources/
│       ├── Assets.xcassets/
│       ├── CardDecks/                 # Multiple card deck images
│       ├── TableThemes/               # Table felt textures
│       └── DefaultHUDs/               # Pre-built HUD configurations
│
├── PokerHUDTests/
│   ├── ParserTests/                   # Test each site parser
│   ├── StatsTests/                    # Verify stat calculations
│   └── DatabaseTests/                 # Repository tests
│
├── Package.swift                      # SPM dependencies
└── README.md
```

---

## 6. Implementation Phases for Claude Code

### Phase 1 — Foundation (Start Here)

**Goal:** Parse hands, store in DB, display basic reports.

```
Tasks:
1. Initialize Xcode project with SwiftUI lifecycle
2. Set up GRDB.swift via SPM
3. Create database schema + migrations
4. Implement PokerStars hand history parser (most common format)
5. Build ImportEngine with manual file import
6. Create basic PlayerStats calculator (VPIP, PFR, 3-Bet, AF, WTSD, W$SD)
7. Build main navigation shell (sidebar: Dashboard, Reports, Opponents)
8. Display basic cash game report with results table + line graph
9. Write parser tests with sample hand histories
```

**Claude Code commands to get started:**

```bash
# In terminal, navigate to your repo
cd ~/Projects/Poker-HUD

# Launch Claude Code
claude

# Then give it prompts like:
> Create a new macOS SwiftUI app called PokerHUD with the project
  structure defined in the blueprint. Set up GRDB.swift as an SPM
  dependency. Create the SQLite schema with all tables from the
  blueprint's section 4.

> Implement a PokerStars hand history parser that reads .txt files
  and extracts: hand ID, game type, stakes, player actions, board
  cards, and results. Follow the HandHistoryParser protocol.

> Build the StatsCalculator that computes VPIP, PFR, 3-Bet%,
  Aggression%, C-Bet%, WTSD%, and W$SD% from the hand_players table.
```

### Phase 2 — HUD Overlay

**Goal:** Overlay stats on poker tables in real-time.

```
Tasks:
1. Build TableDetector using Accessibility API to find poker windows
2. Create HUDWindowController with NSPanel (floating, transparent)
3. Implement auto-positioning of HUD per player seat
4. Build StandardHUDView showing key stats per opponent
5. Build GraphicalHUDView with color-coded rings
6. Add FileWatcher for auto-import from configured directories
7. Wire real-time: new hand → parse → update DB → refresh HUD
8. Implement HUD-only mode (menu bar agent)
```

### Phase 3 — Advanced Reports & Situational Views

**Goal:** Deep analysis tools matching HM3.

```
Tasks:
1. Build FilterEngine with autocomplete and AND/OR combinators
2. Create Situational Views: C-Bet, 3-Bet, River Play, All-In
3. Implement Hole Card report with heat-map grid
4. Build Opponent Analysis with stat comparison
5. Add session detection and session report
6. Create tournament results report
7. Add graphs: EV-adjusted, showdown/non-showdown split
```

### Phase 4 — Hand Replayer

```
Tasks:
1. Build TableCanvasView (visual poker table with seats, cards, chips)
2. Implement step-by-step action replay with pot tracking
3. Add hand tagging/bookmarking
4. Player notes system
5. Stats-at-time-of-play display
6. Multiple table themes and card decks
```

### Phase 5 — Multi-Site & Polish

```
Tasks:
1. Implement parsers: GGPoker, partypoker, 888, Winamax, WPN, Ignition
2. Tournament detection (auto + manual)
3. HUD Editor with drag-and-drop stat placement
4. HUD pop-ups with situational breakdowns
5. Import from HM2/PT4 databases
6. Player type auto-classification
7. Aliases across sites
8. Auto-update via Sparkle
9. Full keyboard shortcut system
```

---

## 7. Key Technical Implementation Notes

### HUD Overlay (the hardest part)

```swift
// NSPanel for floating overlay — AppKit required
class HUDPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false  // allow clicks on HUD
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
    }
}
```

### Table Detection via Accessibility API

```swift
// Detect poker client windows
func findPokerTables() -> [AXUIElement] {
    let apps = NSWorkspace.shared.runningApplications
    let pokerApps = apps.filter { app in
        ["PokerStars", "pokerstars", "GGPoker", "partypoker"]
            .contains(where: { app.localizedName?.contains($0) == true })
    }
    // Use AXUIElement to find table windows and seat positions
}
```

### Real-Time File Watching

```swift
// FSEvents-based watcher for hand history directories
class HandHistoryWatcher {
    private var stream: FSEventStreamRef?

    func watch(directory: URL, handler: @escaping (URL) -> Void) {
        let callback: FSEventStreamCallback = { /* ... */ }
        // Create FSEventStream for the directory
        // On new/modified file → trigger handler
    }
}
```

### Stat Calculation Pattern

```swift
// Efficient aggregate queries via GRDB
struct PlayerStatsQuery {
    static func vpip(for playerID: Int64, in db: Database) throws -> Double {
        let row = try Row.fetchOne(db, sql: """
            SELECT
                COUNT(*) as total_hands,
                SUM(vpip) as vpip_count
            FROM hand_players
            WHERE player_id = ?
        """, arguments: [playerID])
        guard let total = row?["total_hands"] as? Int, total > 0 else { return 0 }
        return Double(row?["vpip_count"] as? Int ?? 0) / Double(total) * 100
    }
}
```

---

## 8. SPM Dependencies

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
]
```

---

## 9. Important Considerations

**Privacy & Terms of Service:** Some poker sites restrict HUD usage. The app should clearly document which sites allow HUDs and respect site policies.

**Performance:** HM3 boasts speed improvements — your app should use indexed queries, background threads for parsing, and incremental stat updates (not full recalculation per hand).

**Accessibility permissions:** The HUD overlay requires macOS Accessibility permissions to detect poker windows. Guide users through System Settings → Privacy & Security → Accessibility.

**Code signing:** For distribution, the app needs a Developer ID certificate. For personal use, ad-hoc signing works.

---

## 10. Getting Started with Claude Code

```bash
# 1. Clone your repo
git clone https://github.com/matteocaglio1989-cmd/Poker-HUD.git
cd Poker-HUD

# 2. Launch Claude Code
claude

# 3. Start with Phase 1 — give Claude Code this prompt:
```

**Suggested first prompt for Claude Code:**

> Read the project blueprint. Create a macOS SwiftUI app called PokerHUD targeting macOS 14+. Set up the Xcode project structure from section 5 of the blueprint. Add GRDB.swift via SPM. Create DatabaseManager.swift that initializes SQLite and runs migrations for all tables in section 4. Then implement the PokerStars hand history parser — it should parse standard PokerStars .txt hand history format, extracting hand metadata, player actions, and results. Finally, create a basic main view with a sidebar navigation showing Dashboard, Reports, and Opponents sections.
