import SwiftUI

/// Floating zoom/pan toolbar overlay for the native diagram canvases.
/// Sits in the top-trailing corner of `DiagramPreviewView`.
struct DiagramViewportControls: View {
    @Bindable var viewport: DiagramViewport

    var body: some View {
        HStack(spacing: 4) {
            Button {
                viewport.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
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
                Image(systemName: "plus.magnifyingglass")
            }
            .keyboardShortcut("=", modifiers: .command)
            .help("Zoom in (⌘=)")
            .accessibilityIdentifier("viewportZoomIn")

            Divider().frame(height: 18).padding(.horizontal, 4)

            Button {
                viewport.fitToWindow()
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .keyboardShortcut("9", modifiers: .command)
            .help("Fit to window (⌘9)")
            .accessibilityIdentifier("viewportFit")

            Button {
                viewport.actualSize()
            } label: {
                Image(systemName: "1.magnifyingglass")
            }
            .keyboardShortcut("0", modifiers: .command)
            .help("Actual size (⌘0)")
            .accessibilityIdentifier("viewportActualSize")

            Button {
                viewport.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
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
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagramViewportControls")
    }
}
