# ER Diagram Expansion — Implementation Plan

**Last updated:** 2026-05-09
**Status:** proposed

## Context

`docs/internal/missing-uml-diagrams.md` (§12) recommends Entity-Relationship diagrams as the highest-value structural gap, and lists three Swift persistence stacks worth covering:

1. **SwiftData** `@Model` classes — **already shipped** (M7, 2026-04). `ERModelExtractor` walks SwiftSyntax `ClassDeclSyntax` nodes annotated with `@Model`, captures stored properties as `ERAttribute`s, and resolves `@Relationship(inverse: \...)` into typed `ERRelationship`s with cardinality. PlantUML and Mermaid (`erDiagram`) emitters ship; `swiftumlbridge er` CLI subcommand is wired; Studio has a Pro-gated `DiagramMode.erDiagram`.
2. **Core Data** `.xcdatamodeld` bundles — **not yet covered.**
3. **GRDB / SQLite.swift** schemas — **not yet covered.**

This plan addresses the two remaining stacks. The missing-uml-diagrams.md doc is itself stale on this point; it should be amended to mark SwiftData ER as shipped (see §8 below).

## Goals

- Detect Core Data `.xcdatamodeld` bundles in input paths and emit ER diagrams from their `contents` XML.
- Detect GRDB and SQLite.swift schema declarations in Swift source and emit ER diagrams from them.
- Reuse the existing `ERModel` / `EREntity` / `ERAttribute` / `ERRelationship` / `ERCardinality` value types and the existing PlantUML / Mermaid emitters — no model-layer rewrites.
- Surface multi-stack support in the CLI (`swiftumlbridge er` already exists; extend it to handle the new inputs) and in the Studio app (file-picker + the existing `DiagramMode.erDiagram` mode).

## Non-goals

- Custom XML schema validation beyond what's required to extract entities/relationships.
- ORMs other than the three named stacks (Realm, FluentKit, etc.) — leave as a follow-up if requested.
- Editing `.xcdatamodeld` from the Studio app — read-only.
- Live reload as the user edits Core Data schemas in Xcode — manual regenerate is fine.

---

## 1. Core Data — `.xcdatamodeld` parsing

### 1.1 Input shape

A `.xcdatamodeld` is a *directory bundle* (Foundation treats it as a file by extension). Inside:

```
MyApp.xcdatamodeld/
├── .xccurrentversion         # plist pointing at the active version
└── MyApp.xcdatamodel/        # one or more versioned models
    └── contents              # XML payload (entity/attribute/relationship)
```

The `contents` file is XML with a stable schema:

```xml
<model type="com.apple.IDECoreDataModeler.DataModel" ...>
  <entity name="Author" representedClassName="Author" syncable="YES">
    <attribute name="name" attributeType="String"/>
    <attribute name="birthYear" optional="YES" attributeType="Integer 32" usesScalarValueType="YES"/>
    <relationship name="books" toMany="YES" deletionRule="Cascade"
                  destinationEntity="Book" inverseName="author" inverseEntity="Book"/>
  </entity>
  <entity name="Book" representedClassName="Book">
    <attribute name="title" attributeType="String"/>
    <relationship name="author" maxCount="1" deletionRule="Nullify"
                  destinationEntity="Author" inverseName="books" inverseEntity="Author"/>
  </entity>
</model>
```

### 1.2 Parser

New file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/CoreDataModelExtractor.swift`.

Use `XMLDocument` (Foundation, macOS-only — fine since the framework already targets `.macOS(.v26)`). DOM-style parsing keeps the code linear:

```swift
public enum CoreDataModelExtractor {
    /// Extract an `ERModel` from a `.xcdatamodeld` bundle. Picks the active
    /// version via `.xccurrentversion`; falls back to the first
    /// `.xcdatamodel` directory inside if that file is missing.
    public static func extract(from bundleURL: URL) throws -> ERModel
}
```

Mapping:

| XML | `ERAttribute` / `ERRelationship` field |
|---|---|
| `<entity name="X">` | `EREntity(name: "X", attributes: …)` |
| `<attribute name="n" attributeType="String">` | `ERAttribute(name: "n", type: "String", …)` |
| `optional="YES"` | `isOptional = true` |
| `<relationship name="r" toMany="YES" destinationEntity="D">` | `ERRelationship(from: parent, toEntity: "D", fromCardinality: .exactlyOne, toCardinality: .zeroOrMany, label: "r", inverseLabel: <inverseName>)` |
| `<relationship maxCount="1">` | `toCardinality = .zeroOrOne` |
| Type names: `Integer 32`, `Integer 64`, `Date`, `String`, `Binary`, `UUID`, etc. | Pass through verbatim — emitters already render strings |

Edge cases to handle:
- **Versioned models**: walk `.xccurrentversion` plist (PropertyListSerialization) to find the current `.xcdatamodel` subdirectory.
- **Abstract entities**: emit normally; consumers can still see them.
- **`parentEntity="…"`**: model as a relationship `child → parent` with cardinality `.exactlyOne` and label `"is a"`, *or* (preferred) merge inherited attributes into the child. v1: emit a separate parent-edge note; merging defers to v1.1.
- **Fetched properties**: skip — they're query-derived, not schema.
- **No `contents` file present**: throw `ERExtractionError.malformedBundle`.

### 1.3 File detection

Extend `FileCollector` (or add a sibling `BundleCollector`) to recognise `.xcdatamodeld` directories and **not** descend into them as if they were Swift source folders. The simplest path: in `ERCommand` and `ERDiagramGenerator`, glob for `*.xcdatamodeld` in the input paths *before* the regular Swift-source pass.

### 1.4 CLI

Extend `swiftumlbridge er`:

- If any input path is a `.xcdatamodeld` (file or descendant), use `CoreDataModelExtractor`.
- Otherwise, fall back to the existing SwiftData path.
- Add `--core-data <path>` for explicit selection when path inference is ambiguous (e.g., the user passes a project directory containing both Swift `@Model` files and a `.xcdatamodeld`).

### 1.5 Tests

Fixtures (under `TestFixtures/SampleProject/CoreData/`):

- `Bookstore.xcdatamodeld/Bookstore.xcdatamodel/contents` — Author 1-to-many Book, Book has String/Date attributes.
- `Library.xcdatamodeld/V1.xcdatamodel/contents` + `V2.xcdatamodel/contents` + `.xccurrentversion` pointing at V2 — versioning test.
- `Inheritance.xcdatamodeld/.../contents` — Person → Employee parent-entity edge.
- `Empty.xcdatamodeld/.../contents` — zero entities, must produce an empty `ERModel` not an error.

Test files:

- `Tests/.../ParsingTests/CoreDataModelExtractorTests.swift` — basic shape, attributes, relationships, cardinality from `toMany`/`maxCount`, inverse handling, `optional="YES"`, versioning via `.xccurrentversion`, parent-entity edge.
- `Tests/.../ModelTests/ERFromCoreDataIntegrationTests.swift` — read-from-disk pipeline (mirror the `StateMachineFixtureTests` pattern).
- Add Mermaid + PlantUML emitter assertions reusing the existing `ERMermaidTests` / `ERPlantUMLTests` patterns against models built from these fixtures.

---

## 2. GRDB / SQLite.swift — Swift-source schema parsing

### 2.1 Detection patterns

Both are detectable via SwiftSyntax with no runtime introspection.

**GRDB:**

```swift
struct Player: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "player"
    var id: Int64?
    var name: String
    var teamId: Int64?

    static let team = belongsTo(Team.self)
    static let scores = hasMany(Score.self)
}
```

Signals:
- Conforms to `FetchableRecord`, `PersistableRecord`, `MutablePersistableRecord`, `EncodableRecord`, or `TableRecord`.
- Optional `static let databaseTableName: String` literal — overrides the default lowercased type name.
- `static let X = belongsTo(...)` / `hasMany(...)` / `hasOne(...)` / `hasManyThrough(...)` for relationships.

**SQLite.swift:**

```swift
struct Schema {
    static let users = Table("users")
    static let id = Expression<Int64>("id")
    static let name = Expression<String>("name")
}
```

Signals:
- A type whose properties are `Table(...)` and `Expression<T>(...)` constructors.
- Cardinality is largely free-form in SQLite.swift (no built-in associations) — v1 will detect tables + columns only and skip relationship inference.

### 2.2 Parser

New file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/PersistenceSchemaExtractor.swift`. One `SyntaxVisitor` that handles both stacks (they don't conflict) and emits the same `ERModel` shape.

```swift
public enum PersistenceSchemaExtractor {
    public static func extract(from source: String) -> ERModel
}
```

GRDB `belongsTo` → `(many) →* (one)` — i.e., `fromCardinality = .zeroOrMany`, `toCardinality = .exactlyOne`, label = property name.
GRDB `hasMany` → mirror.
GRDB `hasOne` → `1 ↔ 1`.

### 2.3 CLI surface

Extend `swiftumlbridge er`:

- Already accepts Swift source paths for SwiftData. When SwiftData (`@Model`) detection yields zero entities for a given file, fall back to `PersistenceSchemaExtractor` on the same file. (The two extractors are mutually exclusive on a per-file basis — a file is either `@Model`-style or GRDB-style, not both.)
- Add `--stack swiftdata|coredata|grdb|auto` flag (default `auto`). Lets users force one path when detection is ambiguous.

### 2.4 Tests

Fixtures (under `TestFixtures/SampleProject/Persistence/`):

- `GRDBPlayer.swift` — `Player` + `Team` + `Score` with `belongsTo` / `hasMany`.
- `GRDBPlayerNoAssociations.swift` — `Player` only, no relationships (positive case for table-only emit).
- `SQLiteSchema.swift` — a `Schema` enum with `Table("users")` + `Expression<Int64>("id")` columns.
- `NotPersistence.swift` — plain Swift struct that must produce zero entities (negative case).

Test files: `PersistenceSchemaExtractorTests.swift` + an `ERFromPersistenceIntegrationTests.swift` paralleling the Core Data integration suite.

---

## 3. Studio integration

The Studio app already has `DiagramMode.erDiagram` and the Pro gate. Two small additions:

- **File-picker recognises `.xcdatamodeld`**: extend `ContentView.openPanel` (or the Open Package flow) to add `.xcdatamodeld` (UTType for Core Data model bundle, `com.apple.xcode.coredata-momd`) to `allowedContentTypes`. When the picked URL is a `.xcdatamodeld`, the view model dispatches to the Core Data path.
- **DiagramViewModel.generateERDiagram** — when `selectedPaths.first` ends in `.xcdatamodeld`, call `CoreDataModelExtractor.extract(from: url)` and feed the resulting `ERModel` into `ERScript`. Otherwise the existing SwiftData-aware path runs.

No new view files. The existing `NativeDiagramView` rendering covers the existing ER output (entities as boxes, relationships as labeled edges).

## 4. Risks

- **Versioned `.xcdatamodeld`**: picking the wrong version. Mitigated by parsing `.xccurrentversion` first; surface an error if it's missing AND there are multiple `.xcdatamodel` siblings.
- **Cross-XML-version drift**: Apple has changed `contents` schema between Xcode releases (`syncable`, `usesScalarValueType`, `elementID`). Treat unknown attributes as ignorable; write tests against fixtures from at least Xcode 14 and Xcode 26.
- **GRDB protocol composition**: `class Player: Foo, FetchableRecord & PersistableRecord` could miss the `&`-form. Strip `&` before checking conformance names.
- **SQLite.swift's free-form schema**: no relationship metadata to derive. Document the limitation and emit table-only diagrams.
- **Performance**: XML parsing is fast; no perf concerns expected. The Process invocation cost only applies to package mode (M12), not here.
- **GRDB v6 vs v7 association API drift**: detect by symbol name only, not type checking, so version drift is tolerable.

## 5. Milestones

| Milestone | Scope                                                                  | Estimate |
|-----------|------------------------------------------------------------------------|----------|
| **C1**    | Core Data: `CoreDataModelExtractor` + fixtures + emitter wiring + `swiftumlbridge er` accepts `.xcdatamodeld` | 1–2 days |
| **C2**    | Studio: file-picker accepts `.xcdatamodeld`, view model dispatches, integration test against bundled fixture | 0.5 day |
| **G1**    | GRDB: `PersistenceSchemaExtractor` (GRDB half) + fixtures + emitter coverage + `--stack` flag scaffolding   | 1 day    |
| **G2**    | SQLite.swift: extend the same extractor (table + columns only)         | 0.5 day  |
| **D**     | Update `missing-uml-diagrams.md` to mark §12 SwiftData as shipped and reference this plan; update CHANGELOG; update README's diagram matrix | 0.5 day |

C1 + C2 together fill the highest-value gap (Core Data is what most Swift projects already use). G1 + G2 are independent and can ship later if priorities shift.

## 6. Critical files

- `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/ERModelExtractor.swift` — pattern to mirror for the Core Data and persistence-schema extractors
- `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/ERModel.swift` — value types being reused; **no changes required**
- `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/ERScript.swift` — emitter; **no changes required** (it consumes `ERModel`)
- `SwiftUMLBridge/Sources/swiftumlbridge/Commands/ERCommand.swift` — CLI; add `.xcdatamodeld` detection + `--stack` flag
- `SwiftUMLStudio/DiagramViewModel+Generation.swift` — add the per-stack dispatch in `generateERDiagram`
- `TestFixtures/SampleProject/CoreData/` and `TestFixtures/SampleProject/Persistence/` — new fixture trees mirroring `StateMachines/`

## 7. Definition of done

- `swiftumlbridge er Bookstore.xcdatamodeld --format mermaid` produces a valid `erDiagram` with the expected entities and one labeled `||--o{` relationship.
- `swiftumlbridge er Sources/Player.swift --format plantuml` produces an entity diagram for the GRDB `Player` model with `belongsTo` / `hasMany` relationships rendered correctly.
- The Studio app's Open dialog accepts a `.xcdatamodeld`, switches to ER mode, and renders the diagram natively.
- Bridge test suite total ≥ baseline + the new test counts; no regressions.
- `docs/internal/missing-uml-diagrams.md` §12 is updated to mark all three sub-stacks as shipped, with a pointer to this plan.

## 8. Stale-doc cleanup

`missing-uml-diagrams.md` is dated 2026-04-20 and still describes ER as a future feature. After this plan ships, that doc needs three edits:

1. §12: replace the "Implementation cost: medium" bullet with a "Shipped (M7, 2026-04-XX): SwiftData. Core Data + GRDB / SQLite.swift via this plan" status block.
2. "Prioritized recommendation" §3: mark ER as shipped.
3. "Other PlantUML diagrams" closing list: add ER to the COVERED set.

This cleanup belongs in milestone D above so it lands as part of the same release cycle.
