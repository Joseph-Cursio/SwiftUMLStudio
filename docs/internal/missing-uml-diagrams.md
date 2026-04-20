# Missing UML Diagram Types — Gap Analysis

**Last updated:** 2026-04-20
**Scope:** Popular UML 2.x (and common non-UML) diagram types that are **not** currently producible by SwiftUMLStudio / SwiftUMLBridge.

## Current coverage (baseline)

SwiftUMLBridge ships **five** diagram types today:

| Diagram | Status | Command |
|---|---|---|
| Class diagram | Shipped | `swiftumlbridge classdiagram` |
| Sequence diagram | Shipped | `swiftumlbridge sequence` |
| Dependency graph | Shipped | `swiftumlbridge deps` |
| Activity diagram | Shipped (concurrency-aware) | `swiftumlbridge activity` |
| State machine diagram | Shipped | `swiftumlbridge state` |

Output formats: PlantUML, Mermaid.js, Nomnoml (class only), SVG.

UML 2.x defines **14** official diagram types (7 structural + 7 behavioral). The sections below focus on the ones that (a) are widely used in industry and (b) can be meaningfully auto-generated from Swift source.

---

## Structural diagrams — gaps

### 1. Component diagram — **high value, recommended**

Shows high-level software components, their interfaces (provided/required), and wiring between modules. In Swift terms this maps naturally onto **Swift packages, SPM products, and target boundaries**.

- **Why it's popular:** standard architecture artifact in almost every enterprise/review deck; the "one diagram" most engineering managers expect to see.
- **Swift relevance:** very high. `Package.swift` already declares products, targets, and dependencies — the raw graph exists.
- **Differs from current `deps`:** `deps --modules` draws a dependency arrow graph; a component diagram adds *ball-and-socket* interface semantics (what each component exposes and requires), not just "A imports B".
- **Implementation cost:** low–medium. Parse `Package.swift` manifests; extend the Dependency layer with an interface-detection pass (public API surface per target).

### 2. Package diagram — **medium value**

UML package diagrams show nested namespace/package hierarchy and dependencies between packages.

- **Why it's popular:** common in Java/Kotlin docs; less common in Swift because Swift's module system is flatter.
- **Swift relevance:** medium. Maps to Swift modules + nested types, or to folder groupings.
- **Overlap:** largely covered by `deps --modules` today. A dedicated package emitter would add containment visuals and folder grouping.
- **Implementation cost:** low (reuse dependency graph + add nesting).

### 3. Object diagram — **low–medium value**

A snapshot of instances and their links at a point in time (vs. class diagram which shows types).

- **Why it's popular:** useful in teaching and for documenting specific scenarios (e.g., "here's the object graph after login").
- **Swift relevance:** low for static source analysis — object graphs are a runtime concern. Would require either runtime instrumentation or hand-authored scenarios.
- **Implementation cost:** high (needs runtime hook or DSL for specifying snapshots). **Not recommended as near-term work.**

### 4. Deployment diagram — **low value for this tool**

Shows hardware nodes, devices, and the artifacts deployed on them.

- **Swift relevance:** effectively zero — deployment topology isn't in source. Better served by dedicated infra-as-code tools. **Skip.**

### 5. Composite structure diagram — **low value**

Internal structure of a classifier (parts, ports, connectors). Rarely used outside of embedded/systems engineering. **Skip.**

### 6. Profile diagram — **skip**

Used to extend UML itself with stereotypes. Not a developer-facing artifact. **Skip.**

---

## Behavioral diagrams — gaps

### 7. Activity diagram — **SHIPPED (2026-04-20)**

Flowchart-style diagram showing control flow: actions, decisions, forks/joins, and swimlanes. In Swift this maps onto **function control-flow graphs** (if/guard/switch/for/while/async-let/task-group).

- **Command:** `swiftumlbridge activity --entry Type.method [--format plantuml|mermaid]`
- **Studio mode:** Activity Diagram (toolbar picker)
- **Parser:** `ActivityFlowExtractor` + `ActivityGraphBuilder` — walks a chosen entry function's body and emits control-flow nodes.
- **Coverage:** if/guard → decision + `true`/`false` branches; switch → multi-branch decision (one edge per case, including `default`); for/while/repeat → loopStart with back-edges; return/throw → terminal edges to the `end` node; do/catch → decision with `success` + `catch <pattern>` branches; **async let → fork/join (one branch per binding)**; **withTaskGroup / withThrowingTaskGroup / withDiscardingTaskGroup / withThrowingDiscardingTaskGroup + group.addTask → fork/join with one branch per task closure**; bare `await` → action flagged `isAsync`.
- **Emitters:** PlantUML (state-diagram flavor with `<<choice>>`/`<<fork>>`/`<<join>>` stereotypes), Mermaid (`flowchart TD`), native SVG (longest-path layering, rounded-rect actions, diamonds, horizontal fork/join bars, dashed back-edges for loops).
- **Test coverage:** 57 Swift Testing cases across parser, PlantUML emitter, Mermaid emitter, SVG layout/renderer, and generator.

### State machine diagram — **SHIPPED (2026-04-20)**

Transition diagram showing discrete states and the triggers that move between them. In Swift this maps onto an enum-typed property on a host type (class/struct/actor) where transitions are expressed as `self.prop = .case` assignments inside `switch` branches.

- **Command:** `swiftumlbridge state [<paths>] [--list] [--state HostType.EnumType] [--format plantuml|mermaid]`
  - `--list` (or omitting `--state`) prints candidate state machines with detection confidence and transition counts; detector notes are shown beneath each candidate.
  - `--state HostType.EnumType` renders the chosen machine as a state diagram.
- **Studio mode:** State Machine (toolbar picker with candidate selector; low-confidence banner surfaces partial detections).
- **Parser:** `StateMachineExtractor` detects `(hostType, enumType)` pairs and resolves transitions triggered by function names, classifying confidence as `high` (canonical: explicit enum annotation + switch-driven self-assign), `medium` (type inferred from initializer), or `low` (assignments outside a switch). Enums with associated values are rejected.
- **Emitters:** PlantUML (`@startuml` state diagram) and Mermaid (`stateDiagram-v2`). Initial/final pseudo-states use `[*]`.
- **Status history:** the framework (extractor + model + emitters) has been shipped for some time; the `swiftumlbridge state` CLI subcommand landed on 2026-04-20 to close the loop. A companion fix switched the CLI executable to `@main`/`AsyncParsableCommand` so all subcommands (`classdiagram`, `sequence`, `deps`, `activity`, `state`) actually run from `swift run`.

### 8. Use case diagram — **medium value**

Actors and their interactions with system use cases.

- **Why it's popular:** early-phase requirements diagram; standard in textbooks and RFPs.
- **Swift relevance:** low — use cases live in requirements docs, not source. Could be inferred partially from public API surface ("what can external callers do?") but would be crude.
- **Implementation cost:** medium if auto-inferred, low if authored via DSL. **Optional; nice for marketing screenshots but not source-derived.**

### 9. Communication diagram — **low–medium value**

Equivalent information to a sequence diagram but arranged spatially (network style) rather than temporally.

- **Why it's popular:** appears in UML courses; rarely in modern practice.
- **Swift relevance:** could be a cheap re-emit of the existing sequence call-graph with a different layout.
- **Implementation cost:** low (reuses sequence extractor, new emitter only). **Low-effort/low-value — defer.**

### 10. Timing diagram — **low value**

Lifeline state changes over a time axis. Mostly used in embedded/RTOS work.

- **Swift relevance:** low for general-purpose Swift. **Skip.**

### 11. Interaction overview diagram — **skip**

A flowchart whose nodes are mini-sequence-diagrams. Rarely drawn in practice. **Skip.**

---

## Non-UML but widely requested

### 12. Entity-Relationship (ER) diagram — **high value, recommended**

Not strictly UML, but expected in any "diagrams" tool. For Swift this maps cleanly onto:

- **Core Data** `.xcdatamodeld` models (entities, attributes, relationships, inverse relationships).
- **SwiftData** `@Model` classes (macro-expanded properties and `@Relationship` annotations).
- **GRDB / SQLite.swift** schemas.

The ER/data-model story is arguably the single biggest gap for iOS/macOS developers using this tool — persistence is ubiquitous and no current command covers it.

- **Implementation cost:** medium. SwiftData is straightforward via SwiftSyntax macro inspection. Core Data requires parsing `contents` XML inside `.xcdatamodeld` bundles. Mermaid has native `erDiagram` syntax; PlantUML has entity syntax.

### 13. Flowchart (Mermaid `flowchart`) — **COVERED by activity diagram**

Effectively the same artifact as an activity diagram. The shipped activity emitter already outputs Mermaid `flowchart TD` directly, so a standalone flowchart command isn't needed.

### 14. Gantt / roadmap — **out of scope**

Project-management artifact; not derivable from source. **Skip.**

### 15. C4 model diagrams (Context / Container / Component / Code) — **medium–high value**

Not UML, but the de facto modern architecture-documentation standard (Simon Brown). Heavy overlap with component + deployment diagrams, with clearer semantics. Mermaid added `C4Context` support. Worth considering as a *viewing mode* layered on top of component + dependency data already extracted.

---

## Prioritized recommendation

If the goal is to maximize "popular diagrams a Swift dev actually wants," ranked by value/cost:

1. ~~**Activity diagram**~~ — **SHIPPED 2026-04-20** (concurrency-aware: async let, TaskGroup).
2. ~~**State machine diagram**~~ — **SHIPPED 2026-04-20** (CLI subcommand closes the remaining gap; framework was already in place).
3. **ER / data-model diagram** — fills the biggest structural gap (persistence) and is a clear differentiator vs. SwiftPlantUML legacy. **Next up.**
4. **Component diagram** — natural extension of the existing `deps` command; adds interface semantics that architects expect.
5. **C4 model views** — layered on top of (4); low incremental cost once component data exists.
6. **Package diagram** — minor extension of `deps --modules`; low priority.
7. *(Defer / skip)* Object, Deployment, Composite Structure, Profile, Communication, Timing, Interaction Overview, Use Case, Gantt.

## Architectural impact

The existing three-layer split (Parsing → Model → Emitter) accommodates new diagram types cleanly. For each new type we add:

- `Sources/SwiftUMLBridgeFramework/Parsing/<Name>Extractor.swift`
- `Sources/SwiftUMLBridgeFramework/Model/<Name>Model.swift` + `<Name>Generator.swift`
- `Sources/SwiftUMLBridgeFramework/Emitters/<Name>+PlantUML.swift`, `<Name>+Mermaid.swift`
- `Sources/swiftumlbridge/Commands/<Name>Command.swift` (wired into `SwiftUMLBridge.swift` subcommands)
- Studio: extend `DiagramMode` enum and `DiagramViewModel`

No framework restructuring required — each new diagram is additive.

## Test-coverage baseline (2026-04-20)

Measured after the activity + state-machine work landed.

- **`SwiftUMLBridgeFramework` (via `swift test --enable-code-coverage`)**: **94.63% line coverage** (744 Swift Testing cases across 62 suites).
- **`SwiftUMLStudio.app` (via `xcodebuild test` — unit + UI combined)**: **83.44%**. The three `Canvas`-based native renderers (`NativeDiagramView`, `NativeSequenceDiagramView`, `NativeActivityDiagramView`) were 0% before live UI tests were added; they now sit at 66–77% — the remaining gap is pan/zoom gesture branches that only fire on real user input.
- **Package platform baseline:** `Package.swift` now matches the Xcode app target at `.macOS(.v26)` (previously `.v13`), removing the need for availability annotations around Swift Concurrency APIs.

## (Other) PlantUML Diagrams
For UML specifically, PlantUML handles
 
* _**COVERED**_ sequence diagrams, 
* use case diagrams, 
* _**COVERED**_ class diagrams (which can be used to create Entity-Relationship aka ER diagrams), 
* object diagrams, 
* _**COVERED**_ activity diagrams, 
* component diagrams, 
* deployment diagrams, 
* _**COVERED**_ state diagrams, and 
* timing diagrams 

That's the core nine UML diagram types. SwiftUMLStudio now ships five of them (class, sequence, activity, state, plus the non-UML dependency graph) as first-class CLI subcommands and Studio modes.

Beyond standard UML, it also supports 

* JSON data visualization, 
* YAML visualization, 
* network diagrams (nwdiag), 
* wireframes/salt, 
* archimate diagrams, 
* specification and description language (SDL), 
* Ditaa diagrams, 
* Gantt charts, 
* MindMap diagrams, 
* Work Breakdown Structure (WBS) diagrams, and
* entity-relationship diagrams.

_Source:_ Claude (non-code)