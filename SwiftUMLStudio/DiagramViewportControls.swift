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
            controlButton(.zoomOut) { viewport.zoomOut() }

            Text(viewport.zoomPercentLabel)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48)
                .accessibilityIdentifier("viewportZoomLabel")

            controlButton(.zoomIn) { viewport.zoomIn() }

            Divider().frame(height: 18).padding(.horizontal, 4)

            controlButton(.fitToWindow) { viewport.fitToWindow() }
            controlButton(.actualSize) { viewport.actualSize() }
            controlButton(.reset) { viewport.reset() }
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

    private func controlButton(_ control: Control, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(control.title, systemImage: control.systemImage)
                .labelStyle(.iconOnly)
        }
        .keyboardShortcut(control.shortcut)
        .help(control.help)
        .accessibilityIdentifier(control.identifier)
    }

    /// What one of the toolbar's icon-only buttons shows, the key that presses it, and how
    /// tests find it.
    private struct Control {
        let title: String
        let systemImage: String
        let shortcut: KeyboardShortcut
        let help: String
        let identifier: String

        static let zoomOut = Control(
            title: "Zoom Out", systemImage: "minus.magnifyingglass",
            shortcut: KeyboardShortcut("-"), help: "Zoom out (⌘−)", identifier: "viewportZoomOut"
        )
        static let zoomIn = Control(
            title: "Zoom In", systemImage: "plus.magnifyingglass",
            shortcut: KeyboardShortcut("="), help: "Zoom in (⌘=)", identifier: "viewportZoomIn"
        )
        static let fitToWindow = Control(
            title: "Fit to Window", systemImage: "arrow.up.left.and.down.right.magnifyingglass",
            shortcut: KeyboardShortcut("9"), help: "Fit to window (⌘9)", identifier: "viewportFit"
        )
        static let actualSize = Control(
            title: "Actual Size", systemImage: "1.magnifyingglass",
            shortcut: KeyboardShortcut("0"), help: "Actual size (⌘0)", identifier: "viewportActualSize"
        )
        static let reset = Control(
            title: "Reset Zoom and Pan", systemImage: "arrow.counterclockwise",
            shortcut: KeyboardShortcut("r", modifiers: [.command, .shift]),
            help: "Reset zoom and pan (⇧⌘R)", identifier: "viewportReset"
        )
    }
}
