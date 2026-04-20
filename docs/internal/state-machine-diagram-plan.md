# State Machine Diagram — Implementation Plan

Adds State Machine as a 4th diagram type alongside Class, Sequence, and Dependency. Ships Pro-gated as part of the Explorer Mode v2.0 pivot.

## Scope

Detect Swift state machines expressed as an enum + host type with switch-driven self-assignment, and render them as UML state diagrams in PlantUML, Mermaid, Nomnoml (fallback), and SVG.

Supported source patterns:
- Enum-based state (`enum State { case idle, loading, loaded, error }`) with a method that switches on it and assigns `self.state = .newCase`.
- SwiftUI `@State` / `@Published` enum properties inside `ObservableObject` / `@Observable` types.
- Actor lifecycle / `TaskState` enums.
- `NavigationStack` / `NavigationPath` route enums.

## 1. Parsing (SwiftUMLBridge)

New file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/StateMachineExtractor.swift`. Mirror `CallGraphExtractor.swift`. Produce `[StateMachineCandidate]` per file.

Minimum viable heuristic (union of signals, ranked by confidence):

1. `EnumDeclSyntax` where every `EnumCaseElementSyntax` has no associated values (or only simple raw values). Collect cases as candidate states.
2. Host type (class/struct/actor) with a stored property whose type matches that enum — `@State`, `@Published`, `@Observable` storage, or plain `var state: MyEnum`.
3. Within the host, a `FunctionDeclSyntax` containing either:
   - `SwitchExprSyntax` over the state property / enum-typed parameter, and/or
   - `InfixOperatorExprSyntax` with `=` assigning `.caseName` to that property.
   Each `case .X:` branch that assigns `.Y` yields transition `X → Y` with enclosing function name as trigger.
4. Fallback (low confidence): enum decl whose cases are referenced in ≥2 assignment RHS positions anywhere — surface with `confidence: .low`.

Expose `StateMachineExtractor.extract(from: String) -> [StateMachineCandidate]` and a higher-level `StateMachineGenerator` parallel to `SequenceDiagramGenerator` with `findCandidates(for:)` + `generateScript(for:stateType:with:)`.

NavigationPath and actor TaskState are specializations of rules 1+3 — no extra parser logic for v1; document them as supported fixtures.

## 2. Model

New files in `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/`:

- `StateMachineModel.swift`
  - `struct State { name, isInitial, isFinal }`
  - `struct Transition { from, to, trigger, guardText? }`
  - `struct StateMachineModel { hostType, enumType, states, transitions }`
- `StateMachineGenerator.swift` + `StateMachineGenerating` protocol alongside `DiagramGenerating`.

Initial/final heuristics: first case becomes `[*] → case` initial; a case with no outgoing transitions but incoming edges is marked terminal only if its name matches `/done|finished|completed|terminated|error/i`.

## 3. Emitters

New file: `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/StateScript.swift`. Model on `SequenceScript.swift`, conform to `DiagramOutputting`.

Per format:

| Format   | M1  | M2  | Notes                                                          |
|----------|-----|-----|----------------------------------------------------------------|
| PlantUML | yes | yes | `@startuml ... [*] --> Idle ... @enduml`                       |
| Mermaid  | no  | yes | `stateDiagram-v2`                                              |
| Nomnoml  | no  | yes | Unsupported natively — fall back to Mermaid (same as sequence) |
| SVG      | no  | yes | Reuse Mermaid HTML pipeline via `MermaidHTMLBuilder`           |

## 4. Studio UI

- `SwiftUMLStudio/DiagramMode.swift` — add `case stateMachine = "State Machine"`.
- `SwiftUMLStudio/FeatureGate.swift` — add `case stateMachines` to `ProFeature`; Pro-gate in `ContentView.swift` alongside sequence/deps gating.
- `DiagramViewModel.swift` — add `var stateScript: StateScript?`, `var stateHostType: String = ""`, `var availableStateMachines: [String] = []`; extend `currentScript` switch.
- `DiagramViewModel+Generation.swift` — add branch persisting `entryPoint = stateHostType.enumType`.
- `ContentView.swift` controls row — add state-machine picker populated from `stateGenerator.findCandidates(paths)` (mirror `SequenceControlsView`).
- `DetailPaneViews.swift`, `ExplorerSidebar.swift`, `ExplorerDetailView.swift` — add the 4th toolbar button.
- `HistoryItemRow.swift` — show enum host for state entries.

## 5. Tests

Swift Testing (`@Test`, `#expect`), target ≥80% coverage.

New files under `SwiftUMLBridge/Tests/SwiftUMLBridgeFrameworkTests/`:

- `ModelTests/StateMachineExtractorTests.swift`
- `ModelTests/StateMachineGeneratorTests.swift`
- `EmitterTests/StatePlantUMLTests.swift`
- `EmitterTests/StateMermaidTests.swift` (M2)

Fixtures under `TestFixtures/SampleProject/`:

- `SimpleTrafficLight.swift` — classic 3-state enum + switch
- `LoadingStore.swift` — `@Published` enum inside `ObservableObject`
- `AsyncTaskActor.swift` — actor + `TaskState` enum
- `NavigationRouter.swift` — `NavigationPath` + route enum
- `NotAStateMachine.swift` — negative case: discriminated union with associated values, no self-assignment

Studio-side: extend `DiagramViewModelTests.swift` and `DiagramViewModelMockStateTests.swift` with a `.stateMachine` mode path.

## 6. Risks

- **False positives** — discriminated-union enums (e.g., `Result`, `ViewModel.Action`) that never self-assign. Mitigate by requiring at least one `self.prop = .case` assignment.
- **Indirect transitions** — state set via delegate, async continuation, or reducer (TCA). v1 will miss these; document as known limitation, surface `.low` confidence with warning banner.
- **Multiple hosts per enum** — same enum driven by two types. Emit one diagram per (host, enum) pair; user picks host.
- **Guards/conditions** — capture `where` clause text as guard string; skip if too complex.
- **Performance** — O(files × nodes) like existing extractors; cache per-file results via the `SyntaxStructureProvider` pattern.

## 7. Milestones

| Milestone | Scope                                                                                   | Estimate |
|-----------|-----------------------------------------------------------------------------------------|----------|
| **M1**    | PlantUML-only, enum+switch+self-assign heuristic, host/enum picker, Pro-gated           | 2–3 days |
| **M2**    | Mermaid emitter + SVG via Mermaid pipeline; `@Published`/`@State` property-wrapper polish | 1–2 days |
| **M3**    | NavigationPath + actor `TaskState` fixtures and docs; guard-clause capture; history integration | 1–2 days |
| **M4**    | Confidence scoring; low-confidence candidate surfacing with warning; Explorer Mode v2 surfacing | 1–2 days |

## Critical Files

- `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Parsing/CallGraphExtractor.swift` — pattern for new extractor
- `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/SequenceDiagramGenerator.swift` — pattern for generator
- `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/SequenceScript.swift` — pattern for emitter + Nomnoml fallback
- `SwiftUMLStudio/DiagramMode.swift` — add 4th case
- `SwiftUMLStudio/DiagramViewModel.swift` — wire script + picker state

## Remaining Gap

### Gap 1 — missing on-disk fixture files (real)

The plan (section 5) named five files to live under `TestFixtures/SampleProject/`:

| File | Purpose |
|---|---|
| `SimpleTrafficLight.swift` | Classic 3-state enum + switch — canonical positive case |
| `LoadingStore.swift` | `@Published` enum inside `ObservableObject` — property-wrapper path |
| `AsyncTaskActor.swift` | `actor` + `TaskState` enum — concurrency path |
| `NavigationRouter.swift` | `NavigationPath` + route enum — SwiftUI routing path |
| `NotAStateMachine.swift` | Negative case: discriminated union with associated values, no `self.x = .case` — detector must reject this |

None of them exist. The directory only holds the six class-diagram fixtures (`User.swift`, `Document.swift`, `AuthService.swift`, `UserStore.swift`, `NotificationService.swift`, `Identifiable.swift`).

**What's actually covered instead:** the scenarios are tested, but inline as multi-line Swift strings inside `StateMachineExtractorTests.swift`. The `actor Worker` + `TaskState` case lives at lines 264-285, and "NavigationStack route enum is detected" at line 287+. So the detector logic has coverage.

**What's actually lost by not having the files:**

1. **End-to-end pipeline tests** — inline strings exercise the extractor only. A real file on disk would test the whole path (file read → parser → model → emitter → rendered PlantUML/Mermaid), which is what a user actually hits.
2. **Demo/manual-QA ergonomics** — there's no file you can point the Studio app at to see what a `@Published`-backed state machine renders as. Every scenario is buried inside test source.
3. **Discoverability** — a new contributor browsing `TestFixtures/SampleProject/` can't see "here are the patterns we detect." The plan's fixture list was also a taxonomy.
4. **Negative-case assurance** — `NotAStateMachine.swift` specifically guards against mis-classifying `Result`-style or `Action`-style enums. It's the kind of test that's easier to forget if it has no physical home.

None of this is critical. It's documentation + demo + integration-test completeness, not correctness.

