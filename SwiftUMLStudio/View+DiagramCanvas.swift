import SwiftUI

// Shared chrome for the native `Canvas`-based diagram renderers
// (`NativeDiagramView`, `NativeSequenceDiagramView`,
// `NativeActivityDiagramView`, `NativeComponentDiagramView`). Each renderer
// differs in its drawing and in which interactive affordances it offers
// (selection, hover, keyboard navigation, shared through
// `SelectableDiagramCanvas`), but they share the pan/zoom transform and the
// viewport-syncing accessibility tail extracted here.

extension View {
    /// Apply the shared pan/zoom transform and gestures for a diagram canvas.
    func canvasPanZoom(viewport: DiagramViewport) -> some View {
        modifier(CanvasPanZoom(viewport: viewport))
    }

    /// Apply the shared accessibility + viewport-size-syncing chrome for a
    /// diagram canvas. `visibleSize` is the enclosing geometry's size.
    func diagramCanvasChrome(
        viewport: DiagramViewport,
        contentSize: CGSize,
        visibleSize: CGSize,
        label: String,
        identifier: String
    ) -> some View {
        modifier(DiagramCanvasChrome(
            viewport: viewport,
            contentSize: contentSize,
            visibleSize: visibleSize,
            label: label,
            identifier: identifier
        ))
    }
}
