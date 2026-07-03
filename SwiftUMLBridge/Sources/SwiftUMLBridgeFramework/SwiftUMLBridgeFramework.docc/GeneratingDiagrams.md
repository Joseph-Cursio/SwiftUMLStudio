# Generating Diagrams

Produce a diagram from Swift source in a few lines.

## Overview

Every diagram type is produced by a generator. Generators are cheap value types
with an empty initializer, and each exposes a synchronous `generateScript(...)`
entry point that returns an emitted script, plus an `async` `generate(...)`
convenience that hands the script to a ``DiagramPresenting`` presenter.

### A class diagram

Point ``ClassDiagramGenerator`` at one or more paths (files or directories) and
read the emitted text:

```swift
import SwiftUMLBridgeFramework

let generator = ClassDiagramGenerator()
let script = generator.generateScript(for: ["Sources/"], with: .default)
print(script.text)
```

To render straight to the browser instead of capturing the text, use the `async`
convenience, which defaults to a ``BrowserPresenter``:

```swift
await generator.generate(for: ["Sources/"])
```

Swap the presenter to print to the console instead:

```swift
await generator.generate(for: ["Sources/"], presentedBy: ConsolePresenter())
```

### Choosing an output format

The emitted syntax is controlled by ``Configuration/format`` — a
``DiagramFormat`` (`.plantuml`, `.mermaid`, or `.nomnoml`). Build a
``Configuration`` with the format you want and pass it in:

```swift
let mermaid = Configuration(format: .mermaid)
let script = generator.generateScript(for: ["Sources/"], with: mermaid)
```

### Filtering what appears

``Configuration/elements`` (an ``ElementOptions``) controls which declarations
and members are drawn — by access level, whether to show nested types or
generics, how extensions are visualized, and an `exclude` list of name patterns.
``Configuration/relationships`` (a ``RelationshipOptions``) controls which
inheritance, conformance, and dependency edges are drawn and how they are
labelled.

```swift
let publicOnly = Configuration(
    elements: ElementOptions(
        havingAccessLevel: [.open, .public],
        showMembersWithAccessLevel: [.open, .public]
    )
)
let script = generator.generateScript(for: ["Sources/"], with: publicOnly)
```

### Other diagram types

The remaining generators follow the same shape, differing only in the inputs
each diagram needs:

- ``SequenceDiagramGenerator`` — traces a static call graph from an entry point
  (`Type.method`) to a given depth. Use ``SequenceDiagramGenerating/findEntryPoints(for:)``
  to discover candidate entry points.
- ``ActivityDiagramGenerator`` — control flow (loops, `switch`, `do`/`catch`,
  `await`) for a single method.
- ``StateMachineGenerator`` — enum-driven state machines and their `switch`-based
  transitions.
- ``ERDiagramGenerator`` — SwiftData, Core Data, GRDB, and SQLite.swift schemas
  with relationship cardinality.
- ``DependencyGraphGenerator`` — module- or type-level dependency graphs. See its
  ``DependencyGraphGenerating`` package-aware overload for SPM module info.
- ``ComponentDiagramGenerator`` — SPM targets and their `target_dependencies`.

### Module-aware generation

When you have parsed a package manifest into an ``SPMPackageDescription`` (via
``SPMPackageReader``), the class-diagram and dependency-graph generators offer
package-aware overloads that stamp each type or edge with its owning SPM target,
so cross-module architecture is visible in the rendered diagram:

```swift
let script = generator.generateScript(
    forPackage: packageDescription,
    packageRoot: packageRoot,
    with: .default
)
```
