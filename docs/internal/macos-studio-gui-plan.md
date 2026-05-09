# macOS Studio GUI

## Current State (2026-05)

The original "Initial Implementation" plan below described a 4-file MVP (file picker + PlantUML WebView). That MVP shipped in 2026-02 and the Studio app has since grown well beyond it. As of 2026-05 it includes:

**Modes** (`AppMode.swift`)
- Document mode — the original single-file → single-diagram MVP flow
- Explorer mode — file-tree-driven navigation (`ExplorerSidebar`, `ExplorerDetailView`, `ExplorerToolbar`)
- Project mode — workspace with snapshots, dashboard, and architecture diff

**Diagram rendering**
- Native SwiftUI / Core Graphics renderers replaced the WebView for class / sequence / activity diagrams (`NativeDiagramView`, `NativeSequenceDiagramView`, `NativeActivityDiagramView`)
- WebView retained as a fallback for Mermaid (`MermaidHTMLBuilder`) and Nomnoml (`NomnomlHTMLBuilder`)
- Six diagram types supported: class, sequence, activity, state, ER, dependency

**Persistence (SwiftData)**
- `PersistenceController`, `DiagramEntity`, `ProjectSnapshot`, `SnapshotManager`, `HistorySidebar`, `SnapshotRowView`
- Snapshots are diffable via `ArchitectureDiffView`

**Subscription / paywall (StoreKit 2)**
- `SubscriptionManager`, `SubscriptionProviding`, `FeatureGate`, `PaywallView`, `ReviewReminderManager`
- Local testing config in `Configuration.storekit`

**Architectural insights**
- `ProjectAnalyzer`, `InsightEngine`, `SuggestionEngine`, `SuggestionDispatcher`
- Surfaced in `ProjectDashboardView`

**UI**
- Multiple sidebars (`WorkspaceSidebar`, `ExplorerSidebar`, `FileBrowserSidebar`, `HistorySidebar`)
- `DiagramInspectorStrip` + per-mode controls (`SequenceControlsView`, `ActivityControlsView`)
- `SourceEditorView`, `MarkupView`

**Concurrency migration**
- Whole app moved to Swift 6 strict concurrency (see CHANGELOG `[Unreleased]` and commit `846adfa`)
- `DiagramPresenting` protocol is now async; the original `SwiftUIPresenter.swift` was removed

The canonical functional spec for the Studio app is now PRD section 6 (`docs/internal/SwiftUML Studio PRD.md`). The MVP plan below is preserved for historical context.

---

# macOS Studio GUI — Initial Implementation (Historical, 2026-02)

## Context

M0 is complete (SwiftUMLBridge package, CLI, 89% test coverage). The next step is to build
the macOS SwiftUI front-end for the SwiftUMLBridge framework. The user wants:
- Single-window app
- Folder/file picker via NSOpenPanel to select Swift source
- Horizontal split view: left = raw PlantUML text, right = rendered SVG preview via planttext.com
- The framework's `ClassDiagramGenerator` and `DiagramPresenting` protocol are the integration points

---

## Architecture

Four files total — three new, one rewritten:

```
SwiftUMLStudio/
├── SwiftUMLStudioApp.swift   (minimal tweak: set window size)
├── ContentView.swift              (REWRITE — main window layout)
├── DiagramViewModel.swift         (NEW — @Observable state + generation logic)
├── SwiftUIPresenter.swift         (NEW — custom DiagramPresenting for SwiftUI)
└── DiagramWebView.swift           (NEW — NSViewRepresentable wrapping WKWebView)
```

---

## Implementation Plan

### 1. `SwiftUIPresenter.swift`

Implement `DiagramPresenting` to capture the `DiagramScript` instead of opening a browser.

```swift
import SwiftUMLBridgeFramework

struct SwiftUIPresenter: DiagramPresenting {
    var onScript: (DiagramScript) -> Void
    func present(script: DiagramScript, completionHandler: @escaping () -> Void) {
        onScript(script)
        completionHandler()
    }
}
```

### 2. `DiagramViewModel.swift`

`@Observable` class (macOS 26+) managing all state. Generation runs off the main actor since
`ClassDiagramGenerator.generate()` uses `DispatchSemaphore` internally (it's blocking).

```swift
import Observation
import SwiftUMLBridgeFramework

@Observable @MainActor
final class DiagramViewModel {
    var selectedPaths: [String] = []
    var script: DiagramScript? = nil
    var isGenerating: Bool = false
    var errorMessage: String? = nil

    func generate() {
        guard !selectedPaths.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        script = nil

        Task.detached { [paths = selectedPaths] in
            let generator = ClassDiagramGenerator()
            var captured: DiagramScript?
            let presenter = SwiftUIPresenter { captured = $0 }
            generator.generate(for: paths, with: .default, presentedBy: presenter)
            await MainActor.run {
                self.script = captured
                self.isGenerating = false
            }
        }
    }
}
```

### 3. `DiagramWebView.swift`

`NSViewRepresentable` wrapping `WKWebView`. Loads SVG URL from planttext.com using the
same encoding that `BrowserPresenter` uses (`script.encodeText()`).

```swift
import SwiftUI
import WebKit
import SwiftUMLBridgeFramework

struct DiagramWebView: NSViewRepresentable {
    var script: DiagramScript?

    func makeNSView(context: Context) -> WKWebView { WKWebView() }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let script, !script.text.isEmpty else { return }
        let encoded = script.encodeText()
        let urlString = "https://www.planttext.com/api/plantuml/svg/\(encoded)"
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
}
```

### 4. `ContentView.swift` (complete rewrite)

Main layout: toolbar + `HSplitView`. Left pane = plain `TextEditor` (read-only via
`.disabled(true)`) showing `script.text`. Right pane = `DiagramWebView`.

```
ContentView
├── toolbar:
│   ├── Button("Open...") → NSOpenPanel (canChooseDirectories: true, multiple: true)
│   ├── Text(selectedPaths summary)
│   └── Button("Generate") → viewModel.generate() [disabled when empty or generating]
└── HSplitView
    ├── ScrollView > TextEditor(viewModel.script?.text ?? "")  [.disabled(true)]
    └── Group
        ├── DiagramWebView(script: viewModel.script)         [when script != nil]
        └── ProgressView("Rendering…") or placeholder        [when script == nil]
```

Open panel configuration:
- `canChooseFiles = true`
- `canChooseDirectories = true`
- `allowsMultipleSelection = true`
- `allowedContentTypes = [.swiftSource]` (UTType)
- Map results to `panel.urls.map(\.path)` → `viewModel.selectedPaths`

### 5. `SwiftUMLStudioApp.swift` (minor)

Add `.defaultSize(width: 1100, height: 700)` to `WindowGroup` so the split view
has a useful default size.

---

## Files to Modify / Create

| File | Action | Purpose |
|---|---|---|
| `SwiftUMLStudio/ContentView.swift` | Rewrite | Main window with toolbar + HSplitView |
| `SwiftUMLStudio/SwiftUMLStudioApp.swift` | Minor edit | Set default window size |
| `SwiftUMLStudio/DiagramViewModel.swift` | Create | State + generation logic |
| `SwiftUMLStudio/SwiftUIPresenter.swift` | Create | Custom DiagramPresenting |
| `SwiftUMLStudio/DiagramWebView.swift` | Create | WKWebView wrapper |

No changes to SwiftUMLBridge package sources required — public API is sufficient.

---

## Key Framework Integration Points

- **Entry point**: `ClassDiagramGenerator.generate(for:with:presentedBy:)` in
  `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/ClassDiagramGenerator.swift`
- **Custom presenter protocol**: `DiagramPresenting` in
  `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/DiagramPresenting.swift`
- **Script output type**: `DiagramScript` in
  `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Emitters/DiagramScript.swift`
- **URL encoding**: `DiagramScript.encodeText()` — same encoding as BrowserPresenter uses
- **Renderer URL pattern**: `https://www.planttext.com/api/plantuml/svg/{encodedText}` (from BrowserPresenter)

---

## Verification

1. Build with Xcode: `xcodebuild -scheme SwiftUMLStudio -destination 'generic/platform=macOS' build`
2. Run the app — click "Open..." → select the `SwiftUMLBridge/Sources/SwiftUMLBridgeFramework/Model/` folder
3. Click "Generate" — left pane should fill with PlantUML script text, right pane should load an SVG diagram
4. Verify the split view is resizable
5. Run existing unit tests to confirm no regressions: `xcodebuild test -scheme SwiftUMLStudio -destination 'platform=macOS,arch=arm64'`
