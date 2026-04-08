# SwiftPlantUML Studio — User Guide

SwiftPlantUML Studio is a macOS GUI for [SwiftUMLBridge](../SwiftUMLBridge/), the Swift-native diagram generator. It lets you point at Swift source files or folders, explore your codebase visually, generate diagrams, and track how your architecture evolves over time — all without touching the terminal.

For CLI usage, see the [SwiftUMLBridge User Guide](user-guide.md).

---

## Table of Contents

1. [Requirements](#requirements)
2. [App Modes](#app-modes)
3. [Explorer Mode](#explorer-mode)
   - [Explorer Window Layout](#explorer-window-layout)
   - [Project Dashboard](#project-dashboard)
   - [Insights](#insights)
   - [Suggested Diagrams](#suggested-diagrams)
   - [Explorer Diagram Preview](#explorer-diagram-preview)
4. [Developer Mode](#developer-mode)
   - [Developer Window Layout](#developer-window-layout)
   - [File Browser](#file-browser)
   - [Source Editor](#source-editor)
   - [Detail Pane Tabs](#detail-pane-tabs)
5. [Opening Swift Source Files](#opening-swift-source-files)
6. [Choosing a Diagram Mode](#choosing-a-diagram-mode)
7. [Choosing a Diagram Format](#choosing-a-diagram-format)
8. [Generating a Class Diagram](#generating-a-class-diagram)
9. [Generating a Sequence Diagram](#generating-a-sequence-diagram)
   - [Entry Point Syntax](#entry-point-syntax)
   - [Traversal Depth](#traversal-depth)
10. [Generating a Dependency Graph](#generating-a-dependency-graph)
    - [Types Mode](#types-mode)
    - [Modules Mode](#modules-mode)
    - [Cycle Annotation](#cycle-annotation)
11. [Reading the Results](#reading-the-results)
12. [Copying the Diagram Markup](#copying-the-diagram-markup)
13. [Diagram History](#diagram-history)
14. [Pro Features](#pro-features)
    - [What Pro Unlocks](#what-pro-unlocks)
    - [Paywall](#paywall)
    - [Architecture Change Tracking](#architecture-change-tracking)
    - [Review Reminders](#review-reminders)
15. [Known Limitations](#known-limitations)

---

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 26.4 |
| Xcode (to build the app) | 16.0 |

---

## App Modes

The app has two modes, toggled via a picker in the toolbar:

| Mode | Audience | Description |
|---|---|---|
| **Explorer** | Everyone (default) | Simplified, insight-driven interface. Focus on understanding your codebase visually without needing to know UML terminology. |
| **Developer** | Power users | Full-featured interface with file browsing, diagram markup editing, and fine-grained control over diagram type, format, and options. |

The mode selection is persisted between launches. Explorer is the default for new users.

---

## Explorer Mode

Explorer Mode presents your codebase through plain-language insights and one-click suggested diagrams. It is designed for users who want to understand their code structure without configuring diagram options manually.

### Explorer Window Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│  Toolbar                                                             │
│  [Open…] [path label]                    [Explorer | Developer] [Save]│
├─────────────────────┬────────────────────────────────────────────────┤
│                     │                                                │
│  Left sidebar       │  Detail pane                                   │
│  ┌───────────────┐  │  ┌──────────────────────────────────────────┐  │
│  │ Insights      │  │  │  Project Dashboard (when no diagram)    │  │
│  │ ─────────     │  │  │  — or —                                 │  │
│  │ Suggestions   │  │  │  Rendered diagram preview                │  │
│  │ ─────────     │  │  └──────────────────────────────────────────┘  │
│  │ Snapshots     │  │                                                │
│  │ ─────────     │  │                                                │
│  │ History       │  │                                                │
│  └───────────────┘  │                                                │
│                     │                                                │
└─────────────────────┴────────────────────────────────────────────────┘
```

**Left sidebar** — Displays insights, suggested diagrams, architecture snapshots (Pro), and saved diagram history.

**Detail pane** — Shows the Project Dashboard when no diagram is loaded, or the rendered diagram preview when a suggestion or history item is selected.

### Project Dashboard

When you open a folder in Explorer Mode, the dashboard appears immediately — before any diagram is generated. It provides an at-a-glance summary of your project:

- **Stats cards** — Total files, types, relationships, and methods.
- **Type breakdown** — Visual grid showing how many structs, classes, enums, protocols, and actors your project contains.
- **Insights** — Plain-language observations about your codebase (see [Insights](#insights)).
- **Suggested diagrams** — One-click actions to generate specific diagrams (see [Suggested Diagrams](#suggested-diagrams)).

### Insights

The Insight Engine analyzes your project and generates plain-language observations. Each insight has a severity level:

| Severity | Icon | Example |
|---|---|---|
| **Info** | Blue circle | "Your project uses 15 protocols — see how types conform to them" |
| **Noteworthy** | Yellow triangle | "PaymentProcessor is used by 12 other types — it's a critical dependency" |
| **Warning** | Red exclamation | "Found a dependency cycle between ModuleA and ModuleB" |

Insights are generated from the project analysis and update whenever you open a new folder.

### Suggested Diagrams

The Suggestion Engine generates actionable one-click diagram options based on your project's structure:

| Suggestion | Description | Pro Required? |
|---|---|---|
| See how your types are connected | Class diagram of all types | No |
| Explore this file's structure | Class diagram of a single file | No |
| Trace what happens when X runs | Sequence diagram from a detected entry point | Yes |
| See which parts depend on each other | Dependency graph | Yes |
| Deep dive into [type name] | Focused class diagram centered on a high-connectivity type | No |

Pro-only suggestions display a lock icon. Tapping them opens the paywall.

### Explorer Diagram Preview

When you select a suggestion or history item, the detail pane switches from the dashboard to a rendered diagram preview. The preview uses the same web view as Developer Mode — PlantUML diagrams are fetched as SVG from planttext.com; Mermaid diagrams are rendered locally via Mermaid.js.

---

## Developer Mode

Developer Mode exposes the full power of the diagram generator with a three-pane layout, file browsing, diagram markup editing, and manual control over all diagram options.

### Developer Window Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│  Toolbar                                                             │
│  [Open…] [path label] [Class|Sequence|Deps] [PlantUML|Mermaid]       │
│  [sequence/deps controls]           [Explorer | Developer] [Save]    │
├──────────────┬───────────────┬───────────────────────────────────────┤
│              │               │                                       │
│  Left sidebar│  Middle pane  │  Right pane                           │
│  ┌────────┐  │  Source code  │  [Dashboard | Preview | Markup]       │
│  │ Files  │  │  (read-only)  │                                       │
│  │ ─────  │  │               │  Dashboard: project stats             │
│  │ History│  │               │  Preview: rendered diagram             │
│  └────────┘  │               │  Markup: raw PlantUML/Mermaid text    │
│              │               │                                       │
└──────────────┴───────────────┴───────────────────────────────────────┘
```

**Left sidebar** — File browser (directory tree of selected paths) and saved diagram history.

**Middle pane** — Read-only source code view for the currently selected file.

**Right pane** — Tabbed detail pane with Dashboard, Preview, and Markup tabs. Defaults to the Preview tab.

### File Browser

The left sidebar displays the selected paths as a hierarchical file tree. Directories expand to show their contents. Clicking a `.swift` file loads its source code in the middle pane.

### Source Editor

The middle pane displays the Swift source code of the file selected in the file browser. It is read-only — you cannot edit source code in the app. This pane is useful for reviewing the code alongside its generated diagram.

### Detail Pane Tabs

The right pane has three tabs:

| Tab | Contents |
|---|---|
| **Dashboard** | Same project dashboard as Explorer Mode — stats, type breakdown, insights, suggestions. |
| **Preview** | Rendered diagram (web view). Shows a progress spinner during generation and an empty-state message when no diagram has been generated. |
| **Markup** | Raw PlantUML or Mermaid markup text (read-only). Useful for copying into other tools or version control. |

---

## Opening Swift Source Files

Click **Open...** in the toolbar. A standard Open panel appears with these options:

- **Individual `.swift` files** — select one or more files directly.
- **Folders** — select a directory; the generator searches it recursively for `.swift` files.
- **Mixed selection** — select a combination of files and folders.

After you confirm, the toolbar path label updates to show the selection. If you selected a single item, its filename is shown. If you selected multiple items, the first filename is shown followed by `+ N more`.

To switch to a different set of files, click **Open...** again. The previous selection is replaced.

When you open files, the app automatically runs a project analysis to populate the dashboard, insights, and suggestions.

---

## Choosing a Diagram Mode

In Developer Mode, the **segmented control** in the toolbar selects the diagram type:

| Mode | What it generates | Pro Required? |
|---|---|---|
| **Class Diagram** | Structural overview of types, properties, methods, and relationships | No |
| **Sequence Diagram** | Static call-graph trace from a named entry-point method | Yes |
| **Dependency Graph** | Type-to-type or module-to-module dependency graph across the selected source | Yes |

Switching modes clears the current diagram and resets the preview pane. Sequence Diagram mode reveals an entry-point text field and a depth stepper; Dependency Graph mode reveals a **Types / Modules** picker.

In Explorer Mode, the diagram mode is determined by which suggestion you tap — you do not choose it manually.

---

## Choosing a Diagram Format

In Developer Mode, the **PlantUML / Mermaid** segmented control selects the output language:

| Format | Preview rendering | Markup extension |
|---|---|---|
| **PlantUML** | SVG fetched from planttext.com (requires internet) | `.puml` |
| **Mermaid** | Rendered locally via Mermaid.js CDN (requires internet for CDN) | `.mmd` |

You can switch formats after generation — click **Generate** again to re-render in the new format.

In Explorer Mode, the format is not exposed — the app defaults to PlantUML for the visual preview.

---

## Generating a Class Diagram

1. Click **Open...** and select Swift files or a folder.
2. In Developer Mode, make sure **Class Diagram** is selected in the mode picker. In Explorer Mode, tap a class diagram suggestion.
3. In Developer Mode, choose **PlantUML** or **Mermaid** in the format picker.
4. In Developer Mode, click **Generate**.

The **Generate** button is disabled until at least one source path is selected. While the generator runs, a progress spinner fills the preview pane. Results appear as soon as generation completes.

---

## Generating a Sequence Diagram

Sequence diagrams require a Pro subscription.

1. Click **Open...** and select the Swift files or folder that contain the entry-point type.
2. In Developer Mode, select **Sequence Diagram** in the mode picker. Two additional controls appear in the toolbar:
   - A **text field** for the entry point.
   - A **depth stepper**.
3. Choose **PlantUML** or **Mermaid**.
4. Type the entry point in the text field (see [Entry Point Syntax](#entry-point-syntax) below).
5. Adjust the depth if needed.
6. Click **Generate**.

In Explorer Mode, sequence diagram suggestions are pre-populated with detected entry points from your code — just tap the suggestion.

If the entry-point field is empty when **Sequence Diagram** mode is active, the preview pane shows a reminder: *"Enter an entry point (e.g. MyType.myMethod), then click Generate."*

### Entry Point Syntax

The entry point must be in the form `TypeName.methodName`:

| Example | Meaning |
|---|---|
| `MyService.run` | Method `run` on `MyService` |
| `ClassDiagramGenerator.generateScript` | Method `generateScript` on `ClassDiagramGenerator` |
| `AuthService.login` | Method `login` on `AuthService` |

The names are **case-sensitive** and must exactly match the Swift source code. If no function matches, the diagram will be empty.

The entry point must be `TypeName.methodName` — exactly one dot. A bare function name or a deeply qualified path (e.g., `Module.Type.method`) is not accepted.

### Traversal Depth

The **Depth stepper** controls how many hops to follow from the entry point. The default is **3**; the range is 1–10.

- **Depth 1** — only the direct calls made by the entry method.
- **Depth 3** — entry method + up to 3 levels of callees.
- **Depth 10** — as deep as the call graph goes (each `Type.method` pair is visited at most once, so cycles are safe).

Increase depth if you want to see deeper call chains; decrease it for a focused, high-level overview.

---

## Generating a Dependency Graph

Dependency graphs require a Pro subscription.

1. Click **Open...** and select the Swift files or folder you want to analyze.
2. In Developer Mode, select **Dependency Graph** in the mode picker. A **Types / Modules** segmented picker appears in the toolbar.
3. Choose **Types** or **Modules** (see below).
4. Choose **PlantUML** or **Mermaid** in the format picker.
5. Click **Generate**.

In Explorer Mode, tap a dependency graph suggestion in the sidebar.

No entry point is required. The generator scans all selected source files and builds the full dependency graph in a single pass.

### Types Mode

Types mode builds one directed edge for every inheritance and protocol-conformance relationship found in the selected source. Each node represents a named Swift type (class, struct, enum, protocol, or actor). Edge labels indicate the relationship kind:

| Edge label | Source relationship |
|---|---|
| `inherits` | Class inheritance (`class Dog: Animal`) |
| `conforms` | Protocol conformance (`struct User: Codable`) |

Use Types mode to get a structural overview of how your types depend on one another — equivalent to a flattened class diagram focused on dependencies only, with no member detail.

### Modules Mode

Modules mode builds one directed edge for every `import` statement found in the selected source files. Each node represents a **module**, where the module name is derived from the parent directory of the file containing the import. This gives a directory-level view of inter-module dependencies without requiring a full build.

| Edge label | Source relationship |
|---|---|
| `imports` | `import ModuleName` statement in source |

Use Modules mode to detect unintended cross-module coupling or to understand the layering of your codebase at a high level.

### Cycle Annotation

When the generator detects a dependency cycle, the nodes involved are highlighted:

- **Mermaid format** — cyclic nodes receive a red fill (`fill:#ffcccc, stroke:#cc0000`) applied via a `style` directive.
- **PlantUML format** — a `note as CyclicDependencies` block is appended at the bottom of the diagram listing the names of the cyclic nodes.

---

## Reading the Results

### Class Diagram

Each Swift type appears as a node. Arrows indicate relationships:

| Arrow | Meaning |
|---|---|
| Solid `<\|--` | Inheritance (`class Dog: Animal`) |
| Dashed `<\|..` | Protocol conformance (`struct User: Codable`) |
| Dotted `<..` | Extension dependency |
| `+--` (PlantUML only) | Nested type |

Stereotypes identify the Swift construct: `<<class>>`, `<<struct>>`, `<<protocol>>`, `<<enum>>`, `<<extension>>`.

### Sequence Diagram

Participants are the types involved in the call chain. Each arrow is a call:

| Arrow | Meaning |
|---|---|
| `->` (PlantUML) / `->>` (Mermaid) | Synchronous call |
| `->>` (PlantUML) / `-->>` (Mermaid) | `await`-prefixed (async) call |

Calls that cannot be resolved statically (e.g., `dependency.doWork()` where `dependency` is a variable) appear as **notes** in the diagram rather than arrows.

### Dependency Graph

Each node is a type name (Types mode) or a directory/module name (Modules mode). Edges are directed from the dependent toward the dependency.

| Edge label | Meaning |
|---|---|
| `inherits` | Class inherits from another class (Types mode) |
| `conforms` | Type conforms to a protocol (Types mode) |
| `imports` | File in source module imports the target module (Modules mode) |

Cyclic nodes — those involved in a dependency cycle — are annotated automatically:

| Format | Annotation |
|---|---|
| **Mermaid** | Node background filled red (`fill:#ffcccc, stroke:#cc0000`) |
| **PlantUML** | `note as CyclicDependencies` block listing affected node names |

---

## Copying the Diagram Markup

In Developer Mode, switch to the **Markup** tab in the right pane to see the raw PlantUML or Mermaid markup. To copy it:

1. Click inside the Markup tab.
2. Press **Cmd-A** to select all, then **Cmd-C** to copy.

You can paste the markup into:
- [planttext.com](https://www.planttext.com) or the PlantUML CLI for PlantUML diagrams.
- [mermaid.live](https://mermaid.live) or any Mermaid-compatible tool for Mermaid diagrams.
- A Markdown file — Mermaid blocks render natively on GitHub and in many editors.

---

## Diagram History

Every diagram you generate can be saved to history by clicking the **Save** button in the toolbar. Saved diagrams appear in the history section of the sidebar (in both Explorer and Developer modes).

Each history entry records:
- The diagram name (auto-generated from the selected file/folder names)
- The diagram mode (class, sequence, or dependency)
- The timestamp

Click a history entry to reload the diagram. You can also delete history entries by swiping or using the context menu.

History is stored in Core Data and persists between app launches.

---

## Pro Features

SwiftPlantUML Studio uses a freemium model. The free tier provides the full Explorer Mode experience with class diagram generation. Pro unlocks advanced capabilities.

### What Pro Unlocks

| Feature | Free | Pro |
|---|---|---|
| Explorer Mode dashboard, insights, suggestions | Yes | Yes |
| Class diagrams (view only) | Yes | Yes |
| Sequence diagrams | — | Yes |
| Dependency graphs | — | Yes |
| PlantUML/Mermaid format selection | — | Yes |
| Diagram markup export (copy/save) | — | Yes |
| Architecture change tracking (snapshots) | — | Yes |
| Review reminders | — | Yes |

### Paywall

When you attempt to use a Pro-only feature, a paywall sheet appears. It lists what Pro unlocks and offers monthly and annual subscription options, plus a **Restore Purchases** link for existing subscribers.

The paywall is informative, not aggressive — it appears only when you specifically try to access a gated feature.

### Architecture Change Tracking

Pro subscribers can save architecture snapshots that capture the state of your project at a point in time:

- **Type count**, **relationship count**, **module count**, **file count**
- **Type breakdown** (structs, classes, enums, protocols, actors)
- **Top connected types** (most-referenced types)

When you save a snapshot, the app compares it against the previous snapshot for the same set of files and shows an **Architecture Diff**:

- Delta values for types, relationships, modules, and files (color-coded: green for increases, red for decreases)
- Type breakdown deltas (e.g., "+3 structs, -1 class")
- Complexity changes for individual types

Snapshots appear in the sidebar under the **Snapshots** section in Explorer Mode.

### Review Reminders

Pro subscribers can enable optional reminders to review their architecture on a regular cadence. When enabled, the app sends a local notification every 14 days prompting you to check how your codebase has evolved.

Toggle this in the Snapshots section of the Explorer sidebar.

---

## Known Limitations

**Internet connection required for PlantUML rendering.** PlantUML diagrams are rendered server-side by planttext.com and require an active internet connection. Mermaid diagrams are rendered locally using a bundled copy of Mermaid.js and work fully offline. The raw markup (in Developer Mode's Markup tab) is always available offline regardless of format.

**Actors appear as classes.** SourceKit 6.3 on macOS 26 reports `actor` declarations with kind `source.lang.swift.decl.class`. Actor types are included in class diagrams but show the `<<class>>` stereotype.

**`async` and `throws` not shown in class diagrams.** Class diagram member labels omit `async`/`throws` annotations. Sequence diagrams correctly distinguish `await`-wrapped calls with a distinct arrow.

**Variable-receiver calls are unresolved in sequence diagrams.** `dep.doWork()` where `dep` is a local variable or parameter cannot be resolved statically. Such calls appear as notes in the diagram and are not expanded further.

**No configuration file support in the GUI.** The GUI uses built-in defaults. Project-level `.swiftumlbridge.yml` settings (custom access levels, themes, extension display, etc.) are not applied. Use the CLI for configuration-file-driven generation.
