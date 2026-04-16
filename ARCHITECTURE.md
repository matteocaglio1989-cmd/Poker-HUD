# Poker HUD Architecture

This document describes the architecture and design patterns used in Poker HUD.

## Architecture Pattern: MVVM + Repository

The app follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────┐
│                    Views                        │
│              (SwiftUI Views)                    │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│                ViewModels                       │
│             (@StateObject / @EnvironmentObject) │
│                 AppState                        │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│             Business Logic                      │
│    (ImportEngine, StatsCalculator, Parsers)     │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│            Data Access Layer                    │
│  (Repositories: HandRepository, PlayerRepository)│
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│              Database Layer                     │
│          (GRDB.swift / SQLite)                  │
└─────────────────────────────────────────────────┘
```

## Layer Responsibilities

### 1. Views (SwiftUI)

**Location:** `PokerHUD/Views/`

**Responsibility:** Presentation and user interaction

**Examples:**
- `DashboardView`: Displays overview and import controls
- `ReportsView`: Shows player statistics tables
- `SettingsView`: App configuration UI

**Key Principles:**
- Views should be **stateless** and driven by data
- Use `@EnvironmentObject`, `@StateObject`, and `@State` appropriately
- Keep views focused on presentation, not business logic

### 2. ViewModels / State Management

**Location:** `PokerHUD/App/AppState.swift`

**Responsibility:** Application state and coordination

**Key Components:**
- `AppState`: Global app state, coordinates import, manages active tables
- Published properties trigger view updates
- Async operations for long-running tasks

**Example:**
```swift
@MainActor
class AppState: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0

    func importHandHistoryFiles(_ urls: [URL]) async throws {
        // Coordinate import process
    }
}
```

### 3. Business Logic (Engine)

**Location:** `PokerHUD/Engine/`

**Responsibility:** Core business operations

**Components:**

#### ImportEngine
- Orchestrates hand history import
- Coordinates parser → stats → database
- Progress tracking
- Error handling

#### StatsCalculator
- Computes poker statistics from hand data
- Calculates VPIP, PFR, 3-Bet, etc.
- Aggregates stats from database

**Key Principles:**
- Independent of UI
- Fully testable
- Clear input/output contracts

### 4. Parsers

**Location:** `PokerHUD/Parsers/`

**Responsibility:** Convert hand history text to structured data

**Components:**
- `HandHistoryParser`: Protocol defining parser interface
- `PokerStarsParser`: Concrete implementation for PokerStars
- `ParserFactory`: Auto-detects and returns appropriate parser

**Design Pattern: Strategy Pattern**
```swift
protocol HandHistoryParser {
    var siteName: String { get }
    func canParse(_ text: String) -> Bool
    func parse(_ text: String) throws -> [ParsedHand]
}
```

**Adding New Parsers:**
1. Create new class conforming to `HandHistoryParser`
2. Implement parsing logic
3. Add to `ParserFactory.parsers` array

### 5. Data Access Layer (Repositories)

**Location:** `PokerHUD/Database/`

**Responsibility:** Abstract database operations

**Components:**

#### HandRepository
```swift
class HandRepository {
    func fetchAll() throws -> [Hand]
    func fetchById(_ id: Int64) throws -> Hand?
    func insert(_ hand: inout Hand) throws
    func fetchRecent(limit: Int) throws -> [Hand]
}
```

#### PlayerRepository
```swift
class PlayerRepository {
    func findOrCreate(username: String, siteId: Int64) throws -> Player
    func fetchByUsername(_ username: String) throws -> Player?
}
```

#### StatsRepository
```swift
class StatsRepository {
    func fetchPlayerStats(playerId: Int64) throws -> PlayerStats?
    func fetchAllPlayerStats(minHands: Int) throws -> [PlayerStats]
}
```

**Key Principles:**
- Repository pattern abstracts database details
- Business logic doesn't directly use GRDB
- Easier to test with mock repositories

### 6. Database Layer

**Location:** `PokerHUD/Database/DatabaseManager.swift`

**Responsibility:** Database setup, migrations, and access

**Key Components:**
- `DatabaseManager`: Singleton managing database connection
- Schema migrations
- GRDB configuration

**Schema Design:**
```
sites → players → hand_players → hands
                               → actions
                               → hand_tags
         ↓
      player_notes

tournaments → hands → sessions
```

## Data Models

**Location:** `PokerHUD/Models/`

### Core Models

All models conform to GRDB protocols:
```swift
struct Hand: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var siteId: Int64
    var handId: String
    // ... other fields
}
```

**GRDB Protocols:**
- `Codable`: Automatic column mapping
- `FetchableRecord`: Can be fetched from database
- `PersistableRecord`: Can be inserted/updated
- `TableRecord`: Defines table name

### Model Relationships

Using GRDB associations:
```swift
extension Hand {
    static let site = belongsTo(Site.self)
    static let handPlayers = hasMany(HandPlayer.self)
    static let actions = hasMany(Action.self)
}
```

## Key Design Patterns

### 1. Repository Pattern
Abstracts data access, making it easy to switch storage or add caching.

### 2. Strategy Pattern
Parsers use strategy pattern - different parsing algorithms for different sites.

### 3. Factory Pattern
`ParserFactory` creates appropriate parser based on content detection.

### 4. Singleton Pattern
`DatabaseManager.shared` - single database instance for the app.

### 5. Observer Pattern
SwiftUI's `@Published` and `ObservableObject` for reactive updates.

## Threading Model

### Main Thread (@MainActor)
- All UI updates
- AppState modifications
- View rendering

### Background Threads
- File I/O (reading hand histories)
- Parsing (CPU-intensive)
- Database queries (via GRDB's serial queue)

**Example:**
```swift
func importHandHistoryFiles(_ urls: [URL]) async throws {
    // This runs in background
    let content = try String(contentsOf: url)

    await MainActor.run {
        // UI updates on main thread
        self.importProgress = progress
    }
}
```

## Error Handling

### Custom Error Types
```swift
enum ParserError: LocalizedError {
    case invalidFormat
    case missingHandId
    // ...

    var errorDescription: String? {
        // User-friendly messages
    }
}
```

### Error Propagation
- Parsers throw errors
- ImportEngine catches and wraps them
- UI displays user-friendly messages

## Testing Strategy

### Unit Tests
- **Parser tests:** Verify parsing logic with sample hands
- **Stats tests:** Validate stat calculations
- **Repository tests:** Test database operations

### Test Organization
```
PokerHUDTests/
├── ParserTests/
│   ├── PokerStarsParserTests.swift
│   └── [Future parsers]
├── StatsTests/
│   └── StatsCalculatorTests.swift
└── DatabaseTests/
    └── RepositoryTests.swift
```

## Performance Considerations

### Database Optimization
- **Indexes:** All foreign keys and frequently queried columns
- **Batch inserts:** Insert multiple records in a transaction
- **Prepared statements:** GRDB uses them automatically

### Memory Management
- **Streaming:** Don't load all hands into memory
- **Pagination:** Fetch hands in batches
- **Weak references:** Avoid retain cycles in closures

### Async/Await
```swift
// Good - non-blocking
func importFiles(_ urls: [URL]) async throws {
    for url in urls {
        try await importFile(url)
    }
}

// Bad - blocks main thread
func importFilesSync(_ urls: [URL]) throws {
    // Synchronous file I/O on main thread
}
```

## Future Architecture Enhancements

### Phase 2: HUD Overlay
Add new layers:
```
HUD Layer (NSPanel)
    ├── HUDWindowController
    ├── TableDetector (CGWindowListCopyWindowInfo)
    └── HUDPositioner
```

### Phase 3: Advanced Reports
Add new components:
```
Reporting Engine
    ├── FilterEngine (SQL query builder)
    ├── GraphGenerator (Charts)
    └── ExportEngine (CSV, PDF)
```

### Phase 4: Hand Replayer
Add new views:
```
Replayer
    ├── TableCanvasView (Visual table)
    ├── ActionTimeline (Playback controls)
    └── ReplayerEngine (State machine)
```

## Code Style Guidelines

### Naming Conventions
- **Types:** PascalCase (`HandRepository`)
- **Variables:** camelCase (`importProgress`)
- **Constants:** camelCase (`databaseManager`)
- **Files:** Match type name (`HandRepository.swift`)

### File Organization
```swift
// 1. Imports
import Foundation
import GRDB

// 2. Main type definition
struct Hand: Codable {
    // Properties
    var id: Int64?

    // Static constants
    static let databaseTableName = "hands"
}

// 3. Extensions
extension Hand: Identifiable {}

extension Hand {
    // Computed properties, methods
}
```

### SwiftUI View Structure
```swift
struct DashboardView: View {
    // 1. Property Wrappers
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false

    // 2. Body
    var body: some View {
        // View hierarchy
    }

    // 3. Private methods
    private func loadData() { }
}

// 4. Subviews and helpers
struct DashboardCard: View { }
```

## Debugging Tips

### Database Inspection
```bash
# Open database in SQLite
sqlite3 ~/Library/Application\ Support/PokerHUD/poker.db

# View tables
.tables

# Query data
SELECT * FROM hands LIMIT 10;
```

### Logging
Use print statements during development:
```swift
print("Parsed \(hands.count) hands from \(url.lastPathComponent)")
```

In production, consider using `os.log`:
```swift
import os.log
let logger = Logger(subsystem: "com.pokerhud.app", category: "import")
logger.info("Import started")
```

## Resources

- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [GRDB Documentation](https://github.com/groue/GRDB.swift)
- [Combine Framework](https://developer.apple.com/documentation/combine)

---

This architecture is designed to be:
- **Testable:** Clear layer separation
- **Maintainable:** Single responsibility principle
- **Scalable:** Easy to add new sites, stats, features
- **Performant:** Async operations, database optimization
