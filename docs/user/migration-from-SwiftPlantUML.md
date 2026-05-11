# Migrating from SwiftPlantUML

SwiftUMLBridge is a Swift 6 evolution of [SwiftPlantUML](https://github.com/MarcoEidinger/SwiftPlantUML). The class-diagram surface is broadly compatible — same YAML configuration vocabulary, same `--format` story, same PlantUML output — but the CLI has been restructured into subcommands and a handful of behaviors changed. This page is a cheatsheet for SwiftPlantUML users who want to switch over.

If you started with SwiftUMLBridge directly, you don't need this page — see [user-guide.md](user-guide.md) and [reference.md](reference.md) instead.

---

## At a glance

| | SwiftPlantUML | SwiftUMLBridge |
|---|---|---|
| Binary | `swiftplantuml` | `swiftumlbridge` |
| Diagram types | Class only | Class, sequence, activity, state, deps, ER, **component** (7 total) |
| Output formats | PlantUML | PlantUML, Mermaid, Nomnoml, SVG (varies by diagram type) |
| Config file | `.swiftplantuml.yml` | `.swiftumlbridge.yml` |
| Toolchain | Swift 5.x | Swift 6.2 (strict concurrency) |
| Parser | SourceKitten only | SwiftSyntax primary + SourceKitten for declarations |
| Macros / actors / async | Not aware | First-class (`@Observable`, `@Model`, `actor`, `async`, etc.) |
| Library product | `SwiftPlantUMLFramework` | `SwiftUMLBridgeFramework` |

---

## CLI: subcommands replace the top-level invocation

SwiftPlantUML had one command that always produced a class diagram. SwiftUMLBridge groups every diagram type under a subcommand, so the same kind of class-diagram invocation now needs the `classdiagram` token explicitly:

```diff
- swiftplantuml ./Sources/MyLib --format plantuml --output browser
+ swiftumlbridge classdiagram ./Sources/MyLib --format plantuml --output browser
```

Subcommand list:

```
swiftumlbridge classdiagram   # Was the only mode in SwiftPlantUML
swiftumlbridge sequence       # New: call-graph sequence diagrams (--entry)
swiftumlbridge activity       # New: control-flow inside a single method (--entry)
swiftumlbridge state          # New: enum-driven state machines
swiftumlbridge deps           # New: type-level / module-level import dep graphs
swiftumlbridge er             # New: SwiftData / Core Data / GRDB / SQLite.swift ER
swiftumlbridge component      # New: SPM target graph
```

Run `swiftumlbridge <subcommand> --help` for the per-subcommand flag list, or read the [reference](reference.md).

---

## Class-diagram flag map

For the `classdiagram` subcommand, the SwiftPlantUML flag → SwiftUMLBridge flag mapping is:

| SwiftPlantUML | SwiftUMLBridge | Notes |
|---|---|---|
| _positional paths_ | _positional paths_ | Unchanged. Accepts files or directories. |
| `--config` | `--config` | Unchanged. Defaults search to `.swiftumlbridge.yml` (was `.swiftplantuml.yml`). |
| `--sdk` | `--sdk` | Unchanged. |
| `--output browser` / `consoleOnly` | Same values, plus `browserImageOnly` | New option renders the PNG/SVG without the surrounding HTML viewer. |
| _(no format option)_ | `--format plantuml|mermaid` | PlantUML is the default; Mermaid is new in 0.2.0. |
| `--extensions show|hide|asObjcLikeCategories` | `--extension-visualization` flag (`--show-extensions` etc.) | Renamed for clarity; same three semantics. |
| _(no module support)_ | `--package <Package.swift-dir>` | New module-aware mode. Each type is stamped with its owning SPM target and gets a module stereotype. |
| _(none)_ | `--verbose` | Standard verbose logging flag. |

---

## YAML configuration

The configuration shape is mostly the same. Rename your file from `.swiftplantuml.yml` to `.swiftumlbridge.yml` and the existing fields keep working:

```yaml
files:
  exclude:
    - "Tests/**"
elements:
  havingVisibility:
    - public
    - internal
hideShowCommands:
  - "hide empty members"
skinparamCommands:
  - "skinparam shadowing false"
relationships:
  showInheritance: true
stereotypes:
  protocol:
    color: lightblue
theme: amiga
texts:
  title: "MyLib"
includeRemoteURL: null
```

What's new on top:

- **`format:`** — top-level field, `plantuml` (default) or `mermaid`. Equivalent to passing `--format` on the CLI.

What changed:

- **Default `hideShowCommands` / `skinparamCommands`** — same defaults as SwiftPlantUML (`hide empty members`, `skinparam shadowing false`), but the entries are now explicit defaults you can override. Passing an empty list clears them entirely.
- **`theme:`** — still a string, still maps to the bundled PlantUML themes. Unchanged.
- **`stereotypes:`** — same shape, but new stereotypes are recognized for macro-detected conformances (e.g. `<<Observable>>`, `<<Model>>`) so you can theme them.

What's gone:

- Nothing intentional. If you find a field that SwiftPlantUML accepted and SwiftUMLBridge silently drops, please file an issue.

---

## Output: PlantUML output is broadly compatible

Class-diagram PlantUML output from SwiftUMLBridge is intended to render identically to SwiftPlantUML's. Differences you may notice:

- **Macro stereotypes**. SwiftUMLBridge surfaces synthetic conformances from macros (`@Observable` → `<<Observable>>`, `@Model` → `<<Model>>`, `@Resolver` → `<<Resolver>>`, etc.) via the `MacroConformanceTable`. SwiftPlantUML predates macros and doesn't emit these.
- **Actor / async**. Methods on `actor` types are tagged; `async` and `throws` modifiers are preserved in member signatures. SwiftPlantUML can't distinguish these.
- **Module stereotypes**. When `--package` is used, each type gets a second stereotype with its owning SPM target name (`<<class>> <<Networking>>`). No SwiftPlantUML equivalent.
- **Identifier quoting**. SwiftUMLBridge consistently quotes element names that contain `-`, `.`, or `+` in identifier positions (aliases). Diff-ing against SwiftPlantUML output you may see additional quotes.

---

## API: framework migration

If you embed the framework programmatically (rather than shelling out to the CLI), the import and entry-point have moved:

```diff
- import SwiftPlantUMLFramework
- ClassDiagramGenerator().generateScript(...)
+ import SwiftUMLBridgeFramework
+ ClassDiagramGenerator().generateScript(for: paths, with: .default, sdkPath: nil)
```

The Swift API itself is now Sendable-clean and prefers async/await for IO-bound surfaces (presenters, package describe). See [user-guide.md § Programmatic Use](user-guide.md#programmatic-use) for the current shape.

---

## Where to go from here

- [user-guide.md](user-guide.md) — full walkthrough for every subcommand.
- [reference.md](reference.md) — every flag, every YAML field, every public type.
- [studio-user-guide.md](studio-user-guide.md) — the macOS app that wraps the same engine if you don't want to live in a terminal.
- File an issue if you find a SwiftPlantUML workflow that doesn't have an obvious SwiftUMLBridge equivalent — those are bugs in the migration story.
