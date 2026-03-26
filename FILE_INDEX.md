# Poker HUD - Complete File Index

This document provides an index of all files in the project with descriptions.

---

## 📁 Project Root

### Documentation Files (5)
| File | Description | Lines |
|------|-------------|-------|
| `README.md` | Main project documentation, features, roadmap | 280+ |
| `GETTING_STARTED.md` | Step-by-step setup and usage guide | 230+ |
| `ARCHITECTURE.md` | Architecture patterns and design decisions | 390+ |
| `PROJECT_SUMMARY.md` | Phase 1 completion summary | 360+ |
| `poker-hud-blueprint_1.md` | Complete 5-phase project specification | 640+ |

### Configuration Files (2)
| File | Description |
|------|-------------|
| `Package.swift` | Swift Package Manager dependencies (GRDB) |
| `.gitignore` | Git ignore patterns |

---

## 📁 PokerHUD/ (Main App)

### App Layer (2 files)
| File | Description | Key Components |
|------|-------------|----------------|
| `App/PokerHUDApp.swift` | Main app entry point (@main) | App, WindowGroup, Settings |
| `App/AppState.swift` | Global application state | ObservableObject, import coordination |

### Models (10 files)
| File | Description | Database Table |
|------|-------------|----------------|
| `Models/Site.swift` | Poker site model | sites |
| `Models/Player.swift` | Player model + PlayerType enum | players |
| `Models/Tournament.swift` | Tournament model + GameType/LimitType | tournaments |
| `Models/Hand.swift` | Hand model | hands |
| `Models/HandPlayer.swift` | Player-in-hand model + Position enum | hand_players |
| `Models/Action.swift` | Player action model + Street/ActionType | actions |
| `Models/Session.swift` | Session model | sessions |
| `Models/PlayerNote.swift` | Player notes model | player_notes |
| `Models/HandTag.swift` | Hand tagging model + CommonHandTag | hand_tags |
| `Models/PlayerStats.swift` | Computed stats (not persisted) | - |

### Database Layer (4 files)
| File | Description | Key Methods |
|------|-------------|-------------|
| `Database/DatabaseManager.swift` | GRDB setup, schema, migrations | migrator, reader, writer |
| `Database/HandRepository.swift` | Hand data access | insert, fetch, delete |
| `Database/PlayerRepository.swift` | Player data access | findOrCreate, fetch |
| `Database/StatsRepository.swift` | Statistics queries | fetchPlayerStats, fetchAllPlayerStats |

### Parsers (3 files)
| File | Description | Lines |
|------|-------------|-------|
| `Parsers/HandHistoryParser.swift` | Parser protocol + data structures | ~150 |
| `Parsers/PokerStarsParser.swift` | PokerStars parser implementation | ~500 |
| `Parsers/ParserFactory.swift` | Auto-detection factory | ~50 |

### Engine (2 files)
| File | Description | Key Methods |
|------|-------------|-------------|
| `Engine/ImportEngine.swift` | Import orchestration | importFiles, importHand |
| `Engine/StatsCalculator.swift` | Stats calculation | calculateHandStats, getPlayerStats |

### Views (4 files)
| File | Description | Key Features |
|------|-------------|--------------|
| `Views/MainView.swift` | Main navigation, sidebar | NavigationSplitView, SidebarItem |
| `Views/Dashboard/DashboardView.swift` | Dashboard with import | Stats cards, file importer, recent hands |
| `Views/Reports/ReportsView.swift` | Statistics reports | Player stats table, filters, time ranges |
| `Views/Settings/SettingsView.swift` | Settings panel | Site config, database info, about |

### Resources (1 file)
| File | Description |
|------|-------------|
| `Info.plist` | App metadata and configuration |

---

## 📁 PokerHUDTests/

### Test Files (1 file)
| File | Description | Test Cases |
|------|-------------|------------|
| `ParserTests/PokerStarsParserTests.swift` | PokerStars parser tests | canParse, parseSimpleHand, multipleHands |

---

## 📁 SampleData/

### Sample Files (1 file)
| File | Description | Content |
|------|-------------|---------|
| `sample_pokerstars.txt` | Sample PokerStars hand histories | 3 realistic poker hands |

---

## File Statistics

### By Category

| Category | Files | Approx. Lines |
|----------|-------|---------------|
| **Documentation** | 5 | 1,900+ |
| **App/State** | 2 | 100 |
| **Models** | 10 | 600 |
| **Database** | 4 | 700 |
| **Parsers** | 3 | 700 |
| **Engine** | 2 | 400 |
| **Views** | 4 | 700 |
| **Tests** | 1 | 150 |
| **Config** | 2 | 50 |
| **Sample Data** | 1 | 100 |
| **TOTAL** | **34** | **~5,400** |

### By File Type

| Type | Count |
|------|-------|
| `.swift` | 27 |
| `.md` | 5 |
| `.plist` | 1 |
| `.txt` | 1 |
| **Total** | **34** |

---

## Quick Navigation Guide

### 🎯 Where to Find...

#### "How do I get started?"
→ `GETTING_STARTED.md`

#### "How does the architecture work?"
→ `ARCHITECTURE.md`

#### "What's been completed?"
→ `PROJECT_SUMMARY.md`

#### "What's the full vision?"
→ `poker-hud-blueprint_1.md`

#### "How do I add a new poker site parser?"
→ `Parsers/HandHistoryParser.swift` (protocol)
→ `Parsers/PokerStarsParser.swift` (example)
→ `Parsers/ParserFactory.swift` (registration)

#### "How is data stored?"
→ `Database/DatabaseManager.swift` (schema)
→ `Models/*.swift` (data structures)

#### "How are stats calculated?"
→ `Engine/StatsCalculator.swift`

#### "How does import work?"
→ `Engine/ImportEngine.swift`

#### "How do I modify the UI?"
→ `Views/**/*.swift`

---

## File Dependencies

### Import Graph (Simplified)

```
PokerHUDApp
    └── AppState
            ├── DatabaseManager
            │       └── Models (Hand, Player, etc.)
            ├── ImportEngine
            │       ├── ParserFactory
            │       │       └── PokerStarsParser
            │       ├── StatsCalculator
            │       └── Repositories
            └── MainView
                    └── DashboardView, ReportsView, SettingsView
```

---

## Code Organization Principles

### 1. **Separation by Layer**
```
App/         → Application entry and state
Models/      → Data structures
Database/    → Data access layer
Parsers/     → Hand history parsing
Engine/      → Business logic
Views/       → User interface
Tests/       → Unit tests
```

### 2. **Naming Conventions**
- Files named after primary type: `Hand.swift` contains `struct Hand`
- Related types grouped: `Action.swift` has `Action`, `Street`, `ActionType`
- Tests mirror source: `PokerStarsParserTests.swift` tests `PokerStarsParser.swift`

### 3. **Dependencies Flow**
```
Views → Engine → Database → Models
       ↓
    Parsers
```

---

## Recently Modified Files

All files created: **March 26, 2025** (Phase 1 implementation)

---

## File Sizes (Approximate)

### Large Files (200+ lines)
- `PokerStarsParser.swift` (~500 lines) - Complex parsing logic
- `ARCHITECTURE.md` (~390 lines) - Comprehensive architecture guide
- `PROJECT_SUMMARY.md` (~360 lines) - Detailed summary
- `DatabaseManager.swift` (~280 lines) - Schema and migrations
- `README.md` (~280 lines) - Main documentation
- `StatsRepository.swift` (~200 lines) - Complex SQL queries

### Medium Files (100-200 lines)
- `DashboardView.swift`
- `ReportsView.swift`
- `ImportEngine.swift`
- `StatsCalculator.swift`
- `HandRepository.swift`

### Small Files (< 100 lines)
- Most model files
- `ParserFactory.swift`
- `PokerHUDApp.swift`
- View helpers

---

## Search Tips

### Find by Function

**Parsing:**
```bash
find . -path ./Parsers -name "*.swift"
```

**Database:**
```bash
find . -path ./Database -name "*.swift"
```

**Views:**
```bash
find . -path ./Views -name "*.swift"
```

### Find by Pattern

**All models:**
```bash
ls PokerHUD/Models/*.swift
```

**All tests:**
```bash
ls PokerHUDTests/**/*.swift
```

**Documentation:**
```bash
ls *.md
```

---

## TODO: Files to Add in Future Phases

### Phase 2 (HUD)
- [ ] `HUD/HUDWindowController.swift`
- [ ] `HUD/HUDOverlayView.swift`
- [ ] `HUD/TableDetector.swift`
- [ ] `HUD/HUDPositioner.swift`
- [ ] `Engine/FileWatcher.swift`

### Phase 3 (Advanced Reports)
- [ ] `Reports/SituationalView.swift`
- [ ] `Reports/CBetView.swift`
- [ ] `Reports/HoleCardReport.swift`
- [ ] `Database/FilterEngine.swift`

### Phase 4 (Replayer)
- [ ] `Replayer/ReplayerView.swift`
- [ ] `Replayer/TableCanvasView.swift`
- [ ] `Replayer/ActionTimeline.swift`

### Phase 5 (Multi-Site)
- [ ] `Parsers/GGPokerParser.swift`
- [ ] `Parsers/EightEightEightParser.swift`
- [ ] `Parsers/PartyPokerParser.swift`
- [ ] `Engine/TournamentDetector.swift`

---

## Maintenance

### When Adding New Files

1. Add to appropriate directory
2. Update this index
3. Ensure tests are added
4. Update documentation if needed

### File Naming Rules

- Match primary type name
- Use PascalCase
- Include file extension
- Group related files in subdirectories

---

**Last Updated:** March 26, 2025 (Phase 1 Complete)
**Total Files:** 34
**Total Lines:** ~5,400
**Documentation Coverage:** 100% (all components documented)
