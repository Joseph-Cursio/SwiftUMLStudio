import SwiftUI

/// Shared chrome for the native `Canvas`-based diagram renderers
/// (`NativeDiagramView`, `NativeSequenceDiagramView`,
/// `NativeActivityDiagramView`, `NativeComponentDiagramView`). Each renderer
/// differs in its drawing and in which interactive affordances it offers
/// (selection, hover, keyboard navigation), but they share the pan/zoom
/// transform and the viewport-syncing accessibility tail extracted here.

/// Applies the pan/zoom transform and the magnify + drag gestures that drive a
/// `DiagramViewport`. Mirrors the order the renderers used inline:
/// `scaleEffect` → `offset` → magnify gesture → drag gesture.
private struct CanvasPanZoom: ViewModifier {
    let viewport: DiagramViewport

    func body(content: Content) -> some View {
        content
            .scaleEffect(viewport.scale)
            .offset(viewport.offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { viewport.updateScale(magnification: $0.magnification) }
                    .onEnded { _ in viewport.commitScale() }
            )
            .gesture(
                DragGesture()
                    .onChanged { viewport.updateOffset(translation: $0.translation) }
                    .onEnded { _ in viewport.commitOffset() }
            )
    }
}

/// The trailing canvas chrome shared by every renderer: button accessibility
/// metadata and the `onAppear`/`onChange` wiring that keeps the viewport's
/// content and visible sizes in sync with the geometry.
private struct DiagramCanvasChrome: ViewModifier {
    let viewport: DiagramViewport
    let contentSize: CGSize
    let visibleSize: CGSize
    let label: String
    let identifier: String

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityHint("Double-tap to reset zoom and position")
            .accessibilityIdentifier(identifier)
            .onAppear {
                viewport.contentSize = contentSize
                viewport.visibleSize = visibleSize
            }
            .onChange(of: visibleSize) { _, newSize in
                viewport.visibleSize = newSize
            }
    }
}

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
