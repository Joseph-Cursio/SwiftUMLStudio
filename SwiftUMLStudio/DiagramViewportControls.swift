import SwiftUI

/// Floating zoom/pan toolbar overlay for the native diagram canvases.
/// Sits in the top-trailing corner of `DiagramPreviewView`.
///
/// Each button shows only its icon, but names itself through its `Label`, so VoiceOver
/// reads "Zoom In" rather than the symbol's name.
struct DiagramViewportControls: View {
    @Bindable var viewport: DiagramViewport

    var body: some View {
        HStack(spacing: 4) {
            Button {
                viewport.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom out (⌘−)")
            .accessibilityIdentifier("viewportZoomOut")

            Text(viewport.zoomPercentLabel)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48)
                .accessibilityIdentifier("viewportZoomLabel")

            Button {
                viewport.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("=", modifiers: .command)
            .help("Zoom in (⌘=)")
            .accessibilityIdentifier("viewportZoomIn")

            Divider().frame(height: 18).padding(.horizontal, 4)

            Button {
                viewport.fitToWindow()
            } label: {
                Label("Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("9", modifiers: .command)
            .help("Fit to window (⌘9)")
            .accessibilityIdentifier("viewportFit")

            Button {
                viewport.actualSize()
            } label: {
                Label("Actual Size", systemImage: "1.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Actual size (⌘0)")
            .accessibilityIdentifier("viewportActualSize")

            Button {
                viewport.reset()
            } label: {
                Label("Reset Zoom and Pan", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Reset zoom and pan (⇧⌘R)")
            .accessibilityIdentifier("viewportReset")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagramViewportControls")
    }
}
