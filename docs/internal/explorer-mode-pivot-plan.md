# Explorer Mode Pivot Plan

**Last updated:** 2026-05-09 (post-implementation refresh)

## Status at a glance

| Phase | Status | Notes |
|---|---|---|
| 1. StoreKit + Feature Gating | **Shipped** | `SubscriptionManager` (StoreKit 2), `FeatureGate`, `PaywallView`, `Configuration.storekit` all in place |
| 2. Project Dashboard + Insights | **Shipped** | `ProjectAnalyzer`, `ProjectSummary`, `InsightEngine`, `SuggestionEngine`, `SuggestionDispatcher`, `ProjectDashboardView` all in place |
| 3. Explorer Mode UI | **Shipped** | `AppMode`, `ExplorerToolbar`, `ExplorerSidebar`, `ExplorerDetailView` are live. §3.4 closed 2026-08-07: Explorer never names a `DiagramMode`, so suggestion-driven navigation meets the plain-language goal without a translation layer. The one jargon leak, `PaywallView`, is fixed. |
| 4. Architecture Change Tracking (Pro) | **Shipped** | `ProjectSnapshot`, `SnapshotManager`, `ArchitectureDiffView`, `ReviewReminderManager` |
| 5. App Store Prep | **Pending** | No App Store submission yet — bundled into v1.0 release prep tasks |
| 6. Distribution | **Pending** | Homebrew formula still in v1.0 prep; landing page / marketing not started |

The phases below preserve the original plan as design context. Material drift from what shipped is called out inline.

## Overview

Transform SwiftUMLStudio from a developer-only UML tool into a freemium codebase explorer that serves both developers and vibe-coders. The pivot adds an "Explorer Mode" as the default free experience, with the existing developer features becoming the paid "Pro" tier.

> **Premise drift:** The original plan said "this plan assumes v1.0 ships first with the current developer feature set; Explorer Mode is the v2.0 headline feature." That inverted in practice — Phases 1–4 landed *before* the v1.0 release (which is still in prep). Explorer Mode is now part of the v1.0 launch, not a v2.0 follow-up.

---

## Phase 1: Foundation — StoreKit & Feature Gating — **SHIPPED**

**Goal:** Establish the subscription infrastructure before building new UI.

### 1.1 StoreKit 2 Integration
- Add StoreKit 2 for subscription management (no server needed for App Store)
- Define product IDs for monthly and annual Pro plans
- Create a `SubscriptionManager` (@Observable) that tracks entitlement state
- Store entitlement in `@AppStorage` with StoreKit transaction listener for real-time updates

### 1.2 Feature Gate Layer
- Create a `FeatureGate` utility that checks subscription status
- Gate the following behind Pro:
  - Sequence diagrams (mode picker option)
  - Dependency graphs (mode picker option)
  - PlantUML/Mermaid export (copy/save buttons)
  - Multiple projects (second+ project opens)
  - YAML configuration
- Free tier gets: Explorer Mode dashboard, basic class diagrams (view only), 1 project

### 1.3 Paywall View
- Simple SwiftUI sheet triggered when a gated feature is tapped
- Show what Pro unlocks, price, and subscription buttons
- Keep it lightweight — not aggressive, just informative

### Architecture Impact
- `DiagramViewModel` gains a dependency on `SubscriptionManager`
- Toolbar controls conditionally disable/show upgrade badges
- No changes to SwiftUMLBridgeFramework — gating is purely at the UI layer

---

## Phase 2: Project Dashboard — The "Wow" Screen — **SHIPPED**

**Goal:** When a user drops a folder, show an instant visual summary before any diagram is generated.

### 2.1 Code Analysis Engine
Create a lightweight analysis pass (separate from full diagram generation) that quickly scans source files and produces a `ProjectSummary`:

```
ProjectSummary
├── totalFiles: Int
├── totalTypes: Int
├── typeBreakdown: [TypeKind: Int]  (classes, structs, enums, protocols, actors)
├── totalRelationships: Int
├── moduleCount: Int
├── topConnectedTypes: [(name: String, connectionCount: Int)]
├── insights: [Insight]  (plain-language observations)
└── suggestions: [DiagramSuggestion]  (actionable one-click options)
```

This reuses the existing `SyntaxStructureBuilder` (SwiftSyntax walker) but skips the emitter layer — just counts and categorizes. Should be fast even for large projects.

### 2.2 Insight Engine
Generate plain-language insights from the `ProjectSummary`:

| Condition | Insight |
|---|---|
| Type with 10+ dependents | "PaymentProcessor is used by 12 other types — it's a critical dependency" |
| Deep inheritance (3+ levels) | "ViewController has a 4-level inheritance chain — this can make changes risky" |
| Many protocols | "Your project uses 15 protocols — see how types conform to them" |
| Isolated types (no relationships) | "5 types have no connections — they may be unused or self-contained utilities" |
| Large file (10+ types) | "Models.swift defines 12 types — consider splitting it up" |
| Cycle detected | "Found a dependency cycle between ModuleA and ModuleB" |

### 2.3 Suggestion Engine
Each suggestion maps to a one-click diagram generation:

| Suggestion | Label (Explorer Mode) | Action |
|---|---|---|
| Class diagram of all types | "See how your types are connected" | Generate class diagram |
| Class diagram of single file | "Explore this file's structure" | Generate filtered class diagram |
| Sequence diagram (if methods found) | "Trace what happens when X runs" | Generate sequence diagram (Pro) |
| Dependency graph | "See which parts depend on each other" | Generate dependency graph (Pro) |
| Focus on high-connectivity type | "Deep dive into PaymentProcessor" | Filtered class diagram centered on type |

Pro-only suggestions show a lock icon and trigger the paywall on tap.

### 2.4 Dashboard View
New `ProjectDashboardView` replaces the current "Select Swift source files" placeholder. Shows:

- **Header:** Project name, file/type counts, at-a-glance stats
- **Insights cards:** Scrollable list of plain-language observations
- **Suggested diagrams:** Grid of one-click actions with preview thumbnails
- **Type breakdown:** Visual bar/pie showing composition (classes vs structs vs protocols etc.)

The dashboard appears immediately after folder selection, before any diagram is generated. It's the first thing a vibe-coder sees.

### Architecture Impact
- New files: `ProjectSummary.swift`, `InsightEngine.swift`, `SuggestionEngine.swift`, `ProjectDashboardView.swift`
- `DiagramViewModel` gets a `projectSummary: ProjectSummary?` property
- `ContentView` shows dashboard when no diagram is active but paths are selected
- Analysis engine lives in SwiftUMLBridgeFramework (reuses parser, no emitter dependency)

---

## Phase 3: Explorer Mode UI — **SHIPPED (mostly; §3.4 still open)**

**Goal:** Plain-language interface that makes diagrams approachable for non-developers.

### 3.1 Mode Toggle
- Add a persistent toggle: Explorer / Developer (stored in `@AppStorage`)
- Explorer is the default for new users
- Developer mode restores the current UI exactly as-is
- Toggle lives in app settings or a prominent switcher in the toolbar

### 3.2 Explorer Mode Toolbar
Replace the current developer toolbar with simplified controls:

| Current (Developer) | Explorer Equivalent |
|---|---|
| Mode: Class / Sequence / Dependency | Hidden — driven by suggestion clicks |
| Format: PlantUML / Mermaid | Hidden — Explorer always renders visual preview |
| Entry point text field | Hidden — populated automatically from suggestions |
| Depth stepper | Hidden |
| Save button | "Save to History" with bookmark icon |

### 3.3 Explorer Mode Navigation
- **Left sidebar:** Project dashboard (insights + suggestions) replaces file browser
- **Center pane:** Interactive diagram (same WebView, but no markup tab)
- **Right sidebar (optional):** Selected type details — "This class has 3 properties and 5 methods, inherits from BaseController"

### 3.4 Plain-Language Labels — **MET BY OTHER MEANS (2026-08-07)**

**Do not implement the `explorerLabel` property this section used to prescribe — it would be dead code.** The earlier note said to add `explorerLabel: String` to `DiagramMode` and have the Explorer toolbar / sidebar read it. That has no consumer: Explorer mode never displays a `DiagramMode` name anywhere. `ExplorerSidebar` and `ExplorerToolbar` contain no `DiagramMode` reference at all, `ExplorerDetailView` shows only `DiagramPreviewView` or `ProjectDashboardView`, and the sole render site — `WorkspaceSidebar.row(for:)` — is reached from `developerLayout` only.

The goal behind the section is already met, by a better route than renaming. Per §3.2 the mode picker is hidden in Explorer and navigation is driven by suggestion clicks, and `SuggestionEngine` titles are already plain language describing *what you will see* rather than naming the artefact:

| Suggestion title | Underlying mode |
|---|---|
| "See how your types are connected" | `.classDiagram` |
| "Trace `Type.method`" | `.sequenceDiagram` |
| "See which types depend on each other" | `.dependencyGraph` (types) |
| "See module dependencies" | `.dependencyGraph` (modules) |

That is strictly better than a "Type Map" / "Execution Flow" picker: the user never meets the artefact name at all, so there is nothing to translate.

**What actually remained, and was fixed 2026-08-07:** `PaywallView` — the one Explorer surface that names Pro features — hardcoded "Sequence Diagrams", "Dependency Graphs", "PlantUML & Mermaid Export" and "Format Selection". Those are now "Execution Flows", "Dependency Maps", "Share Your Diagrams" and "Choose How Diagrams Look", honouring this section's rule that PlantUML / Mermaid are never surfaced to an Explorer user. A regression test (`PaywallFeatureTests.titlesAvoidJargon`) fails if a jargon term reappears in a paywall title.

`DiagramMode.rawValue` is deliberately unchanged. It is both the Developer-mode label and the persisted `DiagramEntity.mode` key, so renaming it would require a snapshot migration for no user-visible gain.

The original translation table is preserved below as design context. Only the last row (PlantUML / Mermaid never shown) turned out to describe live behaviour; the diagram-name rows were superseded by suggestion-driven navigation.

| Developer Term | Explorer Term |
|---|---|
| Class Diagram | Type Map |
| Sequence Diagram | Execution Flow |
| Dependency Graph | Dependency Map |
| Stereotype | Tag |
| Inheritance | "extends" or "is based on" |
| Protocol Conformance | "implements" or "follows the rules of" |
| PlantUML / Mermaid | Not shown — just "Diagram" |

### Architecture Impact
- New files: `ExplorerToolbar.swift`, `ExplorerSidebar.swift`, `TypeDetailView.swift`
- `ContentView` switches layout based on mode toggle
- All existing developer views remain untouched

---

## Phase 4: Architecture Change Tracking (Pro) — **SHIPPED**

**Goal:** Give subscribers a reason to come back regularly — track how their codebase evolves.

### 4.1 Snapshot System
- When a Pro user generates a diagram, save a `ProjectSnapshot` alongside the diagram:
  - Type count, relationship count, module count
  - Per-type connection counts
  - Timestamp
- Store snapshots in **SwiftData** (a new `ProjectSnapshot` model alongside `DiagramEntity`). *(Plan originally said Core Data; the project migrated the persistence layer to SwiftData in commit `e192965`, so the actual implementation is SwiftData-backed.)*

### 4.2 Diff View
- Compare current project state to a previous snapshot
- Show: "Since last week: +3 types, +7 relationships, PaymentModule complexity increased"
- Visual diff on the dashboard — green/red indicators next to changed areas

### 4.3 Notifications (Stretch)
- Optional reminders: "It's been 2 weeks since you last reviewed your architecture"
- Useful for teams doing regular architecture reviews

### Architecture Impact
- New SwiftData model: `ProjectSnapshot` *(plan originally said Core Data — see §4.1 note)*
- New files: `SnapshotManager.swift`, `ArchitectureDiffView.swift`
- Dashboard gains a "Changes since..." section for Pro users

---

## Phase 5: App Store Preparation — **PENDING**

### 5.1 App Store Assets
- Screenshots showing both Explorer and Developer modes
- App preview video: drop a folder → see dashboard → click suggestion → diagram appears
- Description emphasizing "understand your codebase visually" (not "generate UML")

### 5.2 App Store Review Considerations
- Subscription justification: ongoing Swift language support, architecture tracking
- Free tier must be genuinely useful (not a crippled demo)
- Privacy: app never uploads source code, all processing is local

### 5.3 Onboarding Flow
- First launch: brief walkthrough (3 screens max)
  1. "Drop your project folder to get started"
  2. "See insights and suggested diagrams"
  3. "Upgrade to Pro for advanced features"
- Skip option prominent — don't block usage

---

## Phase 6: Distribution & Growth — **PENDING**

### 6.1 Channels
- **Mac App Store:** Primary for vibe-coder discovery
- **Homebrew:** CLI remains free and open source, README links to Studio app
- **GitHub:** Open source framework, proprietary Studio app
- **Social:** Short demo videos showing the "drop folder → instant insight" flow

### 6.2 Landing Page
- Simple page: hero video, feature comparison table, download button
- Email signup for launch notification
- Consider launching this before building Explorer Mode to validate demand

### 6.3 Content Marketing
- Blog posts: "What does your AI-generated code actually look like?"
- Target vibe-coder communities: Reddit r/ChatGPTCoding, Twitter/X AI dev circles
- Show before/after: "I asked AI to build a to-do app. Here's the architecture it created."

---

## Implementation Sequence

| Phase | Scope | Status | Notes |
|---|---|---|---|
| Phase 1 | StoreKit + feature gating | **Shipped** | Landed before v1.0 release prep, not after |
| Phase 2 | Project dashboard + insights | **Shipped** | |
| Phase 3 | Explorer Mode UI | **Shipped** | §3.4 closed 2026-08-07 — met by suggestion-driven navigation, not a label layer |
| Phase 4 | Architecture change tracking | **Shipped** | SwiftData-backed (plan said Core Data) |
| Phase 5 | App Store prep | Pending | Bundled into v1.0 release prep |
| Phase 6 | Distribution | Pending | Homebrew formula still in v1.0 prep |

Original plan called Phases 1–3 the freemium MVP and Phases 4–6 post-launch. In practice Phases 1–4 all shipped together as part of the run-up to v1.0; the remaining work is purely the App Store + distribution side of §5–6.

---

## Key Risks

| Risk | Mitigation |
|---|---|
| Vibe-coders don't pay for dev tools | Free tier is genuinely useful; low price point; validate with landing page first |
| Apple rejects subscription model | Ensure free tier is substantial; document ongoing value (Swift updates, tracking) |
| Dashboard is slow on large projects | Analysis engine skips emitter layer; cache results; show progressive loading |
| Developer users feel ignored | Developer Mode is unchanged; Pro features add to their workflow too |
| Scope creep delays launch | Ship Phase 1-3 as MVP; Phase 4+ is post-launch iteration |

---

## Success Metrics

- **Free tier:** 500+ downloads in first 60 days
- **Conversion:** 5-10% free-to-Pro conversion rate
- **Retention:** <10% monthly churn on Pro subscribers
- **Engagement:** Average user opens app 2+ times per week
- **App Store:** 4.5+ star rating
