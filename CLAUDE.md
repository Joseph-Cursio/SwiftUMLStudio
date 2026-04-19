# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SwiftUMLStudio** is a macOS SwiftUI app (GUI studio) that serves as a front-end for **SwiftUMLBridge** — a Swift-native CLI tool and Swift Package that generates architectural diagrams (PlantUML, Mermaid.js) from Swift source code. SwiftUMLBridge modernizes and extends SwiftPlantUML with support for Swift 5.9+ features (actors, async/await, macros).

This repository is in early development (day 0). The PRD lives in `docs/SwiftUML Studio PRD.md`.

## Build & Test Commands

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

- **Target platform**: macOS 26.4+, `SDKROOT = macosx`
- **Bundle ID**: `name.JosephCursio.SwiftUMLStudio`

## Architecture

### Planned Three-Layer Architecture (per PRD)

```
Parsing Layer  →  Model Layer  →  Emitter Layer
(SourceKitten)    (language-      (PlantUML /
                   agnostic        Mermaid.js /
                   AST/graph)      DOT emitters)
```

1. **Parsing Layer** — wraps SourceKitten to extract the Swift AST and resolve types. Must track each Swift toolchain release.
2. **Model Layer** — language-agnostic representation of types, relationships, and call graphs (stored as graph structures).
3. **Emitter Layer** — format-specific emitters. Adding a new output format requires only a new emitter implementation.

The **CLI** (`swiftumlbridge`) is a thin wrapper over the framework. The **macOS Studio app** (`SwiftUMLStudio`) is a SwiftUI GUI front-end over the same framework.

### CLI Commands (planned)

```
swiftumlbridge classdiagram [paths...] [--format plantuml|mermaid] [--output browser|console|file]
swiftumlbridge sequence --entry <Type.method> [paths...] [--depth n]
swiftumlbridge deps [paths...] [--modules] [--types]
```

### Key Planned Dependencies

| Dependency | Role |
|---|---|
| SourceKitten | Swift AST parsing |
| Swift Argument Parser | CLI |
| Yams | YAML config parsing |

## Testing

- **Unit tests** use the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`). Do not use XCTest for new unit tests.
- **UI tests** use XCTest (`SwiftUMLStudioUITests`).
- Target ≥ 80% test coverage per the PRD.
