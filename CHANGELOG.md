# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This file covers both the **SwiftUMLBridge** package (CLI + framework) and the **SwiftUMLStudio** macOS app.

---

## [Unreleased]

### Added — Bridge

- **M15: DocC documentation catalog for `SwiftUMLBridgeFramework`.** A
  `SwiftUMLBridgeFramework.docc` catalog gives the framework a curated
  landing page (Overview plus topic groups for the seven generators,
  configuration, emitted scripts, per-diagram model layers, layout, and
  rendering) and a `Generating Diagrams` getting-started article. Hosted
  by Swift Package Index via the existing `.spi.yml`
  `documentation_targets`. Also fills in doc comments on previously
  thin public model types (`Configuration`, `ElementOptions`,
  `RelationshipOptions`, `Stereotype` / `Spot`, `SequenceLayout` and its
  participant / message structs).

- **M12 follow-up: `deps --package <Package.swift>`.** Module-aware
  dependency graphs for SPM packages. In `--modules` mode each edge
  comes from a target's `target_dependencies` (authoritative — no
  source-level import parse, system frameworks excluded), and each
  internal node is stereotyped with its target kind:
  `component "Networking" as Networking <<library>>`. In `--types` mode
  each inheritance / conformance edge is tagged with the owning SPM
  target, rendered as `class "Foo" as Foo <<Module>>` (parallels the
  M12 `classdiagram --package` stereotype). Test targets are excluded.

### Added — Studio

- **M12 follow-up: Dependency graph picks up SPM module info when a
  package is loaded.** `DiagramViewModel.generateDependencyGraph()` now
  routes through `DependencyGraphGenerator.generateScript(forPackage:…)`
  whenever `Open Package…` has set `packageDescription` /
  `packageRoot`, mirroring the existing class-diagram branch. The
  result is the same `<<library>>` / `<<Module>>` stereotypes the CLI
  emits, surfaced in Studio's three-pane workspace and Insights without
  any UI changes. Path-based generation remains the fallback when no
  package is loaded.
- **M11 follow-up: Per-module dashboard.** When an SPM package is
  loaded, the Explorer-mode dashboard surfaces a new **Modules**
  section above Insights. One card per non-test SPM target shows the
  module's name (with the same deterministic swatch color the native
  canvas already uses for the per-node stripe), its target kind chip
  (`library` / `executable`), and three counts: source files, types,
  and outgoing `target_dependencies`. Driven by a new
  `ProjectAnalyzer.analyze(package:packageRoot:)` overload that emits a
  `ModuleSummary` per target.
- **M12 follow-up: Module-grouped class-diagram layout.** When an SPM
  package is loaded, the native class-diagram canvas now draws each
  module as a tinted, dashed grouping box behind the types it owns,
  labelled with the module name in its deterministic per-module color.
  Layout is driven by `DagreLayoutEngine` running in compound-graph
  mode — one parent node per module — so the engine itself clusters the
  types and reports a bounding box per module (new `LayoutCluster` on
  `LayoutGraph`). The per-node bottom stripe is now a fallback, drawn
  only when no cluster boxes are present. Closes the last deferred
  M11/M12 Studio bullet.

### Changed — Bridge

- **`DependencyGraphGenerating` protocol gains a `forPackage` entry**
  with a default implementation that falls back to the path-based
  `generateScript(for:mode:with:)` over `sourceFileToModuleMap`. Mirrors
  the existing `ClassDiagramGenerating` shape so Studio's mock-injected
  generators degrade gracefully.
- **M12 follow-up: Mermaid and Nomnoml emit the SPM module stereotype.**
  `classdiagram --package` previously rendered the owning target name
  only in PlantUML output (`<<class>> <<Networking>>`); Mermaid and
  Nomnoml silently dropped the field. Both emitters now append the
  module as an additional `<<Module>>` annotation on each class node,
  matching PlantUML. The same parity applies to `deps --package`:
  Mermaid flowchart node labels gain a `<br/>«stereotype»` line
  (`App["App<br/>«executable»"]`) and Nomnoml inlines the stereotype
  into edge endpoints (`[App «executable»] --> [Core «library»]`).
  Closes the "Mermaid/Nomnoml emitter changes" deferred bullet across
  both `classdiagram` and `deps`.
- **M12 follow-up: `DagreLayoutEngine` gains compound-graph layout.**
  When a `LayoutGraph`'s nodes carry `module` values, the engine builds
  the dagre graph in compound mode — one parent node per module, every
  type re-parented beneath it — so dagre clusters the types and reports
  a bounding box per module. Results are parsed into a new
  `LayoutCluster` array on `LayoutGraph`; `SVGRenderer` draws each as a
  tinted, dashed labelled box behind the nodes. Graphs without module
  info are unaffected (plain non-compound layout, empty `clusters`).
- **Internal: duplication cleanup across the package (no behavior
  change; all 870 package tests still pass).** Consolidated repeated
  logic surfaced by `pmd cpd` — the package dropped from 30 copy-paste
  blocks to 4 (the remainder deliberate: base64 bit-twiddling,
  structurally-distinct loop skeletons):
  - XML and nomnoml escaping unified into `String.xmlEscaped` /
    `.nomnomlEscaped`, replacing copies in `SVGRenderer`,
    `SequenceSVGRenderer`, `ActivitySVGRenderer`,
    `ComponentSVGRenderer`, `SyntaxStructure+Nomnoml`, and `DepsScript`.
  - The CLI subcommands share a `CommonDiagramOptions` `@OptionGroup`
    (the `--format` / `--output` / `--config` triplet plus config
    resolution) and an `Optional<ClassDiagramOutput>.present(_:)`
    presenter selector, replacing the per-command `switch output` blocks.
    Entry-point parsing moves to `String.parsedEntryPoint()`.
  - New `TypeStackVisitor` base class hosts the
    class/struct/enum/actor/protocol/extension push-pop walk shared by
    `CallGraphExtractor` and `StateMachineExtractor`;
    `SyntaxStructureBuilder` collapses its five generic-bearing
    type-declaration visitors into one `handleTypeDeclaration` helper.
  - The three class-diagram emitters share `renderDiagramText` (the
    skip / generics / linking flow) and `renderableMember` (the member
    filter) via a new `SyntaxStructure+EmitterShared`.
  - Smaller shared helpers: `String.globPatternToRegex()`,
    `SyntaxStructure.isExcluded(byPatterns:)`,
    `CallGraphExtractor.entryPoints(for:)`, plus within-file dedup in
    `StateScript`, `SequenceScript`, `ActivityGraphBuilder+ControlFlow`
    (`wireBranch`), and `DependencyGraphGenerator` (`typeEdgeBasis`).

### Changed — Studio

- **Internal: native-canvas and view duplication cleanup (no behavior
  change; Studio's 439 unit and 20 UI tests still pass).** Reduced the
  app from 19 copy-paste blocks to 3 (the remainder the class/sequence
  interactive scaffold, whose modifier order matters for hit-testing):
  - The four native `Canvas` renderers share `canvasPanZoom` and
    `diagramCanvasChrome` view modifiers; the two non-interactive ones
    (activity, component) share a full `DiagramCanvasContainer` body.
    Arrowhead and center→bounds math move to
    `DiagramDrawing.fillArrowhead` and a `CenterPositioned.boundingRect`,
    and the title to `DiagramDrawing.drawTitle`.
  - UI components extracted: `EntryPointPicker` (activity / sequence
    control bars), `AppModePicker` + `PathSummaryLabel` (developer and
    Explorer toolbars), `HistoryListContent` (history list shared by
    `HistorySidebar` and the Explorer sidebar), and `SuggestionHandler`
    + a `.paywallSheet` modifier for the pro-gated suggestion dispatch
    shared by `ExplorerDetailView`, `ExplorerSidebar`, and
    `DiagramDetailView`. Accessibility identifiers are preserved, so the
    UI-test selectors are unchanged.
  - `DiagramViewModel` gains a `resolveEntryPoint()` helper shared by the
    activity and sequence generators.

---

## [1.0.0] — 2026-05-11

First v1 cut. Component diagrams gain full Studio parity with the
other diagram types — including a native SwiftUI canvas, an SVG
format option, and PDF/PNG/SVG export — and CI is finally fully
green across both jobs.

### Added — Component Diagram in Studio

- **`DiagramMode.componentDiagram`** — Studio now surfaces the
  previously CLI-only Component diagram type. New row under the
  "Structural" section of the workspace sidebar (`shippingbox` icon),
  paywall-gated as `ProFeature.componentDiagrams`, with a
  guide-the-user-to-`Open Package…` empty state when no SPM
  package is loaded (Component diagrams are inherently
  package-scoped).
- **`ComponentDiagramGenerating` protocol** — Bridge gains the
  abstraction the other generators already had, so Studio can
  mock-inject `ComponentDiagramGenerator` for tests the same way
  it does class / sequence / deps / state / activity / ER.
- **`ComponentLayout` + `PositionedComponent`** — new public IR for
  laid-out component diagrams, mirroring `ActivityLayout` and
  `SequenceLayout`. Drives the native canvas in Studio.
- **`ComponentSVGRenderer`** — topological-level layout (consumer
  components at the top, depended-on leaves at the bottom; cycle-safe
  via a visiting-set guard) plus a standalone SVG document used as
  the WebView fallback when the user picks `.svg`.
- **`ComponentScript.componentLayout`** — populated when the script
  is rendered in `.svg` format; nil for PlantUML / Mermaid.
- **`DiagramOutputting.componentLayout`** — new optional protocol
  requirement with a `nil` default so existing conformers are
  unaffected.
- **`NativeComponentDiagramView`** — SwiftUI `Canvas` renderer with
  «component» header band, interface list, dotted dependency
  arrows, pan / zoom / ⌘+scroll-wheel zoom, and PDF / PNG / SVG
  export through the existing `DiagramExportMenu` plumbing.
- **Native canvas branches** in `DiagramPreviewView` and
  `DiagramExportMenu` for `componentLayout`. Viewport controls and
  the Export menu now light up in Component mode when `.svg` is
  picked.

### Added — Tests

- **11 new ComponentSVGRenderer tests** covering layout (single /
  multi component, dependency ordering, cycle safety, label-based
  sizing, input-order preservation), SVG output shape, and
  script-level format dispatch including Nomnoml → PlantUML fallback.
- **`MockComponentGenerator`** + dispatch / format-propagation
  coverage in `DiagramViewModelMockTests`.

### Changed — Test Stability

- **Mock generation tests** in `DiagramViewModelMockTests` /
  `DiagramViewModelMockStateTests` and the integration tests in
  `ViewModelFeatureTests` switched from a fixed
  `Task.sleep(for: .milliseconds(500))` (and a 10s wall-clock
  polling helper) to `await viewModel.currentTask?.value`. The
  former raced under CI load on macos-26; the deterministic task
  wait removes the flake without inflating local test wall-time.
- **DashboardUITests** — toolbar Save / Open buttons now carry
  `toolbarSaveButton` / `toolbarOpenButton` /
  `toolbarOpenPackageButton` accessibility identifiers, queried
  with `.firstMatch` to disambiguate the duplicate element the
  macOS 26 accessibility tree exposes on toolbar wrappers.

### Fixed — CI

- **Studio job now actually runs.** Pinned to the `macos-26`
  runner — `macos-latest` is still macOS 15, which can't load
  Studio's macOS 26.4+ test bundle. Bridge stays on
  `macos-latest` because it explicitly targets `.v15` for SPI
  reach.
- **Bridge platform lowered** to `.macOS(.v15)` so the package
  builds on the same CI runner that hosts every other Sequoia
  machine on the team. Studio still targets 26.4+.
- **Code signing disabled** for CI Studio builds
  (`CODE_SIGNING_ALLOWED=NO` + `CODE_SIGNING_REQUIRED=NO` +
  `CODE_SIGN_IDENTITY=`) — the development certificate is
  local-only and not available to runners; the binary isn't
  distributed from CI.
- **Pinned to `latest-stable` Xcode** via
  `maxim-lobanov/setup-xcode` so the Swift 6.2 toolchain the
  Bridge package manifest requires is actually present, and
  stopped hiding `xcodebuild` failures behind `xcbeautify`'s
  exit status.
- **Stale ProFeatureTests count** updated for the new
  `componentDiagrams` Pro feature case.

### Fixed — Bridge

- **`ClassDiagramCommand` help-text line length** — wrapped a 211-
  char `@Option(help:)` string to stay under the 200-char
  hard SwiftLint cap.

---

## [0.3.0] — 2026-05-09

This release lands every diagram type planned for the v1.0 surface
(seven total), the SwiftUML Studio macOS app with Explorer / Developer
modes and a Pro tier, the SwiftSyntax-primary parser, native SVG
rendering, and the Swift 6 strict-concurrency migration. Remaining
v1.0 work is App Store / SPI / Homebrew distribution and a small
backlog of explicitly-deferred Studio integrations called out below.

### Added — Diagram Types

- **Dependency graphs (M4)** — `swiftumlbridge deps` CLI command with `--modules`, `--types`, `--public-only`, `--exclude`; module-level and type-level dependency analysis with cycle detection; PlantUML and Mermaid emitters
- **Activity diagrams (M5)** — `swiftumlbridge activity` CLI; control-flow extraction from imperative function bodies (branches, loops, `switch`, `do/catch`); native SVG renderer
- **State machine diagrams (M6)** — `swiftumlbridge state` CLI; enum-driven state machine detection with confidence scoring, where-clause guards, property-wrapper enum inference; PlantUML, Mermaid, and SVG emitters
- **Entity-Relationship diagrams (M7)** — `swiftumlbridge er` CLI; SwiftData `@Model` and `@Relationship` extraction; PlantUML entity and Mermaid `erDiagram` emitters
- **ER expansion: Core Data + GRDB + SQLite.swift (M7+)** — `swiftumlbridge er` now also accepts Core Data `.xcdatamodeld` bundles (XML parsed via `XMLDocument`, version selected via `.xccurrentversion`, parentEntity surfaced as an "is a" edge) and Swift sources containing GRDB (`FetchableRecord`/`PersistableRecord`/etc. with `belongsTo` / `hasMany` / `hasOne` typed cardinality) or SQLite.swift (`Table("name")` + `Expression<T>("col")` namespace types). Studio's Open dialog accepts `.xcdatamodeld`. Closes all four sub-milestones (C1, C2, G1, G2) of `docs/internal/er-diagram-expansion-plan.md`.
- **Component diagrams** — new `swiftumlbridge component --package <Package.swift>` subcommand. Maps SPM targets to UML components, lists each target's public types as provided interfaces, and renders `target_dependencies` as `..>` edges. PlantUML emits standard `component` syntax with `<<library>>` / `<<executable>>` / `<<test>>` stereotypes; Mermaid falls back to a `flowchart TD` with subgraphs (Mermaid lacks a dedicated component dialect). Test targets are excluded by default; `--include-test-targets` opts in. Fills #4 ("Component diagram") in the prioritized ranking of `docs/internal/missing-uml-diagrams.md`. Studio integration deferred.

### Added — Output Formats

- **Nomnoml** class diagram emitter with locally bundled JS for offline rendering
- **Native SVG** format with Dagre layout via JavaScriptCore (Phase D), plus a SwiftUI `Canvas` renderer for in-app display

### Added — Parsing

- **SwiftSyntax-primary parser (M5)** — replaces SourceKitten as the primary AST source for newer functionality; SourceKitten retained for declarations
- **Macro-aware stereotypes** — `MacroConformanceTable` maps macros (`@Observable`, `@Model`, etc.) to synthetic conformances surfaced in diagrams
- Attribute fields exposed on `SyntaxStructure` for macro-aware diagrams
- **Multi-module SPM cross-references (M12)** — public `SPMPackageDescription` / `SPMTargetDescription` types and an `SPMPackageReader` that runs `swift package describe --type json`; new `ClassDiagramGenerator.generateScript(forPackage:packageRoot:)` entry tags each parsed type with its owning target. PlantUML emits the module as an additional stereotype (`<<class>> <<Networking>>`). Surfaced via `swiftumlbridge classdiagram --package <Package.swift>`. Mermaid/Nomnoml emitter changes, `--package` on `deps`, and Studio integration deferred.
- **`SequenceParticipant.sourceLocation`** — sequence-diagram participants now carry the source location of their underlying type so the Studio app can support reveal-in-source on participant clicks. `SequenceSVGRenderer.computeLayout` accepts an optional `typeLocations: [String: SourceLocation]` map that `SequenceDiagramGenerator` builds from a second pass over each file.

### Added — Diagram Interaction

- **Unified `DiagramViewport`** shared by the class, sequence, and activity native canvases — replaces three duplicated copies of scale/offset state
- **Floating zoom toolbar** (top-trailing): zoom in / zoom out / fit-to-window / actual size / reset, with a live percent label and standard mac shortcuts (⌘= ⌘− ⌘9 ⌘0 ⇧⌘R)
- **Single-click node selection** on class diagrams — selected node is drawn with an accent-colored ring; clicking the canvas background clears the selection
- **`SourceLocation` on `LayoutNode`** — public framework type carrying file path + 1-based line/column, populated by `SyntaxStructureBuilder` from a SwiftSyntax `SourceLocationConverter` for class / struct / enum / actor / protocol / extension declarations
- **"Reveal in Source"** floating button (⌘J) — when a node with a known `sourceLocation` is selected, opens the file in the developer-layout source pane, scrolls to the line, and highlights it in yellow
- **`SourceEditorView` rewritten** as an `NSViewRepresentable` around `NSTextView` to support line scrolling and back-fill highlighting (replaces the previous disabled `TextEditor`)
- **Hover tooltips** on class-diagram nodes — top-leading floating panel showing the node's stereotype, label, and (when available) the source `filename:line`
- **Diagram export menu** (top-trailing) — saves the currently-displayed diagram as PDF (vector, via SwiftUI `ImageRenderer` + `CGContext` PDF consumer), PNG (raster, 2× retina), SVG (when the script's format is already SVG), or source text (`.puml` / `.mmd` / `.nomnoml`) for WebView-rendered formats. Menu items adapt to what the active script supports.
- **Sequence-diagram selection + click-to-source** — single-click a participant box (top or bottom mirror) selects it (accent ring), hover shows the `NodeInfoTooltip`, and "Reveal in Source" jumps to the underlying type's declaration when known. Mirrors what class diagrams gained in the earlier phases.
- **Cmd+scroll-wheel zoom** on all three native canvases — wraps the SwiftUI canvas in an `NSHostingView` subclass that intercepts ⌘+scroll and calls `viewport.zoomIn`/`zoomOut`. Non-⌘ scroll falls through so trackpad pan still works. Cursor-centered zoom deferred.
- **Arrow-key navigation between selected nodes** — when a class- or sequence-diagram canvas has keyboard focus, arrow keys move the selection to the spatially nearest node in that direction (via `NativeDiagramGeometry.nextNode` — picks the closest candidate strictly past the current node along the dominant axis); Esc clears selection. Sequence diagrams only honor left/right since participants share a single row. Pressing an arrow with nothing selected picks the leftmost-topmost node as the starting point.

### Changed — Theming

- **Dark mode polish across native canvases and WebViews.** Native renderers now use `Color(nsColor: .labelColor)` / `.controlBackgroundColor` / `.textBackgroundColor` instead of hardcoded near-white/near-black values, so diagrams render correctly in dark mode. Activity-diagram start/end terminals and fork/join bars switched from a near-black fill (which disappeared into the dark background) to `.labelColor`. Mermaid in `DiagramWebView` now reads `colorScheme` and emits `theme: 'dark'` with a dark page background when applicable; Nomnoml and the SVG fallback adapt their page background. PlantUML remote rendering remains light-only (planttext.com is outside our control); Nomnoml's canvas content also stays light because nomnoml.js draws with hardcoded colors — both documented as known limitations.

### Added — Studio App

- **Two app modes** (`AppMode`): `explorer` (insight-driven default) and `developer` (full-featured three-pane workspace), toggled via the toolbar Picker
- **Project Dashboard** (`ProjectDashboardView`) with stats, insights, and one-click suggestion cards
- **InsightEngine** — plain-language project insights derived from `ProjectAnalyzer`
- **SuggestionEngine** + `SuggestionDispatcher` — actionable diagram suggestions with confidence scoring
- **Explorer Mode** — simplified UI for non-developer users (`ExplorerSidebar`, `ExplorerToolbar`, `ExplorerDetailView`)
- **Pro subscription tier** (StoreKit 2) — `SubscriptionManager`, `SubscriptionProviding`, `FeatureGate`, `PaywallView`, `ReviewReminderManager`, `Configuration.storekit`
- **Architecture Change Tracking (Phase 4)** — diff view comparing snapshots over time for Pro subscribers (`ArchitectureDiffView`, `ProjectSnapshot`, `SnapshotManager`)
- **3-pane NavigationSplitView** layout with sidebar / detail / inspector
- **History sidebar** with diagram restoration and entry-point menu
- **File browser sidebar** with tabbed preview
- **Live-updating preview** with explicit save action
- **MarkupView** annotation overlay tied to diagram entities
- **Inspector strip** + per-mode controls (`SequenceControlsView`, `ActivityControlsView`)
- **SPM package mode** — new "Open Package…" toolbar button (⇧⌘O) opens an SPM directory and runs `swift package describe` off the main actor; class-diagram generation switches to the module-aware `generateScript(forPackage:)` entry. Each native-canvas node gets a thin colored stripe along its bottom edge with the owning module's name (deterministic per-module color via `NativeDiagramGeometry.moduleColor`). The `ClassDiagramGenerating` protocol gained a default-implementing `generateScript(forPackage:)` so mocks degrade gracefully to the path-based flow. Per-module dashboard and module-grouped layout deferred.

### Added — Tests & Quality

- ViewInspector test coverage for `ProjectDashboardView`, `ArchitectureDiffView`, `PaywallView`, `DiagramPreviewView`, `HistoryItemRow`, `SnapshotRowView`, `MarkupView`
- Geometry helpers extracted from `NativeDiagramView` and `NativeSequenceDiagramView` for unit-testable layout
- Protocol abstractions (`DiagramGenerating` family, `SubscriptionProviding`) for dependency-injected testing
- SampleProject fixture enriched for state-machine and sequence-diagram coverage
- 89% test coverage on the Bridge package, 70%+ on the Studio app

### Changed

- **Project rename**: `SwiftPlantUMLstudio` → `SwiftUMLStudio` (working dir, GitHub repo, all targets)
- **Migrated persistence from Core Data to SwiftData** (`PersistenceController`, `DiagramEntity`, `ProjectSnapshot`)
- Modernized to macOS 26 `Tab` API in detail pane (replacing deprecated `tabItem()`)
- Moved project analysis off the main actor to avoid UI blocking
- Switched `Task.sleep` to `Duration`-based API
- Async/await for notification authorization request
- PRD revised to v1.2 covering both Bridge and Studio as first-class products
- CLAUDE.md refreshed to reflect post-M10 state (six diagram types, Swift 6 strict concurrency, Studio architecture)

### Fixed

- Sequence diagram regeneration bug from file-browser sidebar
- `@MainActor` test hangs and Core Data crashes on macOS 26 beta
- DiagramEntity crash; toolbar overflow on small windows
- Empty-paths crash in `ProjectAnalyzer`
- Test isolation issues (UserDefaults injection, removed no-op `.serialized`)
- All SwiftLint violations (multiple cleanup passes — final state: zero warnings, zero errors)
- Accessibility labels and deprecated APIs in native Canvas views
- Stale `ProFeatureTests` and `DiagramModeTests` after enum cases were added

### Removed

- Obsolete plan docs from earlier phases

---

## [0.2.0] — 2026-02-28

### Added

- **M2 — Mermaid.js class diagram output** — first-class Mermaid emitter alongside PlantUML
- **M3 — Sequence diagrams** — static call-graph extraction (`CallGraphExtractor`) and `SequenceDiagramGenerator` with PlantUML and Mermaid emitters; `--depth` and `--entry` CLI flags
- Studio user guide
- GitHub README

### Changed

- Eliminated all force unwraps and `@unchecked Sendable` annotations from the parsing and emitter layers

### Fixed

- SwiftLint violations across the SwiftUMLBridge package

---

## [0.1.0] — 2026-02-27

### Added

- SwiftUMLBridge local Swift package (M0): three-layer parsing/model/emitter architecture powered by SourceKitten, swift-argument-parser, and Yams
- `swiftumlbridge classdiagram` CLI command with `--format`, `--output`, `--sdk`, and `--exclude` options
- `BridgeLogger` singleton wrapping `os.Logger` (replaces SwiftyBeaver)
- macOS SwiftUI studio front-end (M1): file picker, PlantUML preview via planttext.com WebView, toolbar Generate button
- User guide, tutorial, and reference documentation in `docs/`
- Test suite raising SwiftUMLBridge framework coverage from 35% to 89% (229 tests)

### Changed

- **Swift 6 strict concurrency** (`846adfa`):
  - Enabled `swiftLanguageMode(.v6)` in `Package.swift` and `SWIFT_VERSION = 6.0` in the Xcode project for all targets
  - `DiagramPresenting` protocol replaced callback-based `present(script:completionHandler:)` with `async func present(script:)` and added `Sendable` conformance
  - `ClassDiagramGenerator.generate()` methods are now `async`; `DispatchSemaphore`-based `outputDiagram()` removed
  - New public `ClassDiagramGenerator.generateScript(for paths: [String], ...)` synchronous method as the GUI integration point
  - `BrowserPresenter.present()` wraps `NSWorkspace.shared.open()` in `await MainActor.run {}`
  - `BridgeLogger.shared` changed from `var` to `let`; class marked `@unchecked Sendable`
  - `DiagramScript` and `SyntaxStructure` marked `@unchecked Sendable`
  - Full `Sendable` conformance added to all model value types: `Color`, `Theme`, `Version`, `Stereotype`/`Stereotypes`/`Spot`, `Configuration`, `AccessLevel`, `ExtensionVisualization`, `RelationshipInlineStyle`, `RelationshipStyle`, `Relationship`, `RelationshipOptions`, `FileOptions`, `ElementOptions`, `PageTexts`
  - Static mutable singletons and collections converted from `var` to `let`
  - `ClassDiagramCommand` and `SwiftUMLBridgeCLI` migrated to `AsyncParsableCommand`
  - App `DiagramViewModel` replaced GCD + `SwiftUIPresenter` with `Task { await Task.detached { }.value }`
- `Color` enum cases converted to camelCase
- Yams dependency bumped from 5.0.0 to 6.0.0

### Removed

- `SwiftUIPresenter.swift` — no longer needed after async protocol migration
- `outputDiagram(for:with:processingStartDate:)` internal method on `ClassDiagramGenerator`
- All `DispatchSemaphore` usage

### Fixed

- All SwiftLint violations resolved at project inception
