import SwiftUI

/// Applies the pan/zoom transform and the magnify + drag gestures that drive a
/// `DiagramViewport`. Mirrors the order the renderers used inline:
/// `scaleEffect` → `offset` → magnify gesture → drag gesture.
struct CanvasPanZoom: ViewModifier {
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
