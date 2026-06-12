import SwiftUI

/// The full non-interactive native-canvas body: a `GeometryReader` that sizes a
/// `Canvas` to the larger of the content (plus `margin`) and the available
/// space, then applies pan/zoom, double-tap-to-reset, and the shared chrome.
///
/// Used by the activity and component renderers. The class and sequence
/// renderers add selection / hover / keyboard affordances whose modifier order
/// matters for hit-testing, so they keep their bodies inline.
struct DiagramCanvasContainer: View {
    let viewport: DiagramViewport
    let contentSize: CGSize
    var margin: Double = 40
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let draw: (inout GraphicsContext) -> Void

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(contentSize.width + margin, Double(geometry.size.width))
            let canvasHeight = max(contentSize.height + margin, Double(geometry.size.height))

            Canvas { context, _ in
                draw(&context)
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .canvasPanZoom(viewport: viewport)
            .onTapGesture(count: 2) { viewport.reset() }
            .diagramCanvasChrome(
                viewport: viewport,
                contentSize: contentSize,
                visibleSize: geometry.size,
                label: accessibilityLabel,
                identifier: accessibilityIdentifier
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
