import SwiftUI
import SwiftUMLBridgeFramework

/// Floating "Export" menu attached to `DiagramPreviewView`. Presents PDF /
/// PNG / SVG / source options based on what the current script supports.
struct DiagramExportMenu: View {
    let viewModel: DiagramViewModel
    let viewport: DiagramViewport

    @State private var lastError: String?

    var body: some View {
        Menu {
            if hasNativeRenderableCanvas {
                Button("Export as PDF…") { export(.pdf) }
                Button("Export as PNG…") { export(.png) }
            }
            if hasSVGScript || hasNativeRenderableCanvas {
                Button("Export SVG…") { export(.svg) }
            }
            if hasSourceText {
                Button(sourceMenuLabel) { export(.source) }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
        .help("Export the current diagram")
        .accessibilityIdentifier("diagramExportMenu")
        .alert("Export failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) { lastError = nil }
        } message: {
            Text(lastError ?? "")
        }
    }

    // MARK: - Capability checks

    private var script: (any DiagramOutputting)? { viewModel.currentScript }

    private var hasNativeRenderableCanvas: Bool {
        guard let script, script.format == .svg else { return false }
        return script.layoutGraph != nil
            || script.sequenceLayout != nil
            || script.activityLayout != nil
    }

    private var hasSVGScript: Bool { script?.format == .svg }

    private var hasSourceText: Bool {
        guard let script else { return false }
        return script.format != .svg && !script.text.isEmpty
    }

    private var sourceMenuLabel: String {
        let ext = DiagramExporter.sourceExtension(for: script?.format.rawValue ?? "txt")
        return "Export source (.\(ext))…"
    }

    private var suggestedName: String {
        switch viewModel.diagramMode {
        case .classDiagram: return "class-diagram"
        case .sequenceDiagram: return "sequence-diagram"
        case .activityDiagram: return "activity-diagram"
        case .stateMachine: return "state-machine"
        case .erDiagram: return "er-diagram"
        case .dependencyGraph: return "dependency-graph"
        }
    }

    // MARK: - Export

    private func export(_ kind: DiagramExportKind) {
        switch kind {
        case .pdf, .png:
            exportRaster(kind)
        case .svg:
            exportSVG()
        case .source:
            exportSource()
        }
    }

    private func exportRaster(_ kind: DiagramExportKind) {
        guard let url = DiagramExporter.runSavePanel(kind: kind, suggestedName: suggestedName) else {
            return
        }
        guard let size = nativeContentSize(),
              let data = renderData(kind: kind, size: size)
        else {
            lastError = "No native diagram is currently displayed."
            return
        }
        do {
            try data.write(to: url)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func exportSVG() {
        guard let url = DiagramExporter.runSavePanel(kind: .svg, suggestedName: suggestedName) else {
            return
        }
        guard let text = script?.text, !text.isEmpty, script?.format == .svg else {
            lastError = "The current diagram has no SVG source."
            return
        }
        do {
            try DiagramExporter.writeText(text, to: url)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func exportSource() {
        guard let script, !script.text.isEmpty else { return }
        let kind = DiagramExportKind.source
        let formatExtension = DiagramExporter.sourceExtension(for: script.format.rawValue)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [kind.contentType]
        panel.nameFieldStringValue = "\(suggestedName).\(formatExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagramExporter.writeText(script.text, to: url)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Renderer

    /// Returns the natural canvas size of whichever native layout is active.
    private func nativeContentSize() -> CGSize? {
        guard let script, script.format == .svg else { return nil }
        if let graph = script.layoutGraph {
            return CGSize(width: max(graph.width + 40, 200), height: max(graph.height + 40, 200))
        }
        if let sequence = script.sequenceLayout {
            return CGSize(
                width: max(sequence.totalWidth + 40, 200),
                height: max(sequence.totalHeight + 40, 200)
            )
        }
        if let activity = script.activityLayout {
            return CGSize(
                width: max(activity.totalWidth + 40, 200),
                height: max(activity.totalHeight + 40, 200)
            )
        }
        return nil
    }

    /// Renders the current native diagram into PDF or PNG bytes at its natural
    /// size, with an identity viewport (no zoom / pan applied to the export).
    @MainActor
    private func renderData(kind: DiagramExportKind, size: CGSize) -> Data? {
        let identityViewport = DiagramViewport()
        guard let script, script.format == .svg else { return nil }

        let view: AnyView
        if let graph = script.layoutGraph {
            view = AnyView(NativeDiagramView(graph: graph, viewport: identityViewport))
        } else if let sequence = script.sequenceLayout {
            view = AnyView(NativeSequenceDiagramView(layout: sequence, viewport: identityViewport))
        } else if let activity = script.activityLayout {
            view = AnyView(NativeActivityDiagramView(layout: activity, viewport: identityViewport))
        } else {
            return nil
        }

        switch kind {
        case .pdf:
            return DiagramExporter.renderPDF(view, size: size)
        case .png:
            return DiagramExporter.renderPNG(view, size: size)
        default:
            return nil
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { lastError != nil },
            set: { if !$0 { lastError = nil } }
        )
    }
}
