# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains two related products built around the same diagram-generation engine:

- **SwiftUMLBridge** — a Swift-native CLI (`swiftumlbridge`) and Swift Package that generates architectural diagrams from Swift source. A modern, Swift 6 evolution of SwiftPlantUML with support for actors, async/await, macros, and multi-format output.
- **SwiftUMLStudio** — a macOS SwiftUI application that embeds SwiftUMLBridge and provides an interactive workspace with persistent snapshots, native-canvas rendering, architectural insights, and a paid (StoreKit) tier.

**Status (2026-05)**: post-M10 (Swift 6 strict concurrency). M0–M10 shipped. Currently preparing the Bridge v1.0 release (CHANGELOG sync, .spi.yml, Homebrew formula, migration guide). See `docs/internal/SwiftUML Studio PRD.md` for the canonical spec — sections 5 (Bridge) and 6 (Studio) — and `CHANGELOG.md` for shipped scope.

## Build & Test Commands

### macOS Studio app (Xcode project)

```bash
# Build
xcodebuild -scheme SwiftUMLStudio -destination 'generic/platform=macOS' build

# Run all tests
xcodebuild test -scheme SwiftUMLStudio -destination 'platform=macOS,arch=arm64'

# Run a single unit test
xcodebuild test -scheme SwiftUMLStudio -destination 'platform=macOS,arch=arm64' \
  -only-testing:SwiftUMLStudioTests/SwiftUMLStudioTests/<TestName>

# Run a single UI test
xcodebuild test -scheme SwiftUMLStudio -destination 'platform=macOS,arch=arm64' \
  -only-testing:SwiftUMLStudioUITests/SwiftUMLStudioUITests/<TestName>
```

### SwiftUMLBridge package (CLI + framework)

```bash
# Build & test the package directly (faster iteration than xcodebuild)
swift build --package-path SwiftUMLBridge
swift test  --package-path SwiftUMLBridge

# Run the CLI from a checkout
swift run --package-path SwiftUMLBridge swiftumlbridge classdiagram <paths...>
```

- **Studio target platform**: macOS 26.4+, `SDKROOT = macosx`
- **Bridge target platform**: macOS 26+ (per `Package.swift`; tighten if Linux support is added)
- **Swift toolchain**: Swift 6.0 strict concurrency enabled across all targets
- **Bundle ID**: `name.JosephCursio.SwiftUMLStudio`

## Architecture

### Three-Layer Engine (SwiftUMLBridge)

```
Parsing Layer  →  Model Layer  →  Emitter Layer
SourceKitten      Language-       PlantUML /
SwiftSyntax       agnostic AST    Mermaid.js /
                  + graphs        Nomnoml
```

1. **Parsing Layer** (`SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/`) — wraps SourceKitten and SwiftSyntax to extract Swift declarations, call graphs, control flow, and import edges. Must track each Swift toolchain release.
2. **Model Layer** (`Model/`) — language-agnostic representation of types, relationships, call graphs, control-flow graphs, and SwiftData ER models.
3. **Emitter Layer** (`Emitters/`) — format-specific emitters. Adding a new output format requires only a new emitter implementation. The Studio app additionally consumes the model layer through native SwiftUI / Core Graphics renderers, bypassing string emission.

The **CLI** (`swiftumlbridge`) is a thin wrapper over the framework using `AsyncParsableCommand`. The **macOS Studio app** embeds the same framework as a Swift Package dependency.

### CLI Commands

```
swiftumlbridge classdiagram [paths...] [--format plantuml|mermaid] [--output browser|browserImageOnly|consoleOnly] [--package <Package.swift dir>]
swiftumlbridge sequence    --entry <Type.method> [paths...] [--depth n]
swiftumlbridge activity    --entry <Type.method> [paths...]
swiftumlbridge state       [paths...] [--list | --state HostType.EnumType]
swiftumlbridge er          [paths...]                  # SwiftData / Core Data / GRDB / SQLite.swift
swiftumlbridge deps        [paths...] [--modules] [--types] [--public-only] [--exclude <pattern>]
swiftumlbridge component   --package <Package.swift dir> [--include-test-targets]
```

### Studio App Layout (`SwiftUMLStudio/`)

- **Modes** (`AppMode.swift`): `explorer`, `developer` — toggled via the toolbar's Picker. Explorer is the default for new users; Developer exposes the three-pane workspace, file browser, format picker, and per-mode controls.
- **State**: `@Observable DiagramViewModel` (`DiagramViewModel.swift`, `DiagramViewModel+Generation.swift`)
- **Persistence**: SwiftData via `PersistenceController`, `DiagramEntity`, `ProjectSnapshot`, `SnapshotManager`
- **Rendering**: native `NativeDiagramView` / `NativeSequenceDiagramView` / `NativeActivityDiagramView`; WebView fallback (`DiagramWebView`, `MermaidHTMLBuilder`, `NomnomlHTMLBuilder`)
- **Subscription / paywall**: `SubscriptionManager` (StoreKit 2), `SubscriptionProviding`, `FeatureGate`, `PaywallView`, `Configuration.storekit`
- **Insights**: `ProjectAnalyzer`, `InsightEngine`, `SuggestionEngine`, `SuggestionDispatcher` surfaced through `ProjectDashboardView` and `ArchitectureDiffView`

### Key Dependencies

| Dependency | Role |
|---|---|
| SourceKitten | Swift AST parsing (declarations, types) |
| swift-syntax / SwiftParser | Call graph + control flow extraction (M5 primary parser) |
| swift-argument-parser | CLI |
| Yams (6.0+) | YAML config parsing |
| SwiftData | Studio persistence |
| StoreKit 2 | Studio subscriptions |
| WebKit | Studio diagram fallback |

## Testing

- **Unit tests** use the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`, `#require`). Do not use XCTest for new unit tests.
- **UI tests** use XCTest (`SwiftUMLStudioUITests`).
- The Bridge package has its own test target (`SwiftUMLBridgeFrameworkTests`) — runs via `swift test --package-path SwiftUMLBridge`.
- Coverage targets: ≥ 80% for the Bridge package, ≥ 70% for the Studio app (including UI tests). Bridge currently sits ~89%.

## Conventions

- Follow `.swiftlint.yml` — fix violations rather than disabling rules. Identifier names should be 3+ chars (`database` not `db`, `identifier` not `id`).
- Make small, focused commits — one logical change per commit. Each commit should build cleanly and pass tests before the next.
- Use the task list (`TaskCreate` / `TaskUpdate`) for multi-step work.
