# SwiftUMLStudio

Generate architectural diagrams from Swift source code — as a CLI, a Swift Package, or an interactive macOS app.

This repository contains two related products:

- **SwiftUMLBridge** — a Swift-native CLI (`swiftumlbridge`) and Swift Package. A modern, Swift 6 evolution of SwiftPlantUML with multi-format output (PlantUML, Mermaid.js, Nomnoml) and six diagram types.
- **SwiftUMLStudio** — a macOS SwiftUI app embedding SwiftUMLBridge, with persistent project snapshots, native diagram rendering, architectural insights, and a Pro tier.

## Features

### Diagram types

| Diagram | PlantUML | Mermaid.js | Nomnoml | Native SVG |
|---|---|---|---|---|
| Class | ✓ | ✓ | ✓ | ✓ |
| Sequence | ✓ | ✓ | — | ✓ |
| Activity | ✓ | — | — | ✓ |
| State machine | ✓ | ✓ | — | ✓ |
| Entity-Relationship (SwiftData / Core Data / GRDB / SQLite.swift) | ✓ | ✓ | — | — |
| Component (SPM targets + provided interfaces) | ✓ | ✓ | — | — |
| Dependency graph (modules + types) | ✓ | ✓ | — | ✓ |

### Bridge highlights

- **Class diagrams** — inheritance, protocol conformance, composition, access control
- **Sequence diagrams** — static call-graph analysis with async/sync arrow distinction, configurable depth
- **Activity diagrams** — control-flow extraction from imperative function bodies
- **State machine diagrams** — enum-driven state machine detection with confidence scoring
- **ER diagrams** — SwiftData `@Model` + `@Relationship`, Core Data `.xcdatamodeld`, GRDB record types (`belongsTo` / `hasMany` / `hasOne`), and SQLite.swift `Table` + `Expression` schemas
- **Component diagrams** — SPM targets as UML components with public types as provided interfaces and `target_dependencies` as wiring edges
- **Dependency graphs** — type-level and module-level analysis with cycle detection
- **Macro-aware stereotypes** (`@Observable`, `@Model`, etc.) surfaced in diagrams
- **Swift 6 strict concurrency** throughout the framework and CLI

### Studio highlights

- **Three modes**: Document (one-off generation), Explorer (file-tree browsing), Project (workspace with snapshots)
- **Native rendering** for class / sequence / activity / dependency diagrams via SwiftUI Canvas, with WebView fallback for Mermaid and Nomnoml
- **Project Dashboard** with insights and one-click suggestion cards (`InsightEngine`, `SuggestionEngine`)
- **Architecture Change Tracking** — diff snapshots over time (Pro)
- **History sidebar** with diagram restoration
- **Pro tier** via StoreKit 2 (multi-project workspaces, snapshot diffs, all diagram types)
- Persistent storage via SwiftData

## Requirements

- **Bridge** (CLI / Swift Package) — macOS 26+ (per `SwiftUMLBridge/Package.swift`), Swift 6.0+, Xcode 16+
- **Studio** (macOS app) — macOS 26.4+
- A Swift toolchain new enough for SourceKitten and SwiftSyntax 600.x

## Project Structure

```
SwiftUMLStudio/
├── SwiftUMLBridge/                       # Swift Package (CLI + framework)
│   ├── Package.swift
│   └── Sources/
│       ├── SwiftUMLBridgeFramework/      # Three-layer engine
│       │   ├── Parsing/                  # SourceKitten + SwiftSyntax AST
│       │   ├── Model/                    # Language-agnostic graphs
│       │   └── Emitters/                 # PlantUML / Mermaid / Nomnoml / SVG
│       └── swiftumlbridge/
│           └── Commands/                 # classdiagram, sequence, activity,
│                                         #   state, er, deps
├── SwiftUMLStudio/                       # macOS SwiftUI app
│   ├── AppMode.swift                    # Document / Explorer / Project
│   ├── DiagramViewModel.swift           # @Observable state machine
│   ├── PersistenceController.swift      # SwiftData container
│   ├── SubscriptionManager.swift        # StoreKit 2
│   └── …                                # 47 files total
├── SwiftUMLStudioTests/                  # Swift Testing unit tests
├── SwiftUMLStudioUITests/                # XCTest UI tests
├── TestFixtures/SampleProject/           # Swift fixture for diagram extraction
└── docs/
    ├── user/                             # User guide, tutorial, reference
    └── internal/                         # PRD, plans
```

## Architecture

SwiftUMLBridge uses a three-layer architecture. Adding a new output format requires only a new emitter; the Studio app's native renderers consume the same model layer directly.

```
Parsing Layer          Model Layer            Emitter Layer
─────────────          ───────────            ─────────────
SourceKitten     →     Types, graphs,    →    PlantUML
SwiftSyntax            call edges,            Mermaid.js
                       control flow,          Nomnoml
                       import edges,          Native SVG (Studio)
                       ER models
```

## CLI Usage

### Class diagram

```bash
swiftumlbridge classdiagram Sources/ --format plantuml
swiftumlbridge classdiagram Sources/ --format mermaid --output file
swiftumlbridge classdiagram Sources/ --format nomnoml
```

### Sequence diagram

```bash
swiftumlbridge sequence --entry MyClass.myMethod Sources/ --depth 3
swiftumlbridge sequence --entry NetworkManager.fetch Sources/ --format mermaid
```

### Activity diagram

```bash
swiftumlbridge activity --entry MyService.processOrder Sources/
```

### State machine diagram

```bash
swiftumlbridge state Sources/ --format plantuml
```

### Entity-Relationship diagram (SwiftData / Core Data / GRDB / SQLite.swift)

```bash
# SwiftData @Model types
swiftumlbridge er Sources/Models/ --format mermaid

# Core Data .xcdatamodeld bundle (XML parsed via XMLDocument; honors .xccurrentversion)
swiftumlbridge er MyApp.xcdatamodeld --format plantuml

# GRDB record types (belongsTo / hasMany / hasOne become typed relationships)
swiftumlbridge er Sources/Database/Player.swift --format mermaid

# SQLite.swift schemas (Table("name") + Expression<T>("col") namespaces)
swiftumlbridge er Sources/Database/Schema.swift --format plantuml
```

### Dependency graph

```bash
swiftumlbridge deps Sources/ --modules
swiftumlbridge deps Sources/ --types --public-only
swiftumlbridge deps Sources/ --exclude Tests --format mermaid
```

### Component diagram (SPM-aware)

```bash
swiftumlbridge component --package /path/to/MyPackage           # PlantUML by default
swiftumlbridge component --package . --format mermaid           # Mermaid flowchart fallback
swiftumlbridge component --package . --include-test-targets     # opt in to test components
```

### Common flags

```
--format plantuml|mermaid|nomnoml   Output format (default: plantuml)
--output browser|console|file       Destination (default: browser)
--config <path>                     Path to .swiftumlbridge.yml
--depth <n>                         Call depth for sequence diagrams (default: 3)
--ci                                CI mode: no browser, write to file, exit non-zero on error
```

## Configuration

Create `.swiftumlbridge.yml` in your project root:

```yaml
format: mermaid
files:
  include:
    - "Sources/**/*.swift"
  exclude:
    - "**/*Tests*"
elements:
  accessLevel: internal
```

## Building

### CLI / Framework (Swift Package)

```bash
swift build --package-path SwiftUMLBridge
swift test  --package-path SwiftUMLBridge
swift run   --package-path SwiftUMLBridge swiftumlbridge classdiagram Sources/
```

### macOS Studio app (Xcode project)

```bash
xcodebuild -scheme SwiftUMLStudio -destination 'generic/platform=macOS' build
xcodebuild test -scheme SwiftUMLStudio -destination 'platform=macOS,arch=arm64'
```

## Dependencies

| Package | Role | License |
|---|---|---|
| [SourceKitten](https://github.com/jpsim/SourceKitten) | Swift AST parsing (declarations) | MIT |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | Call graph + control flow extraction | Apache 2.0 |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI | Apache 2.0 |
| [Yams](https://github.com/jpsim/Yams) | YAML configuration | MIT |
| SwiftData | Studio persistence | Apple SDK |
| StoreKit 2 | Studio subscriptions | Apple SDK |
| WebKit | Studio diagram fallback | Apple SDK |

## Documentation

- **User guide** — [`docs/user/`](docs/user/)
- **PRD** (Bridge + Studio) — [`docs/internal/SwiftUML Studio PRD.md`](docs/internal/SwiftUML%20Studio%20PRD.md)
- **Changelog** — [`CHANGELOG.md`](CHANGELOG.md)

## Known Limitations

- **Actors** — SourceKit on macOS 26 reports actor declarations with kind `source.lang.swift.decl.class`. Actors appear in diagrams with a class stereotype until SourceKit is updated.
- **async/throws labels** — Detection via SourceKit's `key.typename` is unreliable for some signatures; SwiftSyntax-based parsing covers the gaps for newer features.
- **Macros** — Macro-aware stereotypes are emitted via `MacroConformanceTable` for known macros (`@Observable`, `@Model`, etc.); full macro expansion is not yet performed.

## License

- **SwiftUMLBridge** (CLI + framework) — MIT
- **SwiftUMLStudio** (macOS app) — closed-source / paid (App Store)
