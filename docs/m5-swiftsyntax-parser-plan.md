# M5 — SwiftSyntax-Primary Parser

## Goal

Replace the SourceKit-primary parsing pipeline with a SwiftSyntax-primary one. SourceKit is retained as an optional supplement for resolving inferred variable types. This milestone creates the foundation that directly enables fixes for the three known parsing limitations (actors, async/throws, macros) in the follow-on milestone.

---

## Current Architecture

```
File → SourceKit (via SourceKitten)
     → JSON string (Structure.description)
     → JSONDecoder → SyntaxStructure
```

All structural data — type kinds, accessibility, inherited types, member names — comes from SourceKit's JSON output. SwiftSyntax is currently used only in `CallGraphExtractor` (sequence diagrams), isolated from the class diagram pipeline entirely.

### The problem

SourceKit's JSON for this file:

```swift
actor ImageCache {
    func store(_ data: Data, for key: String) async {}
}
```

Produces `kind = "source.lang.swift.decl.class"` for the actor (SourceKit 6.3 regression), and `typename = nil` for method effect specifiers. The `.actor` case in `ElementKind` is never matched at runtime; async/throws labels are never emitted.

---

## New Architecture

```
File ──► SwiftSyntax (SyntaxStructureBuilder)
              │
              ▼
         SyntaxStructure (correct kinds, async/throws, attributes)
              │
              ▼ (optional — when sdkPath or file URL available)
         SourceKit typename supplement
         (fills in inferred variable types by offset matching)
              │
              ▼
         SyntaxStructure with complete typename data
```

SwiftSyntax owns structure and correctness. SourceKit contributes one thing: the resolved type name for variables with no explicit type annotation. If the SourceKit pass fails or is unavailable, the diagram degrades gracefully (inferred-type properties show no type), identical to the current behavior when no SDK path is provided.

---

## Why SwiftSyntax covers almost everything

| Data point | SwiftSyntax | SourceKit |
|---|---|---|
| Type kind (class/struct/enum/actor/protocol/extension) | ✓ distinct node types | ✗ actors → `.class` |
| Accessibility modifiers | ✓ `DeclModifierListSyntax` | ✓ |
| Inherited types | ✓ `InheritanceClauseSyntax` | ✓ |
| Generic parameters | ✓ `GenericParameterClauseSyntax` | ✓ |
| Method async/throws | ✓ `FunctionEffectSpecifiersSyntax` | ✗ not in typename |
| Attribute macros (@Observable) | ✓ `AttributeListSyntax` | ✗ not exposed |
| Variable typename (explicit) | ✓ `TypeAnnotationSyntax` | ✓ |
| Variable typename (inferred) | ✗ expression only | ✓ `key.typename` |

The only gap is inferred variable types — a narrow case that SourceKit fills precisely.

---

## Implementation Plan

### Step 1 — `SyntaxStructureBuilder.swift` (new file)

A `SyntaxVisitor` subclass in `Parsing/`. Walks a parsed `SourceFileSyntax` and builds `SyntaxStructure` instances directly via `init(...)`, never via JSON decoding.

**Type stack pattern** (same as `CallGraphExtractor`):

```swift
final class SyntaxStructureBuilder: SyntaxVisitor {
    private(set) var topLevelItems: [SyntaxStructure] = []
    private var typeStack: [(structure: SyntaxStructure, children: [SyntaxStructure])] = []
}
```

Each visit/visitPost pair pushes/pops the stack. On pop, children are assigned to `substructure` and the completed node is either appended to its parent's children or to `topLevelItems`.

**Node → ElementKind mapping:**

| SwiftSyntax node | ElementKind |
|---|---|
| `ClassDeclSyntax` | `.class` |
| `StructDeclSyntax` | `.struct` |
| `EnumDeclSyntax` | `.enum` |
| `ActorDeclSyntax` | `.actor` ← fixes limitation 1 |
| `ProtocolDeclSyntax` | `.protocol` |
| `ExtensionDeclSyntax` | `.extension` (always; extension variants never used by emitters) |
| `VariableDeclSyntax` (no static/class modifier) | `.varInstance` |
| `VariableDeclSyntax` (static or class modifier) | `.varStatic` |
| `FunctionDeclSyntax` (no static/class modifier) | `.functionMethodInstance` |
| `FunctionDeclSyntax` (static or class modifier) | `.functionMethodStatic` |
| `InitializerDeclSyntax` | `.functionConstructor` |
| `DeinitializerDeclSyntax` | `.functionDestructor` |
| `EnumCaseDeclSyntax` | `.enumcase` with `.enumelement` child per element |
| `TypeAliasDeclSyntax` | `.typealias` |
| `MacroDeclSyntax` | `.macro` |
| `GenericParameterSyntax` | `.genericTypeParam` |

**Accessibility extraction** (from `DeclModifierListSyntax`):

Look for the first modifier whose `name.tokenKind` is one of `.keyword(.open)`, `.keyword(.public)`, `.keyword(.package)`, `.keyword(.internal)`, `.keyword(.private)`, `.keyword(.fileprivate)`. Default to `.internal` when absent.

**Inherited types** (from `InheritanceClauseSyntax`):

Map each `InheritedTypeSyntax.type.trimmedDescription` to a `SyntaxStructure(name:)`.

Handle compound types (`A & B`) by splitting on `&` and creating one `SyntaxStructure` per component — consistent with the existing `addLinking` logic in `SyntaxStructure+PlantUML.swift`.

**Method effect specifiers** (from `FunctionEffectSpecifiersSyntax`): ← fixes limitation 2

Store on the `SyntaxStructure` as the `typename` field for consistency with the existing `memberName(of:)` logic:
- If async: `typename = "async"`
- If async + throws: `typename = "async throws"`
- If throws only: `typename = "throws"`
- Otherwise: `typename = nil`

This reuses `memberName(of:)`'s existing `typeName.contains("async")` checks without any emitter changes. The method names `async` and `throws` will never collide with real return types in that check.

**Attribute capture** (from `AttributeListSyntax`): ← foundation for limitation 3

For each `AttributeSyntax` in the list, create a `SyntaxStructure(attribute: name)` and collect them as the `attributes` array on the parent node. The attribute name is `attribute.attributeName.trimmedDescription` (e.g., `"Observable"` for `@Observable`).

This captures the data; the emitter changes to render macro stereotypes are deferred to the follow-on limitations milestone.

**Generic parameters** (from `GenericParameterClauseSyntax`):

For each `GenericParameterSyntax`, create a `SyntaxStructure(kind: .genericTypeParam, name: param.name.text, inheritedTypes: [...])` and add to `substructure`. The constraint (`T: Equatable`) maps to `inheritedTypes`.

---

### Step 2 — SourceKit typename supplement (in `SyntaxStructureProvider.swift`)

A private function that back-fills `typename` on variable nodes where SwiftSyntax produced nil (i.e., inferred types):

```swift
private static func supplementTypenames(
    in root: SyntaxStructure,
    source: String,
    sdkPath: String?
)
```

**Approach — offset-based matching:**

1. During the SwiftSyntax builder pass, for each `VariableDeclSyntax` binding with no `typeAnnotation`, record `(utf8Offset: Int, structure: SyntaxStructure)` in the builder.
2. In the supplement function, run the legacy SourceKit parse (`Structure(file:)` or `SwiftDocs`) on the same source to produce a JSON dictionary.
3. Walk the SourceKit JSON recursively, collecting entries where `key.kind` is `varInstance`/`varStatic` and `key.typename` is non-nil, keyed by `key.offset` (integer byte offset).
4. For each pending `(offset, structure)` pair from step 1, look up the offset in the SourceKit map and assign `typename` if found.

This is a targeted read of the SourceKit JSON — we don't decode it into `SyntaxStructure`, we only extract the offset→typename mapping.

**Graceful degradation:** If the SourceKit pass throws, returns nil, or the SDK path is unavailable, the function is a no-op. Variables with inferred types show no type annotation in diagrams, same as today's fallback.

---

### Step 3 — Rewrite `SyntaxStructureProvider.swift`

Replace both `create(from:sdkPath:)` entry points:

```swift
// From file on disk
static func create(from fileOnDisk: URL, sdkPath: String? = nil) -> SyntaxStructure? {
    guard let source = try? String(contentsOf: fileOnDisk, encoding: .utf8) else { return nil }
    return build(from: source, sdkPath: sdkPath, fileURL: fileOnDisk)
}

// From string contents
static func create(from contents: String) -> SyntaxStructure? {
    return build(from: contents, sdkPath: nil, fileURL: nil)
}

private static func build(
    from source: String,
    sdkPath: String?,
    fileURL: URL?
) -> SyntaxStructure? {
    let sourceFile = Parser.parse(source: source)
    let builder = SyntaxStructureBuilder(viewMode: .sourceAccurate)
    builder.walk(sourceFile)

    let root = SyntaxStructure(substructure: builder.topLevelItems)

    if sdkPath != nil || fileURL != nil {
        supplementTypenames(in: root, source: source, sdkPath: sdkPath)
    }

    return root
}
```

The legacy SourceKit decoding path (`createStructure(from:)`, `create(from:sdkPath:)`) can be removed. The `Codable` conformance and `CodingKeys` on `SyntaxStructure` remain intact — they're used nowhere in the main path after this change but removing them is a separate cleanup.

---

## Files to Create / Modify

| File | Action | Notes |
|---|---|---|
| `Parsing/SyntaxStructureBuilder.swift` | **Create** | SwiftSyntax `SyntaxVisitor` subclass |
| `Parsing/SyntaxStructureProvider.swift` | **Rewrite** | SwiftSyntax-primary + SourceKit supplement |
| `Tests/.../ParsingTests/SyntaxStructureBuilderTests.swift` | **Create** | Unit tests for the builder (see below) |
| `Tests/.../ParsingTests/ActorKindDiagnosticTests.swift` | **Update** | Replace workaround assertions with correct `.actor` kind assertions |

### No changes required

- `Parsing/SyntaxStructure.swift` — `ElementKind` raw values are identifiers, not parsing tokens; `Codable` conformance is retained
- `Parsing/SyntaxStructure+Extensions.swift`
- `Model/DiagramContext.swift` and all model layer
- `Emitters/SyntaxStructure+PlantUML.swift` and `SyntaxStructure+Mermaid.swift`
- `Model/ClassDiagramGenerator.swift`
- All 355 existing tests (these become the regression suite)

---

## Test Plan

### New: `SyntaxStructureBuilderTests.swift`

`@Suite("SyntaxStructureBuilder")` covering:

**Type declaration kinds:**
- `class Foo {}` → top-level item with `kind == .class`, `name == "Foo"`
- `struct Foo {}` → `kind == .struct`
- `enum Foo {}` → `kind == .enum`
- `actor Foo {}` → `kind == .actor` (key regression test replacing `ActorKindDiagnosticTests`)
- `protocol Foo {}` → `kind == .protocol`
- `extension Foo {}` → `kind == .extension`

**Accessibility:**
- `public class Foo {}` → `accessibility == .public`
- `private struct Bar {}` → `accessibility == .private`
- `class Foo {}` (no modifier) → `accessibility == .internal`

**Members:**
- `class Foo { var name: String = "" }` → substructure contains `varInstance`, `name == "name"`, `typename == "String"`
- `class Foo { static var count: Int = 0 }` → `kind == .varStatic`
- `class Foo { func greet() {} }` → `kind == .functionMethodInstance`
- `class Foo { static func create() {} }` → `kind == .functionMethodStatic`
- `class Foo { init() {} }` → `kind == .functionConstructor`
- `enum Color { case red }` → substructure contains `.enumcase` with `.enumelement` child

**Effect specifiers** (key regression tests):
- `class Foo { func fetch() async {} }` → method `typename` contains `"async"`
- `class Foo { func load() throws {} }` → method `typename` contains `"throws"`
- `class Foo { func save() async throws {} }` → method `typename` contains both
- `class Foo { func sync() {} }` → method `typename == nil` (no spurious labels)

**Attributes:**
- `@Observable class Foo {}` → `attributes` array contains a node with `attribute == "Observable"`

**Inherited types:**
- `class Dog: Animal {}` → `inheritedTypes` contains `SyntaxStructure(name: "Animal")`
- `class Foo: Bar & Baz {}` → `inheritedTypes` contains two entries (existing compound-type split behaviour)

**Generics:**
- `class Box<T> {}` → substructure contains `genericTypeParam` with `name == "T"`
- `class Box<T: Equatable> {}` → genericTypeParam has `inheritedTypes == [SyntaxStructure(name: "Equatable")]`

### Updated: `ActorKindDiagnosticTests.swift`

Remove the "actors appear as class" workaround assertions. Replace with:

- `actor ImageCache {}` → `kind == .actor`
- The actor stereotype (`<<actor>>`) appears in the PlantUML output

### Regression: existing 355 tests

Run `swift test` in `SwiftUMLBridge/` after the rewrite. All 355 tests must pass without modification. These tests drive behaviour at the `ClassDiagramGenerator`/emitter level, so they verify that the new parser produces identical output for all previously-supported constructs.

---

## Risks and Mitigations

| Risk | Details | Mitigation |
|---|---|---|
| Inferred-type variable regression | Variables like `var x = MyClass()` lose typename if SourceKit supplement path not triggered | Supplement runs whenever `sdkPath` or a file URL is available (all file-based paths). `generateScript(for contents:)` string-only path never had SDK resolution anyway. |
| `functionConstructor` not shown in diagrams | `init` methods — verify existing `PlantUMLGenerationTests` cover constructors | Add constructor test to `SyntaxStructureBuilderTests`; check existing test suite for constructor coverage |
| Extension kind variants lost | `extensionClass`/`extensionStruct` etc. are in `ElementKind` but the emitter `plantUMLText` only handles `.extension` — the variant cases fall to the `default` error branch | Use `.extension` for all extensions in builder; no regression since SourceKit already emits plain `.extension` for real files |
| `EnumCaseDeclSyntax` structure differs | Each `case a, b` is one `EnumCaseDeclSyntax` with multiple `EnumCaseElementSyntax` children | Mirror SourceKit's `.enumcase` wrapping `.enumelement` children; test multi-element cases explicitly |
| Attribute encoding in `SyntaxStructure` | `SyntaxStructure.attributes` holds nodes with `attribute` field (SourceKit uses `key.attribute`); verify field is populated correctly | Test `@Observable class` → attributes array has `attribute == "Observable"` |

---

## Verification

```bash
cd SwiftUMLBridge

# Full test suite — all 355 must pass
swift test

# Spot check actor output
echo 'actor ImageCache { var count: Int = 0 }' | swift run swiftumlbridge classdiagram /dev/stdin

# Spot check async/throws output
echo 'class Svc { func load() async throws -> Data { fatalError() } }' \
  | swift run swiftumlbridge classdiagram /dev/stdin
```

Expected actor output includes `<<actor>>` stereotype. Expected method output includes `async throws` qualifier on the method line.
