# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This file covers both the **SwiftUMLBridge** package (CLI + framework) and the **SwiftUMLStudio** macOS app.

---

## [Unreleased]

---

## [1.1.0] — 2026-08-16

The first release since v1.0.0 (2026-05-11), covering three months of work
that had accumulated unreleased.

Two themes dominate. **M14** makes Studio distributable through the App
Store: a sandboxed `AppStoreRelease` configuration, security-scoped
bookmarks so saved diagrams survive a relaunch, and a consent gate on the
one feature that sends anything off-device. **M12** finishes multi-module
SPM support, so `--package` now works across `classdiagram`, `deps` and
`component`, and Studio draws module grouping boxes to match.

Alongside those: the CLI gained its first test target, Explorer mode
reached all seven diagram types, two hangs in `component --package` were
fixed, and the framework is now free of `nonisolated(unsafe)`.

### Added — Bridge

- **`SwiftUMLBridgeCLITests` — a test target for the `swiftumlbridge`
  executable.** The CLI previously had no tests and no target, so it sat
  outside every coverage measurement: the Bridge's reported 94.8% was the
  framework alone, and counting the executable the package was nearer 88%.
  The CLI is what the Homebrew formula builds and what users actually run,
  and its argument surface — flag precedence, `--entry` validation, output
  routing — was entirely unverified. Now covered in two layers: parse-only
  tests over the argument surface (including that a three-part
  `MyModule.Loader.load` and a dangling-dot `.load` are both *refused*
  rather than guessed at), then end-to-end `run()` calls per subcommand
  over the fixtures, taking the CLI target from 23.8% to 86.1%. Every case
  passes `--output consoleOnly`, since the default presenter opens a
  browser window. A `LinkageSmokeTests` fails first and unambiguously if
  testing an `@main` executable target from SwiftPM ever regresses into a
  link error.

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

- **M14: App Store distribution build (`AppStoreRelease` + App Sandbox).**
  A third build configuration alongside Debug/Release, defining an
  `APP_STORE_BUILD` compilation condition, so the sandboxed App Store
  build and the unsandboxed direct-distribution build ship from one
  codebase. Under the flag:
  - Every subprocess / `dlopen` path is gated off. A new
    `BridgeConfiguration.skipSourceKitTypenameSupplement` (a *runtime*
    toggle, since the SwiftPM package can't see the host project's
    compilation conditions) short-circuits `buildTypenameMap`, avoiding
    a `dlopen` of `sourcekitdInProc` from the system toolchain —
    SwiftSyntax-only parsing still produces every diagram, only
    inferred-type resolution is lost. `Open Package…` and
    `loadPackage` are likewise disabled rather than shelling out to
    `swift package describe`.
  - Entitlements: `app-sandbox`, `files.user-selected.read-write`
    (NSSavePanel exports write via `data.write(to:)`, which the
    read-only grant would silently fail), and `network.client` for the
    PlantUML WebView fallback. Mermaid/Nomnoml ship their JS bundled and
    need no network.
  - **Security-scoped bookmarks** on `DiagramEntity` and
    `ProjectSnapshot` (additive — SwiftData lightweight migration, no
    schema bump). Raw path strings carry no read access under sandbox,
    so restoring a saved diagram in a later launch previously left the
    view model with unreadable paths and silently produced empty
    diagrams. New `SecurityScopedURL` helpers make, resolve, and
    regenerate-when-stale the bookmarks; unresolvable entries are
    dropped under sandbox with a user-visible notice instead of falling
    back to an unreadable path.
- **Studio surfaces `errorMessage` / `packageLoadError` / `restoreNotice`
  as alerts.** All three view-model fields were set but never displayed,
  so a failed generation, an unopenable Swift Package, and a sandbox
  restore that dropped files each produced no feedback at all.
  `restoreNotice` is a dedicated field rather than a reuse of
  `errorMessage`, because `onChange(of: selectedPaths)` fires a
  `generate()` after restore and `generate()` clears `errorMessage` at
  the start of every run — the warning was being wiped before it could
  display.
- **Explorer mode suggests all seven diagram types.** Explorer navigation
  is entirely suggestion-driven (the mode picker is hidden by design), so
  a diagram type with no card is unreachable there. `SuggestionEngine`
  covered only class, sequence, deps, and state machines, leaving ER,
  Component, and Activity invisible to the mode most users start in. ER
  is gated on the project importing SwiftData / Core Data / GRDB /
  SQLite, detected from the already-computed `moduleImports` rather than
  by running the ER extractor. Component is gated on `moduleBreakdown`
  holding two or more targets — exactly the condition under which the
  diagram is more than a single box. Activity offers one card for the top
  entry point rather than matching sequence's `prefix(3)`, which would
  put six cards on the same handful of methods and crowd out the rest of
  the grid; its copy is deliberately distinct from sequence's ("Step
  through Foo.bar" / the branches and loops inside a method, versus
  "Trace Foo.bar" / which types it calls), pinned by test so the two
  don't drift into reading as duplicates.
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

- **M14: PlantUML rendering now requires one-time consent, and is no
  longer the sandbox default.** PlantUML previews render via
  `planttext.com` — a third-party HTTPS upload of the user's diagram
  source — which was previously undisclosed: the picker listed "PlantUML"
  alongside the local formats and the first preview silently pushed
  source off-device. Three changes: the App Store build defaults to
  Mermaid so a new user makes no network request without opting in
  (direct builds keep PlantUML as the default for backward
  compatibility); the first selection of `.plantuml` raises a consent
  alert disclosing the upload, with Continue persisting the grant and
  Cancel reverting the format; and the picker now reads
  "PlantUML (planttext.com)" so the network use is visible at the point
  of choice. Required for App Store Review privacy disclosure — the
  nutrition label and privacy policy remain outstanding.
- **M14: Mermaid / Nomnoml HTML builders no longer carry a CDN
  fallback.** `mermaid.min.js`, `graphre.js`, and `nomnoml.js` are always
  bundled into the `.app`, so the `cdn.jsdelivr.net` fallback never fired
  in production — but its presence meant a grep over the binary still
  showed third-party HTTPS references, and the "Mermaid and Nomnoml
  render locally" privacy claim had a silent escape hatch. Each fallback
  is replaced with an inline HTML comment marker, visible in DevTools if
  a build is ever misconfigured but incapable of producing a request.
  Tests now assert the invariant directly: no `https://` reference may
  appear in the emitted HTML regardless of bundle state.
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

### Documentation

- **M14 behavior is documented for users.** The sandboxed App Store build's
  differences had shipped with no user-facing documentation at all. The
  Studio User Guide gains an **App Store and Direct Download Builds**
  comparison (default format, `Open Package…` availability, the
  package-dependent features that fall away with it, and the loss of type
  *inference* — not of any diagram type — when SourceKit can't be loaded),
  and Troubleshooting gains matching entries for each symptom.
- **The planttext.com upload is disclosed in prose, not just in the
  consent alert.** A new section states plainly that previewing PlantUML
  sends generated markup — type names, member signatures, relationships,
  but not function bodies or literals — to a third party, that the other
  three formats render locally with no network access of any kind, and
  that the Markup tab is the escape hatch for confidential source.
  Written for the App Store privacy nutrition label, which remains
  outstanding.
- **M11: Xcode Cloud and Fastlane integration guides.** Neither has a
  plugin or marketplace equivalent, so both invoke the CLI directly —
  Xcode Cloud through a `ci_scripts/ci_post_clone.sh` custom build script,
  Fastlane through `sh` in a lane (with a `git diff --exit-code` drift
  check). Both call out `--output consoleOnly` as mandatory on headless
  machines, since the default presenter opens a browser. Closes the last
  open M11 item.
- **Corrected stale statements.** Troubleshooting claimed Mermaid loads
  `mermaid.js` from a CDN and that blocked network access yields a blank
  preview — the CDN fallback was removed and the JS is bundled, so the
  opposite is now true. The Studio guide's Xcode floor was 16.0; the
  embedded package's `swift-tools-version: 6.2` makes it 26.0. Four
  hardcoded `1.0.0` version strings across the user docs are now marked
  as examples so they don't go stale at the next release.

### Changed — Concurrency

- **Every `nonisolated(unsafe)` is gone.** Two sites, both replaced with a
  `Mutex` from `Synchronization` (available at the package's macOS 15
  floor):
  - `BridgeConfiguration.skipSourceKitTypenameSupplement` was one write
    at host start-up racing an unknown number of concurrent reads from
    whichever task was parsing. It held only by the convention that the
    write lands first, which nothing enforced. Setting it is now
    memory-safe at any point, though it remains a start-up decision by
    intent — flipping it mid-generation leaves some files parsed with the
    typename supplement and some without.
  - `SubscriptionManager.transactionListener` needed the opt-out because
    its two accesses straddle the type's isolation: `init` writes on the
    main actor, `nonisolated deinit` reads to cancel. Keeping the deinit
    nonisolated preserves immediate deallocation instead of hopping to
    the actor, so the property carries its own synchronisation.

- **`@unchecked Sendable` audited: 8 of 14 removed.** Six generators
  (Activity, Component, DependencyGraph, ER, Sequence, StateMachine) have
  no stored properties, so the attribute suppressed a check with nothing
  to check; they now declare plain `Sendable`. `ClassDiagramGenerator`
  joined them once `FileCollector`, also stateless, declared the
  conformance it always satisfied. The six that remain are load-bearing
  and now carry the reason in a comment: `DiagramScript` holds a mutable
  `DiagramContext` class, `SyntaxStructure` already documented itself,
  and four test spies never cross an isolation boundary.

### Fixed — Bridge

- **A data race in `SPMPackageReader.describe(at:)`'s timeout flag.** The
  private `UncheckedBox` it used documented a `DispatchGroup` as ordering
  its accesses. That holds for the stderr drain and not for `timedOut`:
  the watchdog is an `asyncAfter` work item outside the group, firing at
  an arbitrary moment, and `watchdog.cancel()` in the `defer` runs after
  the read and cannot stop a block already executing. Both call sites are
  now a `Mutex` and the box is gone.

- **`component --package` no longer hangs on SwiftPM's build lock.**
  SwiftPM locks its scratch directory for the length of a command, and
  `SPMPackageReader.describe(at:)` ran `swift package describe` against
  the package's own `.build`. Describing a package that another SwiftPM
  process was already using — most obviously the one you are building or
  testing from — blocked on that lock forever, with no output and no
  error. The command now runs with `--scratch-path` pointing at a private
  temporary directory, so there is no shared lock to queue behind;
  dependency resolution still reads the shared package cache, so this
  costs no re-cloning (0.32s either way). Chosen over detecting the
  condition, since a pre-flight lock check would race and sniffing
  SwiftPM's "waiting for lock" message would break on any rewording. A
  300s watchdog now also kills the subprocess and throws
  `ReadError.timedOut`, bounding the deadlocks not yet found — set far
  above any honest run, because a first-time resolve over a slow network
  is legitimately slow.
- **`SPMPackageReader.describe(at:)` no longer deadlocks on large
  `swift package describe` output.** It called `waitUntilExit()` before
  draining the child's pipes. Once output outgrows the pipe buffer
  (~64KB on Darwin) the child blocks writing into a full pipe nobody is
  reading while the parent blocks waiting for a child that cannot
  proceed — the CLI hangs with no output and no error. SwiftUMLBridge's
  own describe output is 11.9KB so it never tripped, but a package with a
  few thousand sources does. Both pipes are now drained *concurrently*
  before the wait: sequential draining would fix only the first stream,
  since filling either pipe stalls the child. Regression test generates a
  2,000-source package (~120KB of output) — it hung for over ten minutes
  before the fix and returns in about a second after it.

### Fixed — Studio (test infrastructure)

- **ViewInspector quarantine lifted.** Six tests were disabled because
  ViewInspector 0.10.3 could not read accessibility modifiers on
  macOS 27 — the OS replaced `AccessibilityProperties`' named members
  with a generic storage array. The same upstream PR
  (nalexn/ViewInspector#421, merged 2026-08-09) also fixes a more
  dangerous break: `GeometryProxy` has no public initializer, so
  ViewInspector fabricated one by `unsafeBitCast`-ing a fixed-size zeroed
  struct handling only 48 and 52 bytes; macOS 27 reports 76, and the
  unguarded fallback *trapped* rather than failed, killing the test
  process and reporting unrelated suites as failed.
  `NativeSequenceDiagramView`, `DiagramCanvasContainer`, and
  `NativeDiagramView` all render a `GeometryReader`, so any traversal was
  one scheduling change from crashlooping the target. Pinned to the exact
  upstream revision rather than the branch, since there is still no
  `0.10.4` tag — swap for a version requirement once it lands. The old
  compatibility test asserting `MemoryLayout<GeometryProxy>.size` was 48
  or 52 is replaced by two behavioural preflights, the size-agnostic fix
  having made the assertion both obsolete and wrong.

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
