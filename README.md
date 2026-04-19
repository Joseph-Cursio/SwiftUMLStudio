# SwiftUMLStudio

A macOS SwiftUI app and Swift Package for generating architectural diagrams from Swift source code. Built on **SwiftUMLBridge** — a modern, Swift 6 native evolution of SwiftPlantUML with support for Mermaid.js, sequence diagrams, and dependency graphs.

## Features

| Diagram Type | PlantUML | Mermaid.js |
|---|---|---|
| Class diagrams | Yes | Yes |
| Sequence diagrams | Yes | Yes |
| Dependency graphs | Yes | Yes |

- **Class diagrams** — inheritance, protocol conformance, composition, access control
- **Sequence diagrams** — static call-graph analysis with async/sync arrow distinction, configurable depth
- **Dependency graphs** — type-level and module-level dependency analysis with cycle detection
- **Swift 6 strict concurrency** throughout the framework and CLI
- **macOS Studio app** — drag-and-drop source folders, live diagram preview, format switcher

## Requirements

- macOS 13+ (CLI / framework)
- macOS 26.4+ (Studio app)
- Xcode 16+ / Swift 6.0+

## Project Structure

```
SwiftUMLStudio/
├── SwiftUMLBridge/                  # Swift Package (CLI + framework)
│   └── Sources/
│       ├── SwiftUMLBridgeFramework/ # Three-layer framework
│       │   ├── Parsing/             # SourceKitten + SwiftSyntax AST extraction
│       │   ├── Model/               # Language-agnostic graph model
│       │   └── Emitters/            # PlantUML and Mermaid.js emitters
│       └── swiftumlbridge/          # CLI executable
│           └── Commands/            # classdiagram, sequence, deps
├── SwiftUMLStudio/             # macOS SwiftUI app
│   ├── ContentView.swift
│   ├── DiagramViewModel.swift
│   └── DiagramWebView.swift
└── docs/
    └── SwiftUML Studio PRD.md
```

## Architecture

SwiftUMLBridge uses a three-layer architecture. Adding a new output format requires only a new emitter.

```
Parsing Layer          Model Layer            Emitter Layer
─────────────          ───────────            ─────────────
SourceKitten     →     Types, graphs,    →    PlantUML
SwiftSyntax            call edges,            Mermaid.js
                       import edges
```

## CLI Usage

### Class Diagram

```bash
swiftumlbridge classdiagram Sources/ --format plantuml
swiftumlbridge classdiagram Sources/ --format mermaid --output file
```

### Sequence Diagram

```bash
swiftumlbridge sequence --entry MyClass.myMethod Sources/ --depth 3
swiftumlbridge sequence --entry NetworkManager.fetch Sources/ --format mermaid
```

### Dependency Graph

```bash
swiftumlbridge deps Sources/ --modules
swiftumlbridge deps Sources/ --types --public-only
swiftumlbridge deps Sources/ --exclude Tests --format mermaid
```

### Common Flags

```
--format plantuml|mermaid    Output format (default: plantuml)
--output browser|console|file  Destination (default: browser)
--config <path>              Path to .swiftumlbridge.yml
--depth <n>                  Call depth for sequence diagrams (default: 3)
--ci                         CI mode: no browser, write to file, exit non-zero on error
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

### CLI / Framework

```bash
cd SwiftUMLBridge
swift build
swift test
```

### macOS Studio App

```bash
xcodebuild -scheme SwiftUMLStudio -destination 'generic/platform=macOS' build
```

## Dependencies

| Package | Role | License |
|---|---|---|
| [SourceKitten](https://github.com/jpsim/SourceKitten) | Swift AST parsing | MIT |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | Call graph extraction | Apache 2.0 |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI | Apache 2.0 |
| [Yams](https://github.com/jpsim/Yams) | YAML configuration | MIT |

## Known Limitations

- **Actors** — SourceKit 6.3 on macOS 26 reports actor declarations with kind `source.lang.swift.decl.class`. Actors appear in diagrams with a class stereotype until SourceKit is updated.
- **async/throws labels** — Detection via SourceKit's `key.typename` is unreliable; full support requires SwiftSyntax-based method signature parsing.
- **Macros** — `@Observable` and similar macros parse as the underlying type; macro-specific nodes are not yet emitted.

## License

MIT
