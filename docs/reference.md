# SwiftUMLBridge Reference Guide

Complete reference for all CLI options, YAML configuration fields, element kinds, relationship styles, themes, colors, and public framework types.

---

## Table of Contents

1. [CLI Reference](#cli-reference)
   - [Root Command](#root-command)
   - [classdiagram](#classdiagram)
   - [sequence](#sequence)
   - [deps](#deps)
2. [Configuration File Schema](#configuration-file-schema)
   - [files](#files)
   - [elements](#elements)
   - [hideShowCommands](#hideshowcommands)
   - [skinparamCommands](#skinparamcommands)
   - [includeRemoteURL](#includeremoteurl)
   - [theme](#theme)
   - [relationships](#relationships)
   - [stereotypes](#stereotypes)
   - [texts](#texts)
   - [format](#format)
3. [Diagram Formats](#diagram-formats)
   - [Class Diagrams](#class-diagrams)
   - [Sequence Diagrams](#sequence-diagrams)
   - [Dependency Graphs](#dependency-graphs)
4. [Element Kinds](#element-kinds)
5. [Access Levels](#access-levels)
6. [Relationship Arrows](#relationship-arrows)
7. [RelationshipStyle Properties](#relationshipstyle-properties)
8. [Themes](#themes)
9. [Colors](#colors)
10. [Output Destinations](#output-destinations)
11. [Glob Pattern Syntax](#glob-pattern-syntax)
12. [Framework API](#framework-api)
    - [ClassDiagramGenerator](#classdiagramgenerator)
    - [SequenceDiagramGenerator](#sequencediagramgenerator)
    - [DependencyGraphGenerator](#dependencygraphgenerator)
    - [DiagramFormat](#diagramformat)
    - [DepsMode](#depsmode)
    - [Configuration](#configuration)
    - [ConfigurationProvider](#configurationprovider)
    - [FileCollector](#filecollector)
    - [DiagramOutputting](#diagramoutputting)
    - [DiagramScript](#diagramscript)
    - [SequenceScript](#sequencescript)
    - [DepsScript](#depsscript)
    - [DiagramPresenting](#diagrampresenting)
    - [BrowserPresenter](#browserpresenter)
    - [ConsolePresenter](#consolepresenter)
    - [CallGraph](#callgraph)
    - [CallEdge](#calledge)
    - [DependencyGraphModel](#dependencygraphmodel)
    - [DependencyEdge](#dependencyedge)
    - [DependencyEdgeKind](#dependencyedgekind)
    - [ImportEdge](#importedge)
    - [BridgeLogger](#bridgelogger)
13. [Version](#version)
14. [Studio App Reference](#studio-app-reference)
    - [App Modes](#app-modes)
    - [Diagram Modes](#diagram-modes)
    - [Project Analysis](#project-analysis)
    - [Subscription and Feature Gating](#subscription-and-feature-gating)
    - [Core Data Entities](#core-data-entities)
    - [Architecture Diff](#architecture-diff)

---

## CLI Reference

### Root Command

```
swiftumlbridge [--version] [--help] <subcommand>
```

| Option | Description |
|---|---|
| `--version` | Print the tool version and exit (`0.1.0`) |
| `--help` | Print help and exit |

The default subcommand is `classdiagram`. Running `swiftumlbridge` with no verb is equivalent to `swiftumlbridge classdiagram`.

---

### classdiagram

Generate a PlantUML or Mermaid class diagram from Swift source files.

```
swiftumlbridge classdiagram [<paths>...] [options]
```

**Positional arguments:**

| Argument | Type | Description |
|---|---|---|
| `<paths>...` | `[String]` | Zero or more paths to `.swift` files or directories to scan recursively. Defaults to the current directory. Ignored when `files.include` patterns are set in the config file. |

**Options:**

| Option | Type | Default | Description |
|---|---|---|---|
| `--config <path>` | `String?` | `nil` | Path to a custom `.swiftumlbridge.yml` file. When omitted, looks for `.swiftumlbridge.yml` in the current directory, then falls back to built-in defaults. |
| `--exclude <path>...` | `[String]` | `[]` | File or directory paths to exclude. Takes precedence over positional path arguments. May be specified multiple times. |
| `--format <format>` | `DiagramFormat?` | `plantuml` | Diagram language. One of: `plantuml`, `mermaid`. Overrides the `format` field in the config file. |
| `--output <format>` | `ClassDiagramOutput?` | `browser` | Output destination. One of: `browser`, `browserImageOnly`, `consoleOnly`. |
| `--sdk <path>` | `String?` | `nil` | macOS SDK path for improved type inference. Typically `$(xcrun --show-sdk-path -sdk macosx)`. |
| `--show-extensions` | Flag | — | Show all extensions as separate nodes (overrides config file). |
| `--merge-extensions` | Flag | — | Fold extension members into parent type nodes (overrides config file). |
| `--hide-extensions` | Flag | — | Remove all extensions from the diagram (overrides config file). |
| `--verbose` | Flag | `false` | Enable verbose logging to stderr. |
| `--help` | Flag | — | Print subcommand help and exit. |

**Extension flags are mutually exclusive.** If more than one is passed, the last one wins.

**Examples:**

```bash
# Diagram all Swift files in Sources/, open in browser (PlantUML, default)
swiftumlbridge classdiagram Sources/

# Generate Mermaid output and open in Mermaid Live editor
swiftumlbridge classdiagram Sources/ --format mermaid

# Print Mermaid markup to stdout
swiftumlbridge classdiagram Sources/ --format mermaid --output consoleOnly

# Use a custom config, write PlantUML to stdout
swiftumlbridge classdiagram Sources/ --config ./docs/diagram.yml --output consoleOnly

# Diagram with SDK for better type resolution, open PNG
swiftumlbridge classdiagram Sources/ \
  --sdk "$(xcrun --show-sdk-path -sdk macosx)" \
  --output browserImageOnly

# Exclude generated files
swiftumlbridge classdiagram Sources/ --exclude Sources/Generated/ --exclude Sources/Mocks/

# Merge extensions for a compact overview
swiftumlbridge classdiagram Sources/ --merge-extensions
```

---

### sequence

Generate a PlantUML or Mermaid sequence diagram by statically tracing call edges from a named entry-point method.

```
swiftumlbridge sequence [<paths>...] --entry Type.method [options]
```

**Positional arguments:**

| Argument | Type | Description |
|---|---|---|
| `<paths>...` | `[String]` | Paths to `.swift` files or directories. Defaults to the current directory (`.`). |

**Required option:**

| Option | Type | Description |
|---|---|---|
| `--entry <Type.method>` | `String` | Entry point in `TypeName.methodName` form (e.g., `--entry ClassDiagramGenerator.generateScript`). Case-sensitive. |

**Options:**

| Option | Type | Default | Description |
|---|---|---|---|
| `--depth <n>` | `Int` | `3` | Maximum call-graph depth to traverse from the entry point. |
| `--format <format>` | `DiagramFormat?` | `plantuml` | Diagram language. One of: `plantuml`, `mermaid`. |
| `--output <format>` | `ClassDiagramOutput?` | `browser` | Output destination. One of: `browser`, `browserImageOnly`, `consoleOnly`. |
| `--config <path>` | `String?` | `nil` | Path to a custom `.swiftumlbridge.yml` config file. |
| `--sdk <path>` | `String?` | `nil` | macOS SDK path (reserved; not currently used by the sequence extractor). |
| `--help` | Flag | — | Print subcommand help and exit. |

**Call resolution rules:**

| Call pattern | Resolved as |
|---|---|
| `self.method()` | Same type as caller |
| `TypeName.method()` (uppercase receiver) | `TypeName` |
| `bareMethod()` (no receiver) | Same type as caller |
| `variable.method()` (lowercase receiver) | Unresolved — emitted as a note |
| Closure / complex expression call | Unresolved — emitted as a note |

Unresolved calls appear in the diagram as notes rather than arrows and are not expanded further during traversal.

**`await` detection:** Calls wrapped in an `await` expression are marked as async and rendered with a distinct arrow style.

**Examples:**

```bash
# Trace ClassDiagramGenerator.generateScript up to depth 3 (default), open in browser
swiftumlbridge sequence Sources/ --entry ClassDiagramGenerator.generateScript

# Same entry point, Mermaid format, printed to stdout
swiftumlbridge sequence Sources/ \
  --entry ClassDiagramGenerator.generateScript \
  --format mermaid --output consoleOnly

# Deeper traversal
swiftumlbridge sequence Sources/ --entry MyService.handle --depth 5

# Multiple source directories
swiftumlbridge sequence Sources/ Tests/ --entry AuthService.login
```

---

### deps

Generate a PlantUML or Mermaid dependency graph from Swift source files. Supports both type-level graphs (inheritance and conformance edges) and module-level graphs (import statement edges).

```
swiftumlbridge deps [<paths>...] [--modules] [--types] [--public-only] [--exclude <pattern>...] [--format <format>] [--output <output>] [--config <path>]
```

**Positional arguments:**

| Argument | Type | Description |
|---|---|---|
| `<paths>...` | `[String]` | Paths to `.swift` files or directories. Defaults to the current directory. |

**Flags:**

| Flag | Type | Description |
|---|---|---|
| `--modules` | `Bool` | Generate a module-level graph from import statements. Takes precedence over `--types` when both are set. |
| `--types` | `Bool` | Generate a type-level graph from inheritance and conformance relationships. This is the default when neither flag is set. |
| `--public-only` | `Bool` | Include only `open` and `public` types. Types mode only; has no effect in modules mode. |

**Options:**

| Option | Type | Default | Description |
|---|---|---|---|
| `--exclude <pattern>...` | `[String]` | `[]` | Exclude type or module names matching these glob patterns. May be specified multiple times. |
| `--format <format>` | `DiagramFormat?` | `plantuml` | Diagram language. One of: `plantuml`, `mermaid`. |
| `--output <format>` | `ClassDiagramOutput?` | `browser` | Output destination. One of: `browser`, `browserImageOnly`, `consoleOnly`. |
| `--config <path>` | `String?` | `nil` | Path to a custom `.swiftumlbridge.yml` config file. |
| `--help` | Flag | — | Print subcommand help and exit. |

**Config file usage:** Only `format`, `elements.havingAccessLevel`, and `elements.exclude` are read from the config file. All other fields (relationships, themes, stereotypes, etc.) are ignored by the `deps` subcommand.

**Examples:**

```bash
# Type-level dependency graph, PlantUML, open in browser
swiftumlbridge deps Sources/

# Module-level graph, Mermaid, print to stdout
swiftumlbridge deps Sources/ --modules --format mermaid --output consoleOnly

# Public types only, print to stdout
swiftumlbridge deps Sources/ --public-only --output consoleOnly

# Exclude standard library modules from a module-level graph
swiftumlbridge deps Sources/ --modules --exclude Foundation --exclude Swift

# Type-level graph excluding generated types
swiftumlbridge deps Sources/ --exclude "Generated*" --format mermaid
```

---

## Configuration File Schema

The configuration file is a YAML file named `.swiftumlbridge.yml`. All fields are optional. Any field you omit uses its built-in default. The `sequence` subcommand uses `format` from the config file; other fields (elements, relationships, etc.) are class-diagram–specific and are ignored by `sequence`.

**Annotated full schema:**

```yaml
# ─── files ─────────────────────────────────────────────────────────────────
files:
  include:
    # Glob patterns relative to the current directory.
    # When non-empty, positional <paths> arguments are ignored.
    # Type: [String]  Default: []
    - "Sources/**/*.swift"

  exclude:
    # Glob patterns. Matched files are excluded even if they match 'include'.
    # Type: [String]  Default: []
    - "Sources/Generated/**"
    - "Tests/**/Mock*.swift"

# ─── elements ──────────────────────────────────────────────────────────────
elements:
  havingAccessLevel:
    # Which type declarations (classes, structs, etc.) to include in the diagram.
    # Type: [AccessLevel]
    # Values: open | public | package | internal | private | fileprivate
    # Default: [open, public, package, internal, private, fileprivate]
    - public
    - internal

  showMembersWithAccessLevel:
    # Which member declarations (vars, funcs) to show inside included types.
    # Type: [AccessLevel]  Default: [open, public, package, internal, private, fileprivate]
    - public

  showMemberAccessLevelAttribute: true
    # When true, prefix each member with + (public/open), ~ (internal/package),
    # or - (private/fileprivate).
    # Type: Bool  Default: false

  showNestedTypes: true
    # When true, nested type declarations are shown as child nodes connected
    # by composition arrows (+-- in PlantUML; skipped in Mermaid).
    # Type: Bool  Default: true

  showGenerics: true
    # When true, generic type parameters (<T>, <Key, Value>) appear on type nodes.
    # Type: Bool  Default: true

  showExtensions: merged
    # Controls how extension declarations are rendered.
    # Type: all | merged | none
    #   all    — each extension is a separate node (default)
    #   merged — extension members are folded into the parent type node
    #   none   — extensions are hidden entirely
    # Also accepts Boolean: true → all, false → none
    # Default: all

  mergedExtensionMemberIndicator: "^"
    # String appended to member names that were merged from an extension.
    # Only applies when showExtensions: merged.
    # Type: String?  Default: nil

  exclude:
    # Glob patterns matched against type names (not file paths).
    # Matched types are excluded from the diagram.
    # Type: [String]  Default: []
    - "UIViewController"
    - "NS*"

# ─── hideShowCommands ──────────────────────────────────────────────────────
hideShowCommands:
  # Raw PlantUML 'hide' or 'show' directives inserted verbatim into the diagram.
  # Ignored when format is 'mermaid'. Class diagrams only.
  # Type: [String]  Default: ["hide empty members"]
  - "hide empty members"
  - "hide @unlinked"

# ─── skinparamCommands ─────────────────────────────────────────────────────
skinparamCommands:
  # Raw PlantUML 'skinparam' directives inserted verbatim into the diagram.
  # Ignored when format is 'mermaid'. Class diagrams only.
  # Type: [String]  Default: ["skinparam shadowing false"]
  - "skinparam shadowing false"
  - "skinparam sequenceMessageAlign center"

# ─── includeRemoteURL ──────────────────────────────────────────────────────
includeRemoteURL:
  # URL for a PlantUML '!include' directive. Useful for shared style libraries.
  # Ignored when format is 'mermaid'. Class diagrams only.
  # Type: String?  Default: nil
  "https://raw.githubusercontent.com/example/styles/main/custom.iuml"

# ─── theme ─────────────────────────────────────────────────────────────────
theme: minty
  # PlantUML theme name. camelCase names are converted to kebab-case automatically.
  # Use __directive__("name") to pass a raw PlantUML theme directive as-is.
  # Ignored when format is 'mermaid'. Class diagrams only.
  # Type: String?  Default: nil
  # See the Themes section for available values.

# ─── relationships ─────────────────────────────────────────────────────────
relationships:
  inheritance:
    # Solid arrow (<|--) for class inheritance (e.g., class Dog: Animal)
    label: "inherits from"    # Text label on the arrow. Type: String?  Default: nil
    exclude:
      # Parent names to suppress. Accepts glob patterns.
      # Type: [String]  Default: []
      - "NSObject"
    style:
      # Relationship style is applied to PlantUML output only; ignored for Mermaid.
      lineStyle: plain        # bold | dashed | dotted | hidden | plain
      lineColor: DarkGray     # HTML color name recognized by PlantUML
      textColor: DarkGray

  realize:
    # Dashed arrow (<|..) for protocol conformance (e.g., struct Foo: Bar)
    label: "conforms to"
    exclude:
      - "Codable"
      - "Sendable"
    style:
      lineStyle: dashed
      lineColor: RoyalBlue
      textColor: RoyalBlue

  dependency:
    # Dotted arrow (<..) for extension dependency connections
    label: "extends"
    style:
      lineStyle: dotted
      lineColor: DarkGreen
      textColor: DarkGreen

# ─── stereotypes ───────────────────────────────────────────────────────────
stereotypes:
  # Spot characters and colors apply to PlantUML output only.
  class:
    name: "class"             # Display name shown after the spot character. Type: String?
    spot:
      character: "C"          # Single character shown in the type spot circle. Type: String
      color: AliceBlue        # HTML color name for the spot circle. Type: String
  struct:
    spot:
      character: "S"
      color: AntiqueWhite
  extension:
    spot:
      character: "X"
      color: AntiqueWhite
  enum:
    spot:
      character: "E"
      color: AntiqueWhite
  protocol:
    spot:
      character: "P"
      color: AntiqueWhite

# ─── texts ─────────────────────────────────────────────────────────────────
texts:
  # Page text sections added to the diagram. All fields are optional.
  # PlantUML: rendered as header/title/legend/caption/footer blocks.
  # Mermaid: title, header, and footer are rendered as %% comment lines.
  #          legend and caption are not supported in Mermaid and are ignored.
  header: "CONFIDENTIAL"      # Top of every page
  title: "My Architecture"   # Diagram title
  legend: "Legend text"       # Legend box (PlantUML only)
  caption: "Fig. 1"          # Caption below the diagram (PlantUML only)
  footer: "Generated by swiftumlbridge"  # Bottom of every page

# ─── format ────────────────────────────────────────────────────────────────
format: plantuml
  # Diagram language for the generated output.
  # Type: plantuml | mermaid  Default: plantuml
  # Can be overridden at runtime with the --format CLI flag.
  # Applies to both classdiagram and sequence subcommands.
```

---

## Diagram Formats

SwiftUMLBridge supports two output diagram languages, applied to both class diagrams and sequence diagrams.

### Class Diagrams

#### PlantUML (default)

Set `format: plantuml` or pass `--format plantuml`. The generated script is wrapped in `@startuml` / `@enduml` and uses PlantUML class diagram syntax.

**Browser output:** The script is encoded and opened at [planttext.com](https://www.planttext.com).

**Script structure:**
```
@startuml
[!theme <name>]
[!include <url>]
' STYLE START
hide empty members
skinparam shadowing false
' STYLE END
set namespaceSeparator none
[header/title/legend/caption/footer blocks]
[type nodes]
[relationship arrows]
@enduml
```

**PlantUML-specific features:** themes, skinparam commands, hide/show commands, remote include URL, custom spot stereotypes, relationship line styles/colors, nested type `+--` composition connections.

#### Mermaid

Set `format: mermaid` or pass `--format mermaid`. The generated script starts with `classDiagram` and uses [Mermaid.js](https://mermaid.js.org) class diagram syntax.

**Browser output:** The script is base64-encoded and opened at [mermaid.live](https://mermaid.live).

**Script structure:**
```
classDiagram
[%% title: ...]
[%% header: ...]
[%% footer: ...]
[type nodes]
[relationship arrows]
```

**Mermaid-specific notes:**
- `hideShowCommands`, `skinparamCommands`, `includeRemoteURL`, `theme`, and `stereotypes` settings are ignored.
- `texts.legend` and `texts.caption` are ignored (not supported by Mermaid classDiagram).
- `texts.title`, `texts.header`, and `texts.footer` are emitted as `%% key: value` comment lines.
- Nested type composition connections (`+--`) are omitted (not supported by Mermaid classDiagram).
- Relationship line styles and colors are omitted (not supported by Mermaid classDiagram).
- Member format: variables as `Type name`, methods as `name()`, static members with `$` classifier suffix.

**Member syntax comparison:**

| Member | PlantUML | Mermaid |
|---|---|---|
| Instance variable | `name : Type` | `Type name` |
| Static variable | `{static} name : Type` | `Type name$` |
| Instance method | `name()` | `name()` |
| Static method | `{static} name()` | `name()$` |
| Enum case | `name` | `name` |

---

### Sequence Diagrams

Sequence diagrams trace the static call graph from an entry-point method using SwiftSyntax. Both PlantUML and Mermaid output are supported.

#### PlantUML sequence format

**Script structure:**
```
@startuml
title EntryType.entryMethod
participant EntryType
participant CalleeType
...

EntryType -> CalleeType : resolvedMethod()
EntryType ->> CalleeType : asyncMethod()
note right: Unresolved: variableCall()
@enduml
```

**Arrow styles:**

| Arrow | Meaning |
|---|---|
| `->` | Synchronous call |
| `->>` | Asynchronous call (wrapped in `await`) |

Unresolved calls (variable-receiver, closures) appear as `note right: Unresolved: expr()` and are not expanded further.

**Browser output:** Same encoding as class diagrams — opened at planttext.com.

#### Mermaid sequence format

**Script structure:**
```
sequenceDiagram
%% title: EntryType.entryMethod
participant EntryType
participant CalleeType
...

EntryType->>CalleeType: resolvedMethod()
EntryType-->>CalleeType: asyncMethod()
Note right of CalleeType: Unresolved: variableCall()
```

**Arrow styles:**

| Arrow | Meaning |
|---|---|
| `->>` | Synchronous call (solid arrowhead) |
| `-->>` | Asynchronous call (dashed, indicating async) |

Unresolved calls appear as `Note right of <lastParticipant>: Unresolved: expr()`.

**Browser output:** Same base64 JSON encoding as class diagrams — opened at mermaid.live.

#### Call resolution

The sequence extractor uses SwiftSyntax to walk function bodies. Only statically resolvable calls produce arrows. The following table summarizes resolution behavior:

| Source pattern | Resolved? | calleeType |
|---|---|---|
| `self.method()` | Yes | same as caller |
| `TypeName.method()` (uppercase) | Yes | `TypeName` |
| `bareMethod()` | Yes | same as caller |
| `variable.method()` (lowercase) | No | `nil` — emitted as note |
| `{ }()` or complex expression | No | `nil` — emitted as note |

#### Sequence diagram limitations

- **Variable-receiver calls are unresolved.** `dep.doWork()` where `dep` is a local variable or parameter cannot be statically resolved.
- **No dynamic dispatch resolution.** Protocol method calls through an existential are treated as same-type calls.
- **Entry point must exist.** If no functions match `Type.method` in the parsed sources, `SequenceScript.empty` is returned and the diagram is blank.
- **Depth applies per unique caller.** Each `Type.method` pair is visited at most once, regardless of depth.

---

### Dependency Graphs

Dependency graphs visualize how types or modules depend on one another. The `deps` subcommand produces one of two graph kinds depending on the mode flag:

- **Types mode** (default): edges represent inheritance (`inherits`) and protocol conformance (`conforms`).
- **Modules mode** (`--modules`): edges represent import statements (`imports`), with the source module name derived from the parent directory of each source file.

Both PlantUML and Mermaid output are supported.

#### PlantUML dependency graph format

**Script structure:**

```
@startuml
Dog --> Animal : inherits
Report --> Printable : conforms
App --> Foundation : imports

note as CyclicDependencies
  Cyclic nodes: ModA, ModB
end note
@enduml
```

- Each edge is rendered as `From --> To : kind`, where `kind` is one of `inherits`, `conforms`, or `imports`.
- Cyclic nodes are detected via DFS and listed together in a `note as CyclicDependencies` block at the end of the script. The note is omitted when no cycles are detected.
- Browser output uses the same ZLIB deflate + custom base64 encoding as class and sequence diagrams, opened at planttext.com.

#### Mermaid dependency graph format

**Script structure:**

```
graph TD
    Animal["Animal"]
    Dog["Dog"]
    Printable["Printable"]
    Report["Report"]

    Dog --> Animal
    Report --> Printable

    style ModA fill:#ffcccc,stroke:#cc0000
    style ModB fill:#ffcccc,stroke:#cc0000
```

- Header is `graph TD`.
- Each unique node is declared as `SafeId["DisplayName"]`, with nodes sorted alphabetically.
- Edges are rendered as `FromId --> ToId` with no label (Mermaid flowchart graphs do not support per-edge labels in the same way PlantUML does).
- Cyclic nodes receive a `style SafeId fill:#ffcccc,stroke:#cc0000` line (red fill and border). Style lines are omitted when no cycles are detected.
- Node IDs are sanitized: spaces, dots, angle brackets, and hyphens are replaced with underscores to produce valid Mermaid identifiers.
- Browser output uses the same base64 JSON encoding as Mermaid class and sequence diagrams, opened at mermaid.live.

---

## Element Kinds

SwiftUMLBridge recognizes these Swift declaration kinds:

| Kind | SourceKit Raw Value | Notes |
|---|---|---|
| `class` | `source.lang.swift.decl.class` | |
| `struct` | `source.lang.swift.decl.struct` | |
| `enum` | `source.lang.swift.decl.enum` | |
| `protocol` | `source.lang.swift.decl.protocol` | |
| `extension` | `source.lang.swift.decl.extension` | |
| `extensionClass` | `source.lang.swift.decl.extension.class` | |
| `extensionEnum` | `source.lang.swift.decl.extension.enum` | |
| `extensionProtocol` | `source.lang.swift.decl.extension.protocol` | |
| `extensionStruct` | `source.lang.swift.decl.extension.struct` | |
| `typealias` | `source.lang.swift.decl.typealias` | |
| `associatedtype` | `source.lang.swift.decl.associatedtype` | |
| `actor` | `source.lang.swift.decl.actor` | Parses as `.class` in SourceKit 6.3 (see Known Limitations) |
| `macro` | `source.lang.swift.decl.macro` | PlantUML: `note` block; Mermaid: `%% macro:` comment |
| `varInstance` | `source.lang.swift.decl.var.instance` | |
| `varStatic` | `source.lang.swift.decl.var.static` | |
| `varClass` | `source.lang.swift.decl.var.class` | |
| `functionMethodInstance` | `source.lang.swift.decl.function.method.instance` | |
| `functionMethodStatic` | `source.lang.swift.decl.function.method.static` | |
| `functionConstructor` | `source.lang.swift.decl.function.constructor` | |
| `enumcase` | `source.lang.swift.decl.enumcase` | Container for enum elements |
| `enumelement` | `source.lang.swift.decl.enumelement` | Individual case shown by name |

All other kinds are silently skipped during diagram generation.

**Diagram-renderable kinds:** `class`, `struct`, `enum`, `protocol`, `extension` (all variants), `actor`, `macro`.

---

## Access Levels

Access level values used in `havingAccessLevel` and `showMembersWithAccessLevel`:

| Value | Swift keyword | Indicator |
|---|---|---|
| `open` | `open` | `+` |
| `public` | `public` | `+` |
| `package` | `package` | `~` |
| `internal` | `internal` (default) | `~` |
| `fileprivate` | `fileprivate` | `-` |
| `private` | `private` | `-` |

The indicator prefix is applied when `showMemberAccessLevelAttribute: true`. The same `+`/`~`/`-` symbols are used in both PlantUML and Mermaid output.

**Default access level filter:** All six levels are included by default. To show only public API:

```yaml
elements:
  havingAccessLevel:
    - public
    - open
```

---

## Relationship Arrows

Arrow notation used in generated class diagrams. Both PlantUML and Mermaid use the same arrow strings for inheritance, conformance, and extension connections.

| Arrow | Syntax | Meaning |
|---|---|---|
| Inheritance | `Child <\|-- Parent` | `class Dog: Animal` |
| Realization (conformance) | `Type <\|.. Protocol` | `struct Foo: Equatable` |
| Extension dependency | `Extension <.. Type` | Extension on a named type |
| Composition (nested) | `Outer +-- Inner` | Nested type declaration **(PlantUML only)** |
| Generic link | `A -- B` | Generic relationship |

For sequence diagram arrows, see [Sequence Diagrams](#sequence-diagrams).

---

## RelationshipStyle Properties

Each of `relationships.inheritance`, `relationships.realize`, and `relationships.dependency` accepts an optional `style` block. Style properties apply to PlantUML output only and are ignored when `format: mermaid`.

### lineStyle

Controls the line stroke:

| Value | Appearance |
|---|---|
| `plain` | Solid line (default) |
| `bold` | Thicker solid line |
| `dashed` | Dashed line |
| `dotted` | Dotted line |
| `hidden` | Line is invisible (layout only) |

### lineColor and textColor

Any HTML color name recognized by PlantUML. Common values:

| Color Name | Hex |
|---|---|
| `Black` | `#000000` |
| `White` | `#FFFFFF` |
| `Red` | `#FF0000` |
| `Green` | `#008000` |
| `Blue` | `#0000FF` |
| `DarkGray` | `#A9A9A9` |
| `DarkGreen` | `#006400` |
| `DarkViolet` | `#9400D3` |
| `RoyalBlue` | `#4169E1` |
| `AliceBlue` | `#F0F8FF` |
| `AntiqueWhite` | `#FAEBD7` |

See the [Colors](#colors) section for a broader list.

**Example style block:**

```yaml
relationships:
  inheritance:
    style:
      lineStyle: dashed
      lineColor: RoyalBlue
      textColor: RoyalBlue
```

This emits: `#line:RoyalBlue;line.dashed;text:RoyalBlue` inline on the PlantUML relationship arrow.

---

## Themes

Set a PlantUML built-in theme with the `theme` key. camelCase names are automatically converted to kebab-case (e.g., `carbonGray` → `carbon-gray`). This setting is ignored when `format: mermaid`.

**Preferred themes (tested):**

| Config Value | PlantUML Theme |
|---|---|
| `default` | Default light theme |
| `minty` | Light pastel |
| `hacker` | Dark green on black |
| `materia` | Material Design light |
| `cyborg` | Dark with blue accents |
| `sketchy` | Hand-drawn look |
| `sketchyOutline` | `sketchy-outline` |
| `carbonGray` | `carbon-gray` |
| `reddress-darkBlue` | Dark blue header style |
| `reddress-darkOrange` | Dark orange header style |
| `reddress-darkRed` | Dark red header style |
| `reddress-darkGreen` | Dark green header style |
| `reddress-lightBlue` | Light blue header style |
| `spacelab` | Bootstrap-inspired |
| `amiga` | Retro Amiga palette |
| `cerulean` | Blue-gray |
| `superhero` | Dark with purple accents |

**Using a raw PlantUML directive:**

```yaml
theme: "__directive__(\"!theme hacker from https://example.com/themes\")"
```

The `__directive__(...)` syntax passes the string verbatim to PlantUML, bypassing the camelCase-to-kebab-case conversion. Use this for custom or remotely hosted themes.

---

## Colors

PlantUML accepts any HTML 4 color name. A representative set:

### Reds
`Red`, `DarkRed`, `Crimson`, `Firebrick`, `IndianRed`, `LightCoral`, `Salmon`, `Tomato`, `OrangeRed`

### Oranges
`Orange`, `DarkOrange`, `Coral`, `SandyBrown`, `Peru`, `Chocolate`, `Sienna`, `SaddleBrown`

### Yellows
`Yellow`, `Gold`, `Goldenrod`, `DarkGoldenrod`, `PaleGoldenrod`, `Khaki`, `DarkKhaki`

### Greens
`Green`, `DarkGreen`, `LimeGreen`, `Lime`, `ForestGreen`, `SeaGreen`, `MediumSeaGreen`, `SpringGreen`, `YellowGreen`, `OliveDrab`, `Olive`, `DarkOliveGreen`

### Blues
`Blue`, `DarkBlue`, `MediumBlue`, `Navy`, `RoyalBlue`, `CornflowerBlue`, `SteelBlue`, `DodgerBlue`, `DeepSkyBlue`, `SkyBlue`, `LightSkyBlue`, `LightBlue`, `AliceBlue`, `CadetBlue`

### Purples/Violets
`Purple`, `DarkViolet`, `DarkMagenta`, `Magenta`, `Violet`, `Orchid`, `MediumOrchid`, `MediumPurple`, `BlueViolet`, `Indigo`, `SlateBlue`, `MediumSlateBlue`

### Grays
`Black`, `DarkGray`, `Gray`, `DimGray`, `LightGray`, `Silver`, `Gainsboro`, `WhiteSmoke`, `White`

### Whites/Neutrals
`AntiqueWhite`, `Beige`, `Bisque`, `BlanchedAlmond`, `Cornsilk`, `FloralWhite`, `Ivory`, `Linen`, `MintCream`, `MistyRose`, `OldLace`, `Seashell`, `Snow`

> **Complete list:** See the [PlantUML color reference](https://plantuml.com/color) for the full set of recognized names.

---

## Output Destinations

Controlled by the `--output` CLI flag. Applies to both PlantUML and Mermaid formats, and to both `classdiagram` and `sequence` subcommands.

| Value | PlantUML behavior | Mermaid behavior |
|---|---|---|
| `browser` | Opens interactive planttext.com editor | Opens Mermaid Live editor (`mermaid.live`) |
| `browserImageOnly` | Opens a PNG render at planttext.com | Same as `browser` for Mermaid |
| `consoleOnly` | Prints raw PlantUML to stdout | Prints raw Mermaid to stdout |

**PlantUML encoding:** ZLIB deflate followed by PlantUML's custom base64 alphabet (`0-9A-Za-z-_=`).

**Mermaid encoding:** The script text and a theme config object are JSON-encoded and then base64-encoded, per the Mermaid Live URL format.

---

## Glob Pattern Syntax

Used in `files.include`, `files.exclude`, `elements.exclude`, and `relationships.*.exclude`.

| Pattern | Matches |
|---|---|
| `*` | Any sequence of characters (not path separators in single `*`) |
| `**` | Any sequence including path separators (recursive) |
| `?` | Any single character |
| `{a,b}` | Either `a` or `b` (brace expansion) |
| Plain string | Substring match anywhere in the path |

**Examples:**

```yaml
files:
  include:
    - "Sources/**/*.swift"          # all .swift under Sources/
    - "Sources/App/**"              # everything under Sources/App/

  exclude:
    - "**/Generated/**"             # any Generated/ directory at any depth
    - "Tests/**/Mock*.swift"        # files starting with Mock in any Tests/ subdir
    - "**/__Snapshots__/**"         # snapshot test directories

elements:
  exclude:
    - "NS*"                         # any type starting with NS
    - "UI*"                         # any type starting with UI
    - "Generated*"                  # generated types

relationships:
  inheritance:
    exclude:
      - "Codable"                   # exact match
      - "NS*"                       # wildcard match
```

**`elements.exclude` patterns match against type names (not file paths).** `files.include` and `files.exclude` patterns match against file paths relative to the working directory.

---

## Framework API

SwiftUMLBridge is also usable as a Swift Package library (`SwiftUMLBridgeFramework`). Add it to your `Package.swift`:

```swift
.package(path: "../SwiftUMLBridge"),

// In your target:
.product(name: "SwiftUMLBridgeFramework", package: "SwiftUMLBridge"),
```

---

### ClassDiagramGenerator

```swift
public struct ClassDiagramGenerator
```

Top-level orchestrator for class diagrams. Stateless — all state accumulates in `DiagramScript` and `DiagramContext`.

**Methods:**

```swift
// Generate from file paths (async, with presenter)
func generate(
    for paths: [String],
    with configuration: Configuration,
    presentedBy presenter: any DiagramPresenting,
    sdkPath: String?
) async

// Generate from source string (useful for testing / in-memory use, async)
func generate(
    from content: String,
    with configuration: Configuration,
    presentedBy presenter: any DiagramPresenting
) async

// Generate a DiagramScript synchronously from file paths (for GUI integration)
func generateScript(
    for paths: [String],
    with configuration: Configuration,
    sdkPath: String?
) -> DiagramScript
```

**Example (CLI/async):**

```swift
import SwiftUMLBridgeFramework

let generator = ClassDiagramGenerator()
var config = Configuration.default
config.format = .mermaid
let presenter = ConsolePresenter()

await generator.generate(
    for: ["Sources/"],
    with: config,
    presentedBy: presenter,
    sdkPath: nil
)
```

**Example (GUI/synchronous):**

```swift
let script = ClassDiagramGenerator().generateScript(
    for: ["/path/to/Sources"],
    with: Configuration(format: .mermaid)
)
print(script.text)
```

---

### SequenceDiagramGenerator

```swift
public struct SequenceDiagramGenerator
```

Generates sequence diagrams by walking Swift source files with SwiftSyntax, building a call graph, and rendering a `SequenceScript`.

**Methods:**

```swift
// Generate a SequenceScript synchronously
func generateScript(
    for paths: [String],
    entryType: String,
    entryMethod: String,
    depth: Int = 3,
    with configuration: Configuration = .default
) -> SequenceScript
```

**Example:**

```swift
import SwiftUMLBridgeFramework

var config = Configuration.default
config.format = .mermaid

let script = SequenceDiagramGenerator().generateScript(
    for: ["Sources/"],
    entryType: "AuthService",
    entryMethod: "login",
    depth: 4,
    with: config
)
print(script.text)
```

When no matching entry point is found, returns `SequenceScript.empty` (blank diagram text).

---

### DependencyGraphGenerator

```swift
public struct DependencyGraphGenerator
```

Top-level orchestrator for dependency graphs. Stateless — produces a `DepsScript` from source paths and a mode.

**Methods:**

```swift
public init()

public func generateScript(
    for paths: [String],
    mode: DepsMode,
    with configuration: Configuration = .default
) -> DepsScript
```

**Types mode behavior:** Uses `FileCollector` and `SyntaxStructure.create()` to parse Swift declarations. Applies `configuration.elements.havingAccessLevel` and `configuration.elements.exclude` filters. Class elements produce `.inherits` edges; struct, enum, actor, and protocol elements produce `.conforms` edges. Compound conformance annotations such as `A & B` are split into individual edges.

**Modules mode behavior:** Reads each file as a plain string and runs `ImportExtractor`. The source module name is the last path component of the file's parent directory. Access-level and exclude filters do not apply in modules mode.

**Example:**

```swift
import SwiftUMLBridgeFramework

var config = Configuration.default
config.format = .mermaid

let script = DependencyGraphGenerator().generateScript(
    for: ["Sources/"],
    mode: .types,
    with: config
)
print(script.text)
```

---

### DepsMode

```swift
public enum DepsMode: String, CaseIterable, Sendable
```

Controls whether `DependencyGraphGenerator` builds a type-level or module-level graph.

| Case | Raw value | Description |
|---|---|---|
| `.types` | `"Types"` | Type-level graph: inheritance and conformance edges derived from Swift declarations. |
| `.modules` | `"Modules"` | Module-level graph: import edges derived from `import` statements in each file. |

Pass to `DependencyGraphGenerator.generateScript(for:mode:with:)` or select via the `--modules` / `--types` CLI flags.

---

### DiagramFormat

```swift
public enum DiagramFormat: String, Codable, Sendable, CaseIterable
```

The diagram language for generated output. Applies to both class and sequence diagrams.

| Case | Raw value | Description |
|---|---|---|
| `.plantuml` | `"plantuml"` | PlantUML syntax (default) |
| `.mermaid` | `"mermaid"` | Mermaid.js syntax |

Set on `Configuration.format` or via the `--format` CLI flag.

---

### Configuration

```swift
public struct Configuration: Codable, Sendable
```

The complete configuration object.

| Property | Type | Default |
|---|---|---|
| `files` | `FileOptions` | Empty include/exclude |
| `elements` | `ElementOptions` | All access levels, generics on, nested types on, all extensions |
| `hideShowCommands` | `[String]?` | `["hide empty members"]` |
| `skinparamCommands` | `[String]?` | `["skinparam shadowing false"]` |
| `includeRemoteURL` | `String?` | `nil` |
| `theme` | `Theme?` | `nil` |
| `relationships` | `RelationshipOptions` | Default labels and styles |
| `stereotypes` | `Stereotypes` | Default spot characters and colors |
| `texts` | `PageTexts?` | `nil` |
| `format` | `DiagramFormat` | `.plantuml` |

```swift
// Built-in defaults
static let `default`: Configuration
```

**Example — Mermaid configuration:**

```swift
var config = Configuration.default
config.format = .mermaid
```

Or via the memberwise initializer:

```swift
let config = Configuration(format: .mermaid)
```

---

### ConfigurationProvider

```swift
public struct ConfigurationProvider
```

Loads a `Configuration` from YAML.

```swift
// Load config from an optional explicit path, falling back to CWD search and defaults
func getConfiguration(for path: String?) -> Configuration

// Look for .swiftumlbridge.yml in the current working directory
func readSwiftConfig() -> Configuration

// Decode a specific YAML file
func decodeYml(config: URL) -> Configuration?

// Default file name and path
var defaultYmlPath: URL     // <CWD>/.swiftumlbridge.yml
var defaultConfig: Configuration
```

Invalid or missing YAML always falls back to `Configuration.default` — it never throws.

---

### FileCollector

```swift
public struct FileCollector
```

Enumerates `.swift` files from paths. Respects `FileOptions` include/exclude globs. Skips hidden files and `.build/` directories.

```swift
// Collect files from paths relative to a directory, applying FileOptions
func getFiles(for paths: [String], in directory: String, honoring fileOptions: FileOptions?) -> [URL]

// Collect files from paths relative to a directory (no filter)
func getFiles(for paths: [String], in directory: String) -> [URL]

// Recursively collect all .swift files under a URL
func getFiles(for url: URL) -> [URL]
```

---

### DiagramOutputting

```swift
public protocol DiagramOutputting: Sendable
```

The shared protocol for all diagram output types. `DiagramScript` (class diagrams), `SequenceScript` (sequence diagrams), and `DepsScript` (dependency graphs) all conform to this protocol. Use it when your code needs to handle any diagram type without specializing.

```swift
var text: String { get }          // The raw diagram markup
var format: DiagramFormat { get } // .plantuml or .mermaid
func encodeText() -> String       // PlantUML URL encoding (ZLIB + custom base64)
```

**Custom presenter example using the protocol:**

```swift
struct FileSaver: DiagramPresenting {
    let url: URL

    func present(script: any DiagramOutputting) async {
        try? script.text.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

**Format-aware file saver:**

```swift
struct SmartFileSaver: DiagramPresenting {
    let directory: URL

    func present(script: any DiagramOutputting) async {
        let ext = script.format == .mermaid ? "mmd" : "puml"
        let file = directory.appendingPathComponent("diagram.\(ext)")
        try? script.text.write(to: file, atomically: true, encoding: .utf8)
    }
}
```

---

### DiagramScript

```swift
public struct DiagramScript: @unchecked Sendable, DiagramOutputting
```

Builds the complete class diagram text from a `[SyntaxStructure]` list and a `Configuration`.

```swift
// Build the script
init(items: [SyntaxStructure], configuration: Configuration)

// The full diagram text (PlantUML or Mermaid depending on configuration.format)
var text: String

// The diagram language
var format: DiagramFormat

// PlantUML URL-encoded form (ZLIB deflate + custom base64). Used for planttext.com URLs.
func encodeText() -> String
```

---

### SequenceScript

```swift
public struct SequenceScript: Sendable, DiagramOutputting
```

Holds a rendered sequence diagram. Produced by `SequenceDiagramGenerator`. Conforms to `DiagramOutputting` and can be passed directly to any presenter.

```swift
var text: String          // The sequence diagram markup
var format: DiagramFormat // .plantuml or .mermaid
func encodeText() -> String  // PlantUML URL encoding

// Returned when the entry point doesn't match any source, or when traversal yields nothing
static let empty: SequenceScript
```

**Participant ordering:** Participants appear in the order they are first seen in the traversal — the entry type is always listed first.

**PlantUML output sample:**

```
@startuml
title MyService.process
participant MyService
participant Database

MyService -> Database : fetchRecord()
MyService ->> Database : asyncFlush()
note right: Unresolved: completion()
@enduml
```

**Mermaid output sample:**

```
sequenceDiagram
%% title: MyService.process
participant MyService
participant Database

MyService->>Database: fetchRecord()
MyService-->>Database: asyncFlush()
Note right of Database: Unresolved: completion()
```

---

### DepsScript

```swift
public struct DepsScript: Sendable, DiagramOutputting
```

Holds a rendered dependency graph. Produced by `DependencyGraphGenerator`. Conforms to `DiagramOutputting` and can be passed directly to any presenter.

```swift
var text: String          // The dependency graph markup
var format: DiagramFormat // .plantuml or .mermaid
func encodeText() -> String  // Same ZLIB + custom base64 encoding as DiagramScript
```

**PlantUML output sample:**

```
@startuml
Dog --> Animal : inherits
Report --> Printable : conforms

note as CyclicDependencies
  Cyclic nodes: ModA, ModB
end note
@enduml
```

**Mermaid output sample:**

```
graph TD
    Animal["Animal"]
    Dog["Dog"]
    Printable["Printable"]
    Report["Report"]

    Dog --> Animal
    Report --> Printable

    style ModA fill:#ffcccc,stroke:#cc0000
    style ModB fill:#ffcccc,stroke:#cc0000
```

---

### DiagramPresenting

```swift
public protocol DiagramPresenting: Sendable
```

Implement this protocol to create a custom output target. The `present(script:)` method accepts any `DiagramOutputting` value — `DiagramScript`, `SequenceScript`, and `DepsScript` all conform.

```swift
func present(script: any DiagramOutputting) async
```

Both `BrowserPresenter` and `ConsolePresenter` implement this protocol. `ClassDiagramGenerator` and `SequenceDiagramGenerator` both call `await presenter.present(script:)` after generating the script.

---

### BrowserPresenter

```swift
public struct BrowserPresenter: DiagramPresenting
```

Opens the diagram in the default macOS browser via `NSWorkspace`. Format-aware: routes PlantUML to planttext.com and Mermaid to mermaid.live. Works for both class and sequence diagrams.

```swift
// Available render formats (PlantUML only; Mermaid always opens mermaid.live)
public enum BrowserPresentationFormat {
    case `default`    // Interactive planttext.com editor
    case png          // Direct PNG render at planttext.com
    case svg          // Direct SVG render at planttext.com
}

init(format: BrowserPresentationFormat = .default)
```

**URL patterns:**

| `script.format` | `BrowserPresentationFormat` | URL |
|---|---|---|
| `.plantuml` | `.default` | `https://www.planttext.com/?text=<encoded>` |
| `.plantuml` | `.png` | `https://www.planttext.com/api/plantuml/png/<encoded>` |
| `.plantuml` | `.svg` | `https://www.planttext.com/api/plantuml/svg/<encoded>` |
| `.mermaid` | any | `https://mermaid.live/view#base64:<base64json>` |

---

### ConsolePresenter

```swift
public struct ConsolePresenter: DiagramPresenting
```

Prints the raw diagram text to stdout with `print(script.text)`. Works for both PlantUML and Mermaid output, and for both class and sequence diagrams.

```swift
init()
```

---

### CallGraph

```swift
public struct CallGraph: Sendable
```

An in-memory graph of `CallEdge` values extracted from Swift source. Used internally by `SequenceDiagramGenerator`. Available for direct use when embedding the framework.

```swift
init(edges: [CallEdge])
var edges: [CallEdge]

// Depth-limited BFS from the given entry point.
// Returns all traversed edges in order; stops at maxDepth.
func traverse(from entryType: String, entryMethod: String, maxDepth: Int) -> [CallEdge]
```

**Traversal rules:**
- Each `Type.method` pair is visited at most once (cycle protection).
- Unresolved edges (`isUnresolved == true`) are included in the result but are not expanded further.
- Traversal stops when `maxDepth` is reached.

---

### CallEdge

```swift
public struct CallEdge: Sendable, Hashable
```

A single directed call relationship extracted from a function body by `CallGraphExtractor`.

```swift
public let callerType: String     // Type that contains the calling method
public let callerMethod: String   // Name of the calling method
public let calleeType: String?    // Type of the callee; nil when unresolved
public let calleeMethod: String   // Name of the called method
public let isAsync: Bool          // true when the call is wrapped in `await`
public let isUnresolved: Bool     // true when the callee type cannot be statically determined
```

---

### DependencyGraphModel

```swift
public struct DependencyGraphModel: Sendable
```

An in-memory model of dependency edges, with built-in cycle detection. Produced internally by `DependencyGraphGenerator` and available for direct use when embedding the framework.

```swift
public let edges: [DependencyEdge]
public init(edges: [DependencyEdge])

// DFS cycle detection — returns all node names involved in at least one cycle.
// Self-cycles (A → A) are detected. Nodes that merely feed into a cycle
// but are not themselves part of one are not included.
public func detectCycles() -> Set<String>
```

Cycle detection uses a gray/black DFS coloring scheme. A node is included in the result set when a back edge is found from it or through it.

---

### DependencyEdge

```swift
public struct DependencyEdge: Sendable, Hashable
```

A single directed dependency relationship between two named nodes.

```swift
public let from: String              // Dependent node name (the type or module that depends)
public let to: String                // Depended-upon node name (the parent, conformance target, or imported module)
public let kind: DependencyEdgeKind  // The nature of the dependency
```

---

### DependencyEdgeKind

```swift
public enum DependencyEdgeKind: String, Sendable, CaseIterable
```

The kind of dependency represented by a `DependencyEdge`.

| Case | Raw value | Produced by |
|---|---|---|
| `.inherits` | `"inherits"` | Class inheritance (`class Dog: Animal`) |
| `.conforms` | `"conforms"` | Protocol conformance on struct, enum, actor, or protocol |
| `.imports` | `"imports"` | An `import` statement in a source file (modules mode) |

In PlantUML output, the raw value appears as the label on each edge arrow. In Mermaid output, no label is emitted.

---

### ImportEdge

```swift
public struct ImportEdge: Sendable, Hashable
```

A single module import relationship extracted from a Swift source file. Used internally by `DependencyGraphGenerator` in modules mode.

```swift
public let sourceModule: String    // Parent directory name of the source file (derived module name)
public let importedModule: String  // Module name from the import statement
```

---

### BridgeLogger

```swift
public final class BridgeLogger
```

Singleton logger backed by `os.Logger`. All messages are logged with `.public` privacy so they appear in Console.app without a configuration profile.

```swift
static let shared: BridgeLogger

func info(_ message: String)
func error(_ message: String)
func warning(_ message: String)
func debug(_ message: String)
```

Subsystem: `name.JosephCursio.SwiftUMLBridge`

---

## Version

```swift
public struct Version {
    public let value: String
    public static let current: Version   // Version(value: "0.1.0")
}
```

The CLI version string. Displayed by `swiftumlbridge --version`.

---

## Studio App Reference

The SwiftUML Studio macOS app is a GUI front-end for SwiftUMLBridgeFramework. For usage instructions, see the [Studio User Guide](studio-user-guide.md).

### App Modes

```swift
enum AppMode: String, CaseIterable
```

| Case | Description |
|---|---|
| `.explorer` | Simplified, insight-driven interface (default for new users) |
| `.developer` | Full-featured interface with file browsing, markup editing, and fine-grained diagram controls |

Persisted in `@AppStorage`.

---

### Diagram Modes

```swift
enum DiagramMode: String, CaseIterable
```

| Case | Raw Value | Pro Required |
|---|---|---|
| `.classDiagram` | `"Class Diagram"` | No |
| `.sequenceDiagram` | `"Sequence Diagram"` | Yes |
| `.dependencyGraph` | `"Dependency Graph"` | Yes |

---

### Project Analysis

#### ProjectSummary

Produced by `ProjectAnalyzer.analyze(paths:)`. Drives the dashboard, insights, and suggestions.

| Property | Type | Description |
|---|---|---|
| `totalFiles` | `Int` | Number of `.swift` files found |
| `totalTypes` | `Int` | Total type declarations |
| `typeBreakdown` | `[String: Int]` | Count per type kind (structs, classes, enums, protocols, actors) |
| `totalRelationships` | `Int` | Total inheritance and conformance edges |
| `moduleImports` | `[String: Set<String>]` | Import statements grouped by source module |
| `topConnectedTypes` | `[(String, Int)]` | Types ranked by number of connections |
| `cycleWarnings` | `[String]` | Detected dependency cycles |
| `entryPoints` | `[(String, String)]` | Detected `(TypeName, methodName)` pairs for sequence diagrams |

#### InsightEngine

```swift
enum InsightEngine
```

Generates `[Insight]` from a `ProjectSummary`. Each `Insight` has:

| Property | Type | Description |
|---|---|---|
| `icon` | `String` | SF Symbol name |
| `title` | `String` | Short heading |
| `description` | `String` | Plain-language explanation |
| `severity` | `Severity` | `.info`, `.noteworthy`, or `.warning` |

#### SuggestionEngine

```swift
enum SuggestionEngine
```

Generates `[DiagramSuggestion]` from a `ProjectSummary`. Each suggestion has:

| Property | Type | Description |
|---|---|---|
| `icon` | `String` | SF Symbol name |
| `title` | `String` | User-facing label |
| `description` | `String` | What the diagram will show |
| `action` | `SuggestionAction` | `.classDiagram`, `.sequenceDiagram`, or `.dependencyGraph` |
| `requiresPro` | `Bool` | Whether this suggestion requires a Pro subscription |

---

### Subscription and Feature Gating

#### SubscriptionManager

```swift
@Observable @MainActor final class SubscriptionManager
```

Manages StoreKit 2 transactions and entitlement state.

| Property / Method | Type | Description |
|---|---|---|
| `isProUnlocked` | `Bool` | `true` when user has an active Pro subscription |
| `products` | `[Product]` | Available StoreKit products |
| `purchase(_:)` | `async throws` | Initiates a StoreKit purchase |
| `restorePurchases()` | `async` | Restores previously purchased subscriptions |
| `checkEntitlement()` | `async` | Verifies current entitlement status |

**Product IDs:** `pro_monthly`, `pro_annual`

#### ProFeature

```swift
enum ProFeature
```

Features gated behind a Pro subscription:

| Case | Description |
|---|---|
| `.sequenceDiagrams` | Sequence diagram generation |
| `.dependencyGraphs` | Dependency graph generation |
| `.exportMarkup` | Copying/saving raw PlantUML or Mermaid markup |
| `.formatSelection` | Choosing between PlantUML and Mermaid format |
| `.unlimitedProjects` | Opening more than one project |
| `.architectureTracking` | Saving and comparing architecture snapshots |

---

### Core Data Entities

#### DiagramEntity

Stores saved diagram history.

| Attribute | Type | Description |
|---|---|---|
| `id` | `UUID` | Unique identifier |
| `name` | `String` | Auto-generated from selected file/folder names |
| `mode` | `String` | `DiagramMode` raw value |
| `format` | `String` | `DiagramFormat` raw value |
| `entryPoint` | `String` | Entry method (sequence) or deps mode |
| `sequenceDepth` | `Int16` | Traversal depth for sequence diagrams |
| `paths` | `Binary` | JSON-encoded `[String]` of selected paths |
| `scriptText` | `String` | Generated PlantUML or Mermaid markup |
| `timestamp` | `Date` | When the diagram was saved |

#### ProjectSnapshot

Stores architecture state at a point in time (Pro only).

| Attribute | Type | Description |
|---|---|---|
| `id` | `UUID` | Unique identifier |
| `timestamp` | `Date` | When the snapshot was taken |
| `typeCount` | `Int32` | Total number of types |
| `relationshipCount` | `Int32` | Total number of relationships |
| `moduleCount` | `Int16` | Number of modules |
| `fileCount` | `Int32` | Number of `.swift` files |
| `typeBreakdown` | `Binary` | JSON-encoded `[String: Int]` |
| `topConnectedTypes` | `Binary` | JSON-encoded `[[String: Int]]` |
| `projectPaths` | `Binary` | JSON-encoded `[String]` |

---

### Architecture Diff

```swift
struct ArchitectureDiff
```

Computed by `SnapshotManager.computeDiff()` when comparing the current project state against a previous `ProjectSnapshot`.

| Property | Type | Description |
|---|---|---|
| `previousTimestamp` | `Date` | When the baseline snapshot was taken |
| `typeDelta` | `Int` | Change in type count |
| `relationshipDelta` | `Int` | Change in relationship count |
| `moduleDelta` | `Int` | Change in module count |
| `fileDelta` | `Int` | Change in file count |
| `typeBreakdownDeltas` | `[String: Int]` | Per-kind deltas (e.g., "+3 structs, -1 class") |
| `complexityChanges` | `[(String, Int)]` | Per-type connectivity changes |
